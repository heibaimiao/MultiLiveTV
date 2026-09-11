import weightsJson from "@/config/play-line-weights.json";
import type { PlaySource } from "./types";

export interface PlayLineWeights {
  version: number;
  defaultWeight: number;
  byPlayFrom: Record<string, number>;
  byProviderId: Record<string, number>;
  bySourceId?: Record<string, number>;
}

const table = weightsJson as PlayLineWeights;

/** providerId > playFrom > sourceId > default */
export function weightFor(
  playFrom?: string,
  providerId?: string,
  sourceId?: number
): number {
  const pid = providerId?.trim().toLowerCase();
  const pf = playFrom?.trim().toLowerCase();
  if (pid && table.byProviderId[pid] != null) {
    return table.byProviderId[pid];
  }
  if (pf && table.byPlayFrom[pf] != null) {
    return table.byPlayFrom[pf];
  }
  if (sourceId && table.bySourceId?.[String(sourceId)] != null) {
    return table.bySourceId[String(sourceId)];
  }
  return table.defaultWeight ?? 100;
}

export function sourceWeight(sourceId: number): number {
  return weightFor(undefined, undefined, sourceId);
}

function playabilityScore(source: PlaySource): number {
  return source.episodes.filter((episode) =>
    /\.m3u8|\.mp4|\.mkv|\.flv|\.mov/i.test(episode.url)
  ).length;
}

export function annotatePlaySource(
  source: PlaySource,
  rawPlayFrom?: string
): PlaySource {
  const playFrom = (rawPlayFrom ?? source.playFrom ?? source.key).trim();
  const tableW = weightFor(playFrom, source.providerId, source.sourceId);
  return {
    ...source,
    playFrom,
    mode: source.mode ?? "direct",
    // Keep upstream preference_weight when already set
    weight: source.weight && source.weight > 0 ? source.weight : tableW,
  };
}

export function sortPlaySources(sources: PlaySource[]): PlaySource[] {
  return [...sources].sort((a, b) => {
    const wa = a.weight ?? weightFor(a.playFrom, a.providerId, a.sourceId);
    const wb = b.weight ?? weightFor(b.playFrom, b.providerId, b.sourceId);
    if (wa !== wb) return wb - wa;
    const sa = playabilityScore(a);
    const sb = playabilityScore(b);
    if (sa !== sb) return sb - sa;
    return b.episodes.length - a.episodes.length;
  });
}

function episodePlayable(
  source: PlaySource,
  episodeIndex: number,
  ticketEnabled: boolean
): boolean {
  const ep = source.episodes[episodeIndex] ?? source.episodes[0];
  const url = (ep?.url || source.ticket || "").trim();
  if (!url) return false;
  if (source.mode === "ticket") return ticketEnabled;
  return true;
}

/** First playable line in weight order (array should already be sorted). */
export function preferredPlayableIndex(
  sources: PlaySource[],
  opts?: { episodeIndex?: number; ticketEnabled?: boolean }
): number {
  if (!sources.length) return 0;
  const episodeIndex = opts?.episodeIndex ?? 0;
  const ticketEnabled = opts?.ticketEnabled ?? false;
  const sorted = sortPlaySources(sources);
  for (const candidate of sorted) {
    if (!episodePlayable(candidate, episodeIndex, ticketEnabled)) continue;
    const index = sources.findIndex((item) => item.key === candidate.key);
    if (index >= 0) return index;
  }
  return 0;
}

/** Next playable indices after `fromIndex` (exclusive), up to `limit` total tries including current. */
export function nextPlayableIndexes(
  sources: PlaySource[],
  fromIndex: number,
  opts?: { episodeIndex?: number; ticketEnabled?: boolean; maxTries?: number }
): number[] {
  const maxTries = opts?.maxTries ?? 3;
  const episodeIndex = opts?.episodeIndex ?? 0;
  const ticketEnabled = opts?.ticketEnabled ?? false;
  const ordered = sortPlaySources(sources);
  const result: number[] = [];
  let seenCurrent = false;
  for (const candidate of ordered) {
    const index = sources.findIndex((item) => item.key === candidate.key);
    if (index < 0) continue;
    if (!seenCurrent) {
      if (index === fromIndex) seenCurrent = true;
      continue;
    }
    if (!episodePlayable(candidate, episodeIndex, ticketEnabled)) continue;
    result.push(index);
    if (result.length >= maxTries - 1) break;
  }
  return result;
}
