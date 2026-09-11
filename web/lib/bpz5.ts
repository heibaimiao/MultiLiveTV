/**
 * bpz5 / souju ticket resolver + official-line enrich (server-side only).
 * Docs: docs/souju-playback-api.md
 */

import crypto from "crypto";
import type { Episode, PlaySource, VodItem } from "@/lib/types";
import { annotatePlaySource, sortPlaySources } from "@/lib/playLineWeights";

const DEFAULT_BASE = "https://bpz5.com";
const DEFAULT_CLIENT = "movie-search-frontend";
const MATCH_THRESHOLD = 80;
const MAX_EPISODES = 40;

let cookieJar = "";
let anonymousId = "";
let sessionReady = false;

export function normalizeTicket(
  ticket?: string | null,
  fallbackUrl?: string | null
): string {
  let t = (ticket ?? "").trim();
  if (!t) t = (fallbackUrl ?? "").trim();
  if (t.startsWith("resolve://")) t = t.slice("resolve://".length).trim();
  return t;
}

function baseURL() {
  return (process.env.BPZ5_BASE_URL || DEFAULT_BASE).replace(/\/$/, "");
}

function secret() {
  return process.env.BPZ5_HMAC_SECRET?.trim() || "";
}

export function bpz5Configured(): boolean {
  return Boolean(secret());
}

function signHeaders(method: string, url: string) {
  const parsed = new URL(url);
  const path = parsed.pathname + parsed.search;
  const ts = String(Date.now());
  const nonce = crypto.randomBytes(16).toString("hex");
  const payload = `${method}\n${path}\n${ts}\n${nonce}`;
  const sig = crypto.createHmac("sha256", secret()).update(payload).digest("hex");
  const origin = `${parsed.protocol}//${parsed.host}`;
  const headers: Record<string, string> = {
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    Accept: "application/json",
    Origin: origin,
    Referer: `${origin}/`,
    "x-ai-movie-timestamp": ts,
    "x-ai-movie-nonce": nonce,
    "x-ai-movie-signature": sig,
    "x-ai-movie-client-name": DEFAULT_CLIENT,
  };
  if (cookieJar) headers.Cookie = cookieJar;
  return headers;
}

function absorbCookies(res: Response) {
  const anyHeaders = res.headers as Headers & { getSetCookie?: () => string[] };
  const list =
    typeof anyHeaders.getSetCookie === "function"
      ? anyHeaders.getSetCookie()
      : [];
  if (!list.length) {
    const single = res.headers.get("set-cookie");
    if (single) list.push(single);
  }
  if (!list.length) return;
  const jar = new Map<string, string>();
  for (const part of cookieJar.split(";").map((s) => s.trim()).filter(Boolean)) {
    const i = part.indexOf("=");
    if (i > 0) jar.set(part.slice(0, i), part.slice(i + 1));
  }
  for (const raw of list) {
    const first = raw.split(";")[0];
    const i = first.indexOf("=");
    if (i > 0) jar.set(first.slice(0, i), first.slice(i + 1));
  }
  cookieJar = Array.from(jar.entries())
    .map(([k, v]) => `${k}=${v}`)
    .join("; ");
}

async function bpz5Fetch(
  method: string,
  path: string,
  body?: unknown
): Promise<{ status: number; json: any }> {
  if (!bpz5Configured()) throw new Error("ticket_not_enabled");
  const endpoint = `${baseURL()}${path}`;
  const headers = signHeaders(method, endpoint);
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  absorbCookies(res);
  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

async function ensureAnonymousSession(force = false) {
  if (sessionReady && !force) return;
  if (!anonymousId) anonymousId = crypto.randomBytes(16).toString("hex");
  const { status } = await bpz5Fetch("POST", "/v1/users/anonymous", {
    anonymous_id: anonymousId,
  });
  sessionReady = status < 400;
}

export async function resolveBpz5Ticket(ticket: string): Promise<{
  url: string;
  urlKind?: string;
}> {
  const normalized = normalizeTicket(ticket);
  if (!normalized) throw new Error("ticket is required");
  await ensureAnonymousSession(false);
  let { status, json } = await bpz5Fetch("POST", "/v1/playback/resolve-line", {
    ticket: normalized,
  });
  if (status === 401) {
    await ensureAnonymousSession(true);
    ({ status, json } = await bpz5Fetch("POST", "/v1/playback/resolve-line", {
      ticket: normalized,
    }));
  }
  if (status !== 200 && status !== 201) {
    throw new Error(`bpz5 upstream HTTP ${status}`);
  }
  const url = json?.line?.url?.trim();
  if (!url) throw new Error("bpz5 missing line.url");
  return { url, urlKind: json.line?.url_kind };
}

function normalizeTitle(name: string): string {
  return name
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "")
    .replace(/[·・:：\-—_]/g, "");
}

