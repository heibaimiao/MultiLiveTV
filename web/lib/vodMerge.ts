import { fetchVodDetail, searchVod, MACCMS_MERGE_TIMEOUT_MS } from "./maccms";
import { mergePlaySourcesFromVods } from "./parser";
import { enrichOfficialPlaySources, bpz5Configured } from "./bpz5";
import { sortPlaySources, sourceWeight } from "./playLineWeights";
import { getEnabledSources } from "./sources";
import type {
  MergeableVodItem,
  MergedVodItem,
  PlaySource,
  Source,
  VodItem,
  VodVariant,
} from "./types";

const MAX_VARIANTS = 16;

export function normalizeVodTitle(name?: string): string {
  if (!name) return "";
  return name
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "")
    .replace(/[·・:：\-—_]/g, "");
}

export function normalizeVodYear(year?: string, nowYear = new Date().getFullYear()): string {
  if (!year) return "";
  const match = year.trim().match(/\d{4}/);
  if (!match) return "";
  const value = Number(match[0]);
  if (!Number.isFinite(value) || !isDisplayableReleaseYear(value, nowYear)) return "";
  return match[0];
}

/** Hide CMS placeholder years on cards; keep next calendar year for unreleased titles. */
export function isDisplayableReleaseYear(year: number, nowYear = new Date().getFullYear()): boolean {
  return year >= 1900 && year <= nowYear + 1;
}

/** @deprecated use isDisplayableReleaseYear */
export function isPlausibleReleaseYear(year: number, nowYear = new Date().getFullYear()): boolean {
  return isDisplayableReleaseYear(year, nowYear);
}

export function buildVodMergeKey(
  item: Pick<VodItem, "vod_name" | "type_name" | "vod_year">
): string {
  const title = normalizeVodTitle(item.vod_name);
  const year = normalizeVodYear(item.vod_year);
  return year ? `${title}|${year}` : title;
}

/** 详情跨源合并：标题相同；年份缺一侧或相等即可（避免搜索结果无年份时丢源） */
export function isCompatibleVodMatch(
  primary: Pick<VodItem, "vod_name" | "vod_year">,
  candidate: Pick<VodItem, "vod_name" | "vod_year">
): boolean {
  if (normalizeVodTitle(primary.vod_name) !== normalizeVodTitle(candidate.vod_name)) {
    return false;
  }
  const primaryYear = normalizeVodYear(primary.vod_year);
  const candidateYear = normalizeVodYear(candidate.vod_year);
  if (!primaryYear || !candidateYear) return true;
  return primaryYear === candidateYear;
}

function countPlayLines(item: VodItem): number {
  const from = item.vod_play_from ?? "";
  if (!from) return 0;
  if (from.includes("$$$")) return from.split("$$$").filter(Boolean).length;
  if (from.includes(",")) return from.split(",").filter(Boolean).length;
  return 1;
}

/** Parse MacCMS vod_time / vod_time_add to unix seconds (0 if unknown). */
export function parseVodTimeSec(value?: string | number | null): number {
  if (value == null) return 0;
  if (typeof value === "number" && Number.isFinite(value)) {
    if (value <= 0) return 0;
    return value > 10_000_000_000 ? Math.floor(value / 1000) : Math.floor(value);
  }
  const raw = String(value).trim();
  if (!raw) return 0;
  if (/^\d+$/.test(raw)) {
    const n = Number(raw);
    if (n <= 0) return 0;
    return n > 10_000_000_000 ? Math.floor(n / 1000) : n;
  }
  const parts = raw.split(/[^\d]+/).map(Number).filter((n) => Number.isFinite(n));
  if (parts.length < 3) return 0;
  const [year, month, day, hour = 0, minute = 0, second = 0] = parts;
  // Asia/Shanghai = UTC+8
  const ms = Date.UTC(year, month - 1, day, hour - 8, minute, second);
  if (!Number.isFinite(ms)) return 0;
  return Math.floor(ms / 1000);
}

export function vodUpdatedAtSec(
  item: Pick<VodItem, "vod_time" | "vod_time_add">
): number {
  return Math.max(
    parseVodTimeSec(item.vod_time),
    parseVodTimeSec(item.vod_time_add)
  );
}

