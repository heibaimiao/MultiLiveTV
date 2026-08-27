import sourcesData from "@/config/sources.json";
import type { Source } from "./types";

const sources: Source[] = sourcesData as Source[];

export function getAllSources(): Source[] {
  return sources;
}

export function getEnabledSources(): Source[] {
  return sources.filter((s) => s.flag === 0 && !s.vip_only);
}

export function getSourceById(id: number): Source | undefined {
  return sources.find((s) => s.id === id);
}

export function getDefaultSource(): Source {
  const enabled = getEnabledSources();
  if (enabled.length === 0) {
    throw new Error("No enabled sources configured");
  }
  return enabled[0];
}