function normalizeYear(year?: string | number | null): string {
  const digits = String(year ?? "").replace(/\D/g, "");
  return digits.slice(0, 4);
}

function scoreTitle(query: string, candidate: string): number {
  if (!query || !candidate) return 0;
  if (query === candidate) return 100;
  if (candidate.includes(query) || query.includes(candidate)) {
    const diff = Math.abs([...candidate].length - [...query].length);
    return Math.max(50, 90 - diff * 3);
  }
  return 0;
}

function isOfficialParseLine(line: any): boolean {
  if (line?.resolve_mode === "parse") return true;
  if (line?.url_kind === "resolve_ticket") return true;
  if (line?.resolve_required && String(line?.url || "").startsWith("resolve://")) {
    return true;
  }
  return false;
}

/** Enrich MacCMS playSources with bpz5 official ticket lines. Failures → []. */
export async function enrichOfficialPlaySources(
  vod: VodItem,
  existing: PlaySource[]
): Promise<PlaySource[]> {
  if (!bpz5Configured()) return [];
  const title = (vod.vod_name || "").trim();
  if (!title) return [];

  try {
    const q = new URLSearchParams({
      page: "1",
      limit: "8",
      intent: "catalog_search",
      q: title,
    });
    const catalog = await bpz5Fetch("GET", `/v1/browse/catalog?${q}`);
    if (catalog.status !== 200) return [];
    const cards: any[] = catalog.json?.cards || [];
    const qNorm = normalizeTitle(title);
    const qYear = normalizeYear(vod.vod_year);
    let best: any = null;
    let bestScore = -1;
    for (const card of cards) {
      if (card.has_playback === false) continue;
      let score = scoreTitle(qNorm, normalizeTitle(card.title || ""));
      if (qYear && normalizeYear(card.year) === qYear) score += 15;
      if (score > bestScore) {
        bestScore = score;
        best = card;
      }
    }
    if (!best || bestScore < MATCH_THRESHOLD) return [];

    const variantId =
      best.selected_variant_id || best.default_variant_id || best.id;
    if (!variantId) return [];

    let epBudget = 1;
    for (const src of existing) {
      epBudget = Math.max(epBudget, src.episodes?.length || 0);
    }
    epBudget = Math.min(epBudget, MAX_EPISODES);

    const epsRes = await bpz5Fetch(
      "GET",
      `/v1/catalog/${encodeURIComponent(variantId)}/episodes?offset=0&limit=${epBudget}`
    );
    if (epsRes.status !== 200) return [];
    const episodes: any[] = (epsRes.json?.episodes || []).slice(0, epBudget);
    if (!episodes.length) return [];

    await ensureAnonymousSession(false);

    const byProvider = new Map<string, PlaySource>();
    const order: string[] = [];

    await Promise.all(
      episodes.map(async (ep, index) => {
        const token = (ep.token || "").trim();
        if (!token) return;
        const resolved = await bpz5Fetch(
          "GET",
          `/v1/playback/resolve/${encodeURIComponent(token)}`
        );
        if (resolved.status !== 200) return;
        const lines = (resolved.json?.line_options || []).filter(isOfficialParseLine);
        const epName =
          ep.title ||
          existing.find((s) => s.episodes?.[index]?.name)?.episodes?.[index]
            ?.name ||
          `第${index + 1}集`;
        for (const line of lines) {
          const provider = (line.provider_id || line.play_from || "").trim();
          const playFrom = (line.play_from || "").trim();
          if (!provider) continue;
          const key =
            playFrom && playFrom !== provider
              ? `bpz5:${provider}:${playFrom}`
              : `bpz5:${provider}`;
          let ps = byProvider.get(key);
          if (!ps) {
            const empty: Episode[] = Array.from({ length: episodes.length }, () => ({
              name: "",
              url: "",
            }));
            const weightHint =
              typeof line.preference_weight === "number" &&
              line.preference_weight > 0
                ? line.preference_weight
                : 0;
            // 热播聚合共用 provider_id，权重只看 play_from
            const weightProviderId =
              provider === "official-hot-playback" ? undefined : provider;
            ps = annotatePlaySource(
              {
                name: line.provider_name || line.label || provider,
                key,
                episodes: empty,
                mode: "ticket",
                playFrom,
                providerId: provider,
                requiresAuth: true,
                weight: weightHint,
              },
              playFrom
            );
            if (weightHint <= 0) {
              ps = annotatePlaySource(
                { ...ps, providerId: weightProviderId, weight: 0 },
                playFrom
              );
              ps.providerId = provider;
            }
            byProvider.set(key, ps);
            order.push(key);
          }
          let url = String(line.url || "").trim();
          if (url && !url.startsWith("resolve://") && url.startsWith("rpt1.")) {
            url = `resolve://${url}`;
          }
          ps.episodes[index] = { name: epName, url };
        }
      })
    );

    const out = order
      .map((k) => byProvider.get(k)!)
      .filter((ps) => ps.episodes.some((e) => e.url));
    return sortPlaySources(out);
  } catch {
    return [];
  }
}