export function vodYearValue(year?: string): number {
  const normalized = normalizeVodYear(year);
  if (!normalized) return 0;
  const n = Number(normalized);
  return Number.isFinite(n) ? n : 0;
}

function rawYearDigits(year?: string): string {
  if (!year) return "";
  return year.trim().match(/\d{4}/)?.[0] ?? "";
}

function yearFromVodTimeSec(sec: number, fallback: number): number {
  if (sec <= 0) return fallback;
  return new Date(sec * 1000).getFullYear();
}

/** Ranking year: future placeholders use the current year so recent films stay near top. */
export function sortYearValue(
  year?: string,
  vodTime?: string | number | null,
  nowYear = new Date().getFullYear()
): number {
  const digits = rawYearDigits(year);
  if (digits) {
    const value = Number(digits);
    if (value >= 1900 && value <= nowYear + 1) return value;
    if (value > nowYear + 1) return nowYear;
  }
  return yearFromVodTimeSec(parseVodTimeSec(vodTime), 0);
}

export function sortMergedByUpdatedDesc(
  items: MergedVodItem[]
): MergedVodItem[] {
  return [...items]
    .map((item, index) => ({ item, index }))
    .sort((a, b) => {
      const ay = sortYearValue(a.item.vod_year, a.item.vod_time ?? a.item.vod_time_add);
      const by = sortYearValue(b.item.vod_year, b.item.vod_time ?? b.item.vod_time_add);
      if (ay !== by) return by - ay;
      const at = vodUpdatedAtSec(a.item);
      const bt = vodUpdatedAtSec(b.item);
      if (at !== bt) return bt - at;
      return a.index - b.index;
    })
    .map(({ item }) => item);
}

function pickLatestTimeRaw(
  items: MergeableVodItem[]
): string | number | undefined {
  let best = 0;
  let raw: string | number | undefined;
  for (const item of items) {
    for (const candidate of [item.vod_time, item.vod_time_add]) {
      const sec = parseVodTimeSec(candidate);
      if (sec > best) {
        best = sec;
        raw = candidate;
      }
    }
  }
  return raw;
}

function getSourceOrder(): Map<number, number> {
  return new Map(getEnabledSources().map((source, index) => [source.id, index]));
}

function pickPrimaryItem(
  items: MergeableVodItem[],
  sourceOrder: Map<number, number>
): MergeableVodItem {
  return [...items].sort((a, b) => {
    const aPic = a.vod_pic ? 1 : 0;
    const bPic = b.vod_pic ? 1 : 0;
    if (bPic !== aPic) return bPic - aPic;

    const aWeight = sourceWeight(a.sourceId ?? 0);
    const bWeight = sourceWeight(b.sourceId ?? 0);
    if (bWeight !== aWeight) return bWeight - aWeight;

    const aLines = countPlayLines(a);
    const bLines = countPlayLines(b);
    if (bLines !== aLines) return bLines - aLines;

    const aOrder = sourceOrder.get(a.sourceId ?? 0) ?? 999;
    const bOrder = sourceOrder.get(b.sourceId ?? 0) ?? 999;
    return aOrder - bOrder;
  })[0];
}

function pickBestVodMetadata(items: VodItem[]): VodItem {
  return [...items].sort((a, b) => {
    const aPic = a.vod_pic ? 1 : 0;
    const bPic = b.vod_pic ? 1 : 0;
    if (bPic !== aPic) return bPic - aPic;

    const aContent = (a.vod_content ?? a.vod_blurb ?? "").length;
    const bContent = (b.vod_content ?? b.vod_blurb ?? "").length;
    return bContent - aContent;
  })[0];
}

function buildVariants(items: MergeableVodItem[]): VodVariant[] {
  const variants: VodVariant[] = [];
  const seen = new Set<string>();

  for (const item of items) {
    const sourceId = item.sourceId ?? 0;
    if (!sourceId) continue;

    const vodId = String(item.vod_id);
    const key = `${sourceId}:${vodId}`;
    if (seen.has(key)) continue;

    seen.add(key);
    variants.push({
      sourceId,
      sourceName: item.sourceName ?? "",
      vodId,
    });
  }

  return variants.sort(
    (a, b) => sourceWeight(b.sourceId) - sourceWeight(a.sourceId)
  );
}

