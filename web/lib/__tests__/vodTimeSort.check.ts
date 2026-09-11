import {
  mergeVodItems,
  normalizeVodYear,
  parseVodTimeSec,
  sortMergedByUpdatedDesc,
  vodUpdatedAtSec,
} from "../vodMerge";
import type { MergeableVodItem } from "../types";

function assert(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

assert(parseVodTimeSec(1710000000) === 1710000000, "unix sec");
assert(parseVodTimeSec(1710000000000) === 1710000000, "unix ms");
assert(parseVodTimeSec("2026-09-03 14:00:00") > 0, "datetime string");
assert(parseVodTimeSec("") === 0, "empty");

const items: MergeableVodItem[] = [
  {
    vod_id: "1",
    vod_name: "旧片",
    vod_pic: "a",
    vod_time: "2020-01-01 00:00:00",
    sourceId: 125,
    sourceName: "猫眼",
  },
  {
    vod_id: "2",
    vod_name: "新片",
    vod_pic: "b",
    vod_time: "2026-09-03 12:00:00",
    sourceId: 125,
    sourceName: "猫眼",
  },
  {
    vod_id: "3",
    vod_name: "新片",
    vod_pic: "c",
    vod_time: "2026-09-01 12:00:00",
    sourceId: 160,
    sourceName: "量子",
  },
];

const merged = sortMergedByUpdatedDesc(mergeVodItems(items));
assert(merged[0].vod_name === "新片", `expected 新片 first, got ${merged[0].vod_name}`);
assert(
  vodUpdatedAtSec(merged[0]) >= vodUpdatedAtSec(merged[1]),
  "merged list not time-desc when years empty"
);
assert(
  vodUpdatedAtSec(merged[0]) === parseVodTimeSec("2026-09-03 12:00:00"),
  "group should keep latest vod_time across variants"
);

const yearSorted = sortMergedByUpdatedDesc([
  {
    vod_id: "1",
    vod_name: "旧年",
    vod_pic: "",
    vod_year: "2020",
    vod_time: 900,
    variants: [],
    primarySourceId: 1,
  },
  {
    vod_id: "2",
    vod_name: "新年",
    vod_pic: "",
    vod_year: "2026",
    vod_time: 100,
    variants: [],
    primarySourceId: 1,
  },
  {
    vod_id: "3",
    vod_name: "无年份",
    vod_pic: "",
    vod_time: 999,
    variants: [],
    primarySourceId: 1,
  },
]);
assert(
  yearSorted.map((item) => item.vod_id).join(",") === "2,1,3",
  "release year must rank above vod_time"
);

assert(normalizeVodYear("2030", 2026) === "", "future placeholder year must not display");
assert(normalizeVodYear("2027", 2026) === "2027", "next year remains allowed");
assert(normalizeVodYear("2028", 2026) === "", "year+2 must not display");

const futureSorted = sortMergedByUpdatedDesc([
  {
    vod_id: "1",
    vod_name: "脏年份",
    vod_pic: "",
    vod_year: "2030",
    vod_time: 1700000000,
    variants: [],
    primarySourceId: 1,
  },
  {
    vod_id: "2",
    vod_name: "老片",
    vod_pic: "",
    vod_year: "2020",
    vod_time: 1600000000,
    variants: [],
    primarySourceId: 1,
  },
]);
assert(
  futureSorted.map((item) => item.vod_id).join(",") === "1,2",
  "recent 2030-placeholder titles must stay ahead of older real years"
);

const folded = mergeVodItems([
  {
    vod_id: "1",
    vod_name: "热血部落",
    vod_pic: "",
    vod_year: "",
    vod_time: 100,
    sourceId: 1,
    sourceName: "A",
  },
  {
    vod_id: "2",
    vod_name: "热血部落",
    vod_pic: "",
    vod_year: "2024",
    vod_time: 200,
    sourceId: 2,
    sourceName: "B",
  },
]);
assert(folded.length === 1, "empty year should fold into concrete year");
assert(folded[0].variants.length === 2, "both sources remain as variants");

console.log("vodTimeSort.check.ts: ok");
