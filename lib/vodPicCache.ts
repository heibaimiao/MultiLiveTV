const CACHE_KEY = "vod-pic-cache";
const MAX_ENTRIES = 500;

interface CacheEntry {
  url: string;
  ts: number;
}

type CacheStore = Record<string, CacheEntry>;

function cacheKey(sourceId: number, vodId: string): string {
  return `${sourceId}:${vodId}`;
}

function readStore(): CacheStore {
  if (typeof window === "undefined") return {};
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    return raw ? (JSON.parse(raw) as CacheStore) : {};
  } catch {
    return {};
  }
}

function writeStore(store: CacheStore): void {
  const entries = Object.entries(store).sort((a, b) => b[1].ts - a[1].ts);
  const trimmed = Object.fromEntries(entries.slice(0, MAX_ENTRIES));
  localStorage.setItem(CACHE_KEY, JSON.stringify(trimmed));
}

export function getCachedPic(sourceId: number, vodId: string): string | null {
  const entry = readStore()[cacheKey(sourceId, vodId)];
  return entry?.url ?? null;
}

export function setCachedPic(
  sourceId: number,
  vodId: string,
  url: string
): void {
  if (!url || url.startsWith("/")) return;
  const store = readStore();
  store[cacheKey(sourceId, vodId)] = { url, ts: Date.now() };
  writeStore(store);
}

const inflight = new Map<string, Promise<string | null>>();

export function fetchAndCachePic(
  sourceId: number,
  vodId: string
): Promise<string | null> {
  const key = cacheKey(sourceId, vodId);
  const cached = getCachedPic(sourceId, vodId);
  if (cached) return Promise.resolve(cached);

  const pending = inflight.get(key);
  if (pending) return pending;

  const promise = fetch(`/api/vod/pic?sourceId=${sourceId}&ids=${encodeURIComponent(vodId)}`)
    .then(async (res) => {
      const data = (await res.json()) as { url?: string | null };
      const url = data.url ?? null;
      if (url) setCachedPic(sourceId, vodId, url);
      return url;
    })
    .catch(() => null)
    .finally(() => {
      inflight.delete(key);
    });

  inflight.set(key, promise);
  return promise;
}
