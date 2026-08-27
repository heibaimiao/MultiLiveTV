import type {
  Source,
  VodType,
  MacCmsListResponse,
  MacCmsDetailResponse,
} from "./types";

const DEFAULT_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
};

function normalizeBaseUrl(url: string): string {
  return url.endsWith("/") ? url : `${url}/`;
}

async function fetchJson<T>(url: string, params: Record<string, string | number>): Promise<T> {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    search.set(key, String(value));
  }

  const response = await fetch(`${url}?${search.toString()}`, {
    headers: DEFAULT_HEADERS,
    signal: AbortSignal.timeout(15000),
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`MacCMS request failed: ${response.status}`);
  }

  return response.json() as Promise<T>;
}

export async function fetchVodTypes(source: Source): Promise<VodType[]> {
  const data = await fetchJson<MacCmsListResponse>(normalizeBaseUrl(source.url), {
    ac: "list",
    pg: 1,
  });
  return data.class ?? [];
}

export async function fetchVodList(
  source: Source,
  page = 1,
  typeId?: number
): Promise<MacCmsListResponse> {
  const params: Record<string, string | number> = {
    ac: "list",
    pg: page,
  };
  if (typeId !== undefined) {
    params.t = typeId;
  }

  return fetchJson<MacCmsListResponse>(normalizeBaseUrl(source.url), params);
}

export async function fetchVodDetail(
  source: Source,
  ids: string
): Promise<MacCmsDetailResponse> {
  return fetchJson<MacCmsDetailResponse>(normalizeBaseUrl(source.url), {
    ac: "detail",
    ids,
  });
}

export async function searchVod(
  source: Source,
  keyword: string,
  page = 1
): Promise<MacCmsListResponse> {
  return fetchJson<MacCmsListResponse>(normalizeBaseUrl(source.url), {
    ac: "list",
    wd: keyword,
    pg: page,
  });
}