export interface HomeFeedCard {
  id: string;
  title: string;
  year: string;
  poster: string;
  remarks: string;
  heat: number | null;
  rank: number;
  playable: boolean;
  availabilityLabel: string;
  contentKind: string;
  genres: string[];
}

export interface HomeFeedSection {
  id: string;
  title: string;
  subtitle: string;
  priority: number;
  type: string;
  cards: HomeFeedCard[];
}

export interface HomeFeedResponse {
  enabled: boolean;
  sections: HomeFeedSection[];
}

function yearString(value: unknown): string {
  if (value == null) return "";
  const match = String(value).match(/\d{4}/);
  return match?.[0] ?? "";
}

/** Proxy bpz5 home feed; preserves section priority + card rank order. */
export async function fetchHomeFeed(): Promise<HomeFeedResponse> {
  if (!bpz5Configured()) {
    return { enabled: false, sections: [] };
  }
  try {
    const { status, json } = await bpz5Fetch("GET", "/v1/feed/home");
    if (status !== 200 || !json) {
      return { enabled: false, sections: [] };
    }
    const rawSections: any[] = Array.isArray(json.sections) ? json.sections : [];
    const sections: HomeFeedSection[] = rawSections
      .map((section) => {
        const cards: HomeFeedCard[] = (section.cards || []).map(
          (card: any, index: number) => {
            const availability = card.availability || {};
            return {
              id: String(card.id || card.work_id || `${section.id}-${index}`),
              title: String(card.title || "").trim(),
              year: yearString(card.year),
              poster: String(card.poster_url || card.carousel_url || "").trim(),
              remarks: String(card.remarks || "").trim(),
              heat:
                typeof card.heat_value === "number" ? card.heat_value : null,
              rank:
                typeof card.rank_position === "number"
                  ? card.rank_position
                  : index,
              playable: availability.playable !== false,
              availabilityLabel: String(
                availability.label || (availability.playable === false ? "暂不可播" : "可播放")
              ),
              contentKind: String(card.content_kind || "").trim(),
              genres: Array.isArray(card.genres)
                ? card.genres.map((g: unknown) => String(g)).filter(Boolean)
                : [],
            };
          }
        );
        return {
          id: String(section.id || section.title || "section"),
          title: String(section.title || "").trim() || "推荐",
          subtitle: String(section.subtitle || "").trim(),
          priority: Number(section.priority) || 0,
          type: String(section.type || "").trim(),
          cards,
        };
      })
      .filter((section) => section.cards.length > 0)
      .sort((a, b) => b.priority - a.priority);

    return { enabled: sections.length > 0, sections };
  } catch {
    return { enabled: false, sections: [] };
  }
}
