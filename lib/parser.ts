import type { Source, PlaySource, Episode, ParseResult } from "./types";
import { formatPlaySourceName } from "./playSourceNames";

const DEFAULT_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
};

export function parsePlayUrl(vodPlayFrom: string, vodPlayUrl: string): PlaySource[] {
  if (!vodPlayFrom || !vodPlayUrl) return [];

  const fromList = vodPlayFrom.split("$$$");
  const urlList = vodPlayUrl.split("$$$");

  return fromList.map((name, index) => {
    const rawEpisodes = urlList[index] ?? "";
    const episodes: Episode[] = rawEpisodes
      .split("#")
      .filter(Boolean)
      .map((item) => {
        const dollarIndex = item.indexOf("$");
        if (dollarIndex === -1) {
          return { name: `第${item}`, url: item };
        }
        return {
          name: item.slice(0, dollarIndex) || "播放",
          url: item.slice(dollarIndex + 1),
        };
      });

    return {
      name: formatPlaySourceName(name, index),
      key: name.trim() || `line-${index + 1}`,
      episodes,
    };
  });
}

export async function parsePlayAddress(
  source: Source,
  playUrl: string
): Promise<ParseResult> {
  if (!source.jx_url) {
    return { url: playUrl, parsed: false };
  }

  const parseEndpoint = `${source.jx_url}${encodeURIComponent(playUrl)}`;

  try {
    const response = await fetch(parseEndpoint, {
      headers: DEFAULT_HEADERS,
      signal: AbortSignal.timeout(15000),
      cache: "no-store",
    });

    if (!response.ok) {
      return { url: playUrl, parsed: false };
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const data = await response.json();
      if (typeof data === "string" && data.startsWith("http")) {
        return { url: data.trim(), parsed: true };
      }
      if (data?.url && typeof data.url === "string") {
        return { url: data.url, parsed: true };
      }
      if (data?.data?.url && typeof data.data.url === "string") {
        return { url: data.data.url, parsed: true };
      }
    } else {
      const text = (await response.text()).trim();
      if (text.startsWith("http")) {
        return { url: text, parsed: true };
      }
    }
  } catch {
    // fall through to raw url
  }

  return { url: playUrl, parsed: false };
}
