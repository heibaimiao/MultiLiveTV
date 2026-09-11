import { annotatePlaySource, preferredPlayableIndex, sortPlaySources, weightFor } from "../playLineWeights";
import type { PlaySource } from "../types";

function assert(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

const sources: PlaySource[] = [
  annotatePlaySource({
    name: "红牛",
    key: "hn",
    episodes: [{ name: "1", url: "https://a.com/a.m3u8" }],
    sourceId: 164,
    playFrom: "hnm3u8",
    mode: "direct",
  }),
  annotatePlaySource({
    name: "官方V",
    key: "huo",
    episodes: [{ name: "1", url: "resolve://x" }],
    mode: "ticket",
    playFrom: "huo",
    weight: 1000,
  }),
  annotatePlaySource({
    name: "猫眼",
    key: "my",
    episodes: [{ name: "1", url: "https://b.com/b.m3u8" }],
    sourceId: 125,
    playFrom: "unknown",
    mode: "direct",
  }),
];

const sorted = sortPlaySources(sources);
assert(sorted[0].key === "huo", `expected huo first got ${sorted[0].key}`);
assert(weightFor("hnm3u8") === 920, "hnm3u8 weight");
assert(weightFor(undefined, undefined, 33) === 480, "source 33 weight");
assert(
  preferredPlayableIndex(sources, { ticketEnabled: false }) ===
    sources.findIndex((s) => s.key === "hn"),
  "without ticket prefer hnm3u8 over 猫眼 source weight"
);
assert(
  preferredPlayableIndex(sources, { ticketEnabled: true }) ===
    sources.findIndex((s) => s.key === "huo"),
  "with ticket prefer official"
);

console.log("playLineWeights ok");
