/**
 * MacCMS vod_play_from 播放线路显示名映射
 *
 * 来源：
 * - 本项目 7 个资源站接口实测（2026-08）
 * - GitHub: allhaily/zyplayer tab_rename
 * - GitHub: maccmsapp/MacApp playerName
 * - 苹果 CMS 资源站常见播放器编码文档
 */

const PLAY_SOURCE_NAMES: Record<string, string> = {
  // --- 当前 config/sources.json 实测有数据 ---
  wjm3u8: "无尽",
  snm3u8: "索尼",
  ikm3u8: "爱酷",
  ffm3u8: "非凡",
  feifan: "非凡",
  gsm3u8: "光速",
  gsyun: "光速",
  mtm3u8: "茅台",
  mtyun: "茅台",
  mym3u8: "猫眼",
  hym3u8: "虎牙",
  hyyun: "虎牙",
  modum3u8: "魔都",
  liangzi: "量子",
  jsyun: "极速",
  subyun: "速播",

  // --- GitHub / 社区常见 MacCMS 播放器编码 ---
  lzm3u8: "量子",
  jpm3u8: "极品",
  jsm3u8: "极速",
  subm3u8: "速播",
  bfzym3u8: "暴风",
  hnm3u8: "红牛",
  hnyun: "红牛",
  bjm3u8: "八戒",
  wolong: "卧龙",
  maotai: "茅台",
  maoyan: "猫眼",
  kcm3u8: "快车",
  xlm3u8: "新浪",
  dbm3u8: "豆瓣",
  hkm3u8: "华为",
  yym3u8: "丫丫",
  ckm3u8: "CK",
  dym3u8: "电影",
  ukm3u8: "U酷",
  lsm3u8: "乐视",
  qhm3u8: "奇虎",
  ysm3u8: "影视",
  huyam3u8: "虎牙",
  tpm3u8: "淘片",
  tkm3u8: "天空",
  "1080zyk": "1080看",
  zuidam3u8: "最大",
  kuaikan: "快看",
  wsym3u8: "无印",
  xiguam3u8: "西瓜",
  xigua: "西瓜",
  hhm3u8: "豪华",
  hhyun: "豪华",
  rym3u8: "如意",
  ruyi: "如意",
  ukyun: "U酷",
  iqym3u8: "奇艺",
  jinyingm3u8: "金鹰",
  jinyingyun: "金鹰",
  dyttm3u8: "天堂",
  dytt: "天堂",
  nnm3u8: "牛牛",
  "360zy": "360",
  xlyun: "新浪",
  dbyun: "豆瓣",

  // bpz5 官方票
  huo: "1080P-官方V",
  lv2: "1080P-官方Z",
  rrys: "1080P-官方R",
  bytedance: "高清-官方B",
  cloudflare: "高清-官方C",
  "cloudflare-4k": "4K-官方C",
  dong: "1080P-官方D",
  qq: "腾讯视频",
  qiyi: "爱奇艺",
  youku: "优酷",
  mgtv: "芒果TV",
  bilibili: "哔哩哔哩",
};

const PLAY_SOURCE_PREFIX_NAMES: Record<string, string> = {
  wj: "无尽",
  sn: "索尼",
  ik: "爱酷",
  lz: "量子",
  ff: "非凡",
  gs: "光速",
  mt: "茅台",
  my: "猫眼",
  hy: "虎牙",
  modu: "魔都",
  jp: "极品",
  js: "极速",
  sub: "速播",
  bfzy: "暴风",
  hn: "红牛",
  bj: "八戒",
  kc: "快车",
  xl: "新浪",
  db: "豆瓣",
  hk: "华为",
  yy: "丫丫",
  ck: "CK",
  dy: "电影",
  uk: "U酷",
  ls: "乐视",
  qh: "奇虎",
  ys: "影视",
  tp: "淘片",
  tk: "天空",
  wolong: "卧龙",
  feifan: "非凡",
  maotai: "茅台",
  maoyan: "猫眼",
  gsyun: "光速",
  mtyun: "茅台",
  hyyun: "虎牙",
  liangzi: "量子",
  jsyun: "极速",
  subyun: "速播",
  wsy: "无印",
  xigua: "西瓜",
  hh: "豪华",
  ry: "如意",
  iqy: "奇艺",
  jinying: "金鹰",
  nn: "牛牛",
  "360zy": "360",
  dytt: "天堂",
};

/** 当前项目资源站实测会出现的线路（用于文档/调试） */
export const VERIFIED_PLAY_SOURCES = [
  "wjm3u8",
  "snm3u8",
  "ikm3u8",
  "ffm3u8",
  "feifan",
  "gsm3u8",
  "gsyun",
  "mtm3u8",
  "mtyun",
  "mym3u8",
  "hym3u8",
  "hyyun",
  "modum3u8",
  "liangzi",
  "jsyun",
  "subyun",
  "lzm3u8",
  "bfzym3u8",
  "jsm3u8",
  "subm3u8",
  "hnm3u8",
  "hnyun",
  "wsym3u8",
  "xlm3u8",
  "xiguam3u8",
  "dbm3u8",
  "1080zyk",
  "hhm3u8",
  "rym3u8",
  "ukm3u8",
  "iqym3u8",
  "jinyingm3u8",
  "zuidam3u8",
  "dyttm3u8",
  "nnm3u8",
  "360zy",
] as const;

export function formatPlaySourceName(raw: string, index: number): string {
  const key = raw.trim().toLowerCase();
  if (!key) return `线路${index + 1}`;

  if (PLAY_SOURCE_NAMES[key]) {
    return PLAY_SOURCE_NAMES[key];
  }

  const prefix = key.replace(/m3u8$/i, "").replace(/yun$/i, "");
  if (PLAY_SOURCE_PREFIX_NAMES[prefix]) {
    return PLAY_SOURCE_PREFIX_NAMES[prefix];
  }

  if (/^线路\d+$/i.test(raw.trim())) {
    return raw.trim();
  }

  return `线路${index + 1}`;
}