export function mergeVodItems(items: MergeableVodItem[]): MergedVodItem[] {
  const sourceOrder = getSourceOrder();
  const { groups, order } = groupMergeableItems(items);
  const merged: MergedVodItem[] = [];

  for (const key of order) {
    const group = groups.get(key) ?? [];
    const primary = pickPrimaryItem(group, sourceOrder);
    const variants = buildVariants(group);
    const primarySourceId =
      primary.sourceId ?? variants[0]?.sourceId ?? 0;
    const latestTime = pickLatestTimeRaw(group);
    const year =
      normalizeVodYear(primary.vod_year) ||
      group
        .map((item) => normalizeVodYear(item.vod_year))
        .filter(Boolean)
        .sort((a, b) => vodYearValue(b) - vodYearValue(a))[0] ||
      primary.vod_year;

    merged.push({
      ...primary,
      ...(year ? { vod_year: year } : {}),
      ...(latestTime !== undefined ? { vod_time: latestTime } : {}),
      variants,
      primarySourceId,
    });
  }

  return merged;
}

function groupMergeableItems(items: MergeableVodItem[]): {
  groups: Map<string, MergeableVodItem[]>;
  order: string[];
} {
  const byTitle = new Map<string, MergeableVodItem[]>();
  const titleOrder: string[] = [];

  for (const item of items) {
    const title = normalizeVodTitle(item.vod_name);
    if (!title) continue;
    if (!byTitle.has(title)) {
      titleOrder.push(title);
      byTitle.set(title, []);
    }
    byTitle.get(title)!.push(item);
  }

  const groups = new Map<string, MergeableVodItem[]>();
  const order: string[] = [];

  for (const title of titleOrder) {
    const group = byTitle.get(title) ?? [];
    const concreteYears = orderedUniqueYears(group);
    if (concreteYears.length <= 1) {
      const key = concreteYears[0] ? `${title}|${concreteYears[0]}` : title;
      order.push(key);
      groups.set(key, group);
      continue;
    }

    const byYear = new Map<string, MergeableVodItem[]>();
    const yearOrder: string[] = [];
    const emptyYear: MergeableVodItem[] = [];
    for (const entry of group) {
      const year = normalizeVodYear(entry.vod_year);
      if (!year) {
        emptyYear.push(entry);
        continue;
      }
      if (!byYear.has(year)) {
        yearOrder.push(year);
        byYear.set(year, []);
      }
      byYear.get(year)!.push(entry);
    }

    if (emptyYear.length) {
      let target = yearOrder[0];
      let bestTime = Math.max(
        ...((byYear.get(target) ?? []).map((item) => vodUpdatedAtSec(item))),
        0
      );
      for (const year of yearOrder.slice(1)) {
        const t = Math.max(
          ...((byYear.get(year) ?? []).map((item) => vodUpdatedAtSec(item))),
          0
        );
        if (t > bestTime) {
          bestTime = t;
          target = year;
        }
      }
      byYear.get(target)!.push(...emptyYear);
    }

    for (const year of yearOrder) {
      const key = `${title}|${year}`;
      order.push(key);
      groups.set(key, byYear.get(year) ?? []);
    }
  }

  return { groups, order };
}

function orderedUniqueYears(group: MergeableVodItem[]): string[] {
  const seen = new Set<string>();
  const years: string[] = [];
  for (const entry of group) {
    const year = normalizeVodYear(entry.vod_year);
    if (!year || seen.has(year)) continue;
    seen.add(year);
    years.push(year);
  }
  return years;
}

export interface MergedVodDetailResult {
  vod: VodItem;
  playSources: PlaySource[];
  primarySourceId: number;
  variants: VodVariant[];
}

