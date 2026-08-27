import { fetchVodDetail, searchVod } from "./maccms";
import { mergePlaySourcesFromVods } from "./parser";
import { getEnabledSources } from "./sources";
import type {
  MergeableVodItem,
  MergedVodItem,
  PlaySource,
  Source,
  VodItem,
  VodVariant,
} from "./types";

const MAX_VARIANTS = 10;

export function normalizeVodTitle(name?: string): string {
  if (!name) return "";
  return name
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "")
    .replace(/[·・:：\-—_]/g, "");
}

export function buildVodMergeKey(
  item: Pick<VodItem, "vod_name" | "type_name" | "vod_year">
): string {
  // 跨资源站时 type_name / vod_year 常不一致（如动作片 vs 恐怖片），
  // 仅按片名合并；季数差异通常已体现在片名中（如「第二季」）。
  return normalizeVodTitle(item.vod_name);
}

function countPlayLines(item: VodItem): number {
  const from = item.vod_play_from ?? "";
  if (!from) return 0;
  if (from.includes("$$$")) return from.split("$$$").filter(Boolean).length;
  if (from.includes(",")) return from.split(",").filter(Boolean).length;
  return 1;
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

  return variants;
}

export function mergeVodItems(items: MergeableVodItem[]): MergedVodItem[] {
  const sourceOrder = getSourceOrder();
  const groups = new Map<string, MergeableVodItem[]>();

  for (const item of items) {
    const key = buildVodMergeKey(item);
    const group = groups.get(key) ?? [];
    group.push(item);
    groups.set(key, group);
  }

  const merged: MergedVodItem[] = [];

  for (const group of groups.values()) {
    const primary = pickPrimaryItem(group, sourceOrder);
    const variants = buildVariants(group);
    const primarySourceId =
      primary.sourceId ?? variants[0]?.sourceId ?? 0;

    merged.push({
      ...primary,
      variants,
      primarySourceId,
    });
  }

  return merged;
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

  const mergeKey = buildVodMergeKey(primary);
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

  const searchResults = await Promise.allSettled(
    sources.map(async (searchSource) => {
      const data = await searchVod(searchSource, primary.vod_name, 1);
      return (data.list ?? [])
        .filter((item) => buildVodMergeKey(item) === mergeKey)
        .map((item) => ({
          source: searchSource,
          vodId: String(item.vod_id),
        }));
    })
  );

  for (const result of searchResults) {
    if (result.status !== "fulfilled") continue;
    for (const match of result.value) {
      addMatch(match.source, match.vodId);
      if (matches.length >= MAX_VARIANTS) break;
    }
    if (matches.length >= MAX_VARIANTS) break;
  }

  const details = await Promise.allSettled(
    matches.map(async ({ source: matchSource, vodId: matchVodId }) => {
      if (matchSource.id === source.id && matchVodId === vodId) {
        return { source: matchSource, vod: primary };
      }

      const data = await fetchVodDetail(matchSource, matchVodId);
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
    .map((result) => result.value);

  const playSources = mergePlaySourcesFromVods(vodsWithSource);
  const bestVod = pickBestVodMetadata(vodsWithSource.map((entry) => entry.vod));
  const variants = vodsWithSource.map((entry) => ({
    sourceId: entry.source.id,
    sourceName: entry.source.name,
    vodId: String(entry.vod.vod_id),
  }));

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

export function getVariantSourceNames(item: MergedVodItem): string[] {
  return [...new Set(item.variants.map((variant) => variant.sourceName).filter(Boolean))];
}