export async function fetchMergedVodDetail(
  source: Source,
  vodId: string
): Promise<MergedVodDetailResult | null> {
  const primaryData = await fetchVodDetail(source, vodId);
  const primary = primaryData.list?.[0];
  if (!primary) return null;

  const sources = getEnabledSources();
  const matches: Array<{ source: Source; vodId: string }> = [];
  const seen = new Set<string>();

  const addMatch = (matchSource: Source, matchVodId: string) => {
    const key = `${matchSource.id}:${matchVodId}`;
    if (seen.has(key)) return;
    seen.add(key);
    matches.push({ source: matchSource, vodId: matchVodId });
  };

  addMatch(source, vodId);

  // Prefer high-weight sources first; stop once we have enough matches or hit
  // the merge timeout so one slow MacCMS host cannot block detail.
  const searchSources = [...sources].sort(
    (a, b) => sourceWeight(b.id) - sourceWeight(a.id)
  );

  await new Promise<void>((resolve) => {
    let remaining = searchSources.length;
    if (remaining === 0) {
      resolve();
      return;
    }
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      resolve();
    };
    const deadline = setTimeout(finish, MACCMS_MERGE_TIMEOUT_MS);

    for (const searchSource of searchSources) {
      searchVod(
        searchSource,
        primary.vod_name,
        1,
        MACCMS_MERGE_TIMEOUT_MS
      )
        .then((data) => {
          if (settled) return;
          for (const item of data.list ?? []) {
            if (!isCompatibleVodMatch(primary, item)) continue;
            addMatch(searchSource, String(item.vod_id));
            if (matches.length >= MAX_VARIANTS) {
              finish();
              return;
            }
          }
        })
        .catch(() => {
          /* ignore slow/failed sources */
        })
        .finally(() => {
          remaining -= 1;
          if (remaining <= 0) finish();
        });
    }
  });

  const details = await Promise.allSettled(
    matches.map(async ({ source: matchSource, vodId: matchVodId }) => {
      if (matchSource.id === source.id && matchVodId === vodId) {
        return { source: matchSource, vod: primary };
      }

      const data = await fetchVodDetail(
        matchSource,
        matchVodId,
        MACCMS_MERGE_TIMEOUT_MS
      );
      const vod = data.list?.[0];
      if (!vod) throw new Error("Vod not found");
      return { source: matchSource, vod };
    })
  );

  const vodsWithSource = details
    .filter(
      (
        result
      ): result is PromiseFulfilledResult<{
        source: Source;
        vod: VodItem;
      }> => result.status === "fulfilled"
    )
    .map((result) => result.value)
    // 详情里的年份更准：二次过滤，避免搜索无年份误并入其它年份同名片
    .filter((entry) => isCompatibleVodMatch(primary, entry.vod));

  const bestVod = pickBestVodMetadata(
    vodsWithSource.length
      ? vodsWithSource.map((entry) => entry.vod)
      : [primary]
  );
  let playSources = mergePlaySourcesFromVods(vodsWithSource);
  if (bpz5Configured()) {
    const official = await enrichOfficialPlaySources(bestVod, playSources);
    if (official.length) {
      playSources = sortPlaySources([...official, ...playSources]);
    }
  }

  const variants = vodsWithSource
    .map((entry) => ({
      sourceId: entry.source.id,
      sourceName: entry.source.name,
      vodId: String(entry.vod.vod_id),
    }))
    .sort((a, b) => sourceWeight(b.sourceId) - sourceWeight(a.sourceId));

  return {
    vod: {
      ...bestVod,
      vod_id: primary.vod_id,
      vod_name: primary.vod_name,
    },
    playSources,
    primarySourceId: source.id,
    variants,
  };
}

export function getPrimaryVariant(item: MergedVodItem): VodVariant | undefined {
  return (
    item.variants.find((variant) => variant.sourceId === item.primarySourceId) ??
    item.variants[0]
  );
}

export function getVariantSourceNames(
  item: MergedVodItem,
  limit = 0
): string[] {
  const names = [
    ...new Set(
      [...item.variants]
        .sort((a, b) => sourceWeight(b.sourceId) - sourceWeight(a.sourceId))
        .map((variant) => variant.sourceName)
        .filter(Boolean)
    ),
  ];
  if (limit > 0 && names.length > limit) {
    return names.slice(0, limit);
  }
  return names;
}

export function formatSourceMetaLabel(
  item: MergedVodItem,
  limit = 2
): string {
  const names = getVariantSourceNames(item);
  if (!names.length) return "";
  if (names.length <= limit) return names.join(" · ");
  const head = names.slice(0, limit).join(" · ");
  return `${head} · 等${names.length}个源`;
}
