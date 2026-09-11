"""Build a TVBox source JSON from EHR663 official py spiders, dropping slow parsers."""

from __future__ import annotations

import json
from pathlib import Path
from statistics import median
from typing import Any
from urllib.parse import quote, urlparse

FAST_PARSER_PREFIXES = [
    "https://jx.xmflv.cc/?url=",
    "https://jx.m3u8.tv/jiexi/?url=",
]

OFFICIAL_SITES = [
    {"key": "qq", "name": "腾讯视频", "file": "腾讯视频.py"},
    {"key": "youku", "name": "优酷", "file": "优酷视频.py"},
    {"key": "qiyi", "name": "爱奇艺", "file": "爱奇艺.py"},
    {"key": "mgtv", "name": "芒果TV", "file": "芒果TV.py"},
]

EHR_PY_BASE = "https://raw.githubusercontent.com/FGBLH/EHR663/refs/heads/main/py/"

PARSER_NAMES = {
    "jx.xmflv.cc": "解析cc",
    "jx.m3u8.tv": "解析m3u8",
}

OFFICIAL_FLAGS = [
    "qq",
    "腾讯",
    "腾讯视频",
    "qiyi",
    "爱奇艺",
    "youku",
    "优酷",
    "mgtv",
    "芒果",
    "芒果TV",
]


def parser_prefix(url: str) -> str:
    raw = (url or "").strip()
    if not raw.startswith("http"):
        return ""
    parsed = urlparse(raw)
    if "url=" not in (parsed.query or ""):
        return ""
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path}?url="


def filter_parser_prefixes(rows: list[dict[str, Any]], max_ttfb_ms: float = 2000) -> list[str]:
    """Keep parser prefixes that stayed under max_ttfb_ms and never failed. Faster first."""
    buckets: dict[str, list[float]] = {}
    failed: set[str] = set()
    for row in rows:
        if row.get("role") != "parser":
            continue
        prefix = parser_prefix(str(row.get("url") or ""))
        if not prefix:
            continue
        if not row.get("ok"):
            failed.add(prefix)
            continue
        ttfb = row.get("ttfb_ms")
        if not isinstance(ttfb, (int, float)):
            failed.add(prefix)
            continue
        buckets.setdefault(prefix, []).append(float(ttfb))

    kept: list[tuple[float, str]] = []
    for prefix, samples in buckets.items():
        if prefix in failed:
            continue
        if max(samples) > max_ttfb_ms:
            continue
        kept.append((median(samples), prefix))
    kept.sort(key=lambda item: item[0])
    return [prefix for _, prefix in kept]


def _site_api(filename: str) -> str:
    return EHR_PY_BASE + quote(filename)


def _parse_name(prefix: str) -> str:
    host = urlparse(prefix).netloc.lower()
    return PARSER_NAMES.get(host, host.split(".")[0] or "解析")


def build_tvbox_source(parser_prefixes: list[str] | None = None) -> dict[str, Any]:
    prefixes = list(parser_prefixes or FAST_PARSER_PREFIXES)
    sites = [
        {
            "key": f"py_{item['key']}",
            "name": item["name"],
            "type": 3,
            "api": _site_api(item["file"]),
            "searchable": 1,
            "quickSearch": 1,
            "filterable": 1,
            "changeable": 1,
        }
        for item in OFFICIAL_SITES
    ]
    parses = [
        {
            "name": _parse_name(prefix),
            "type": 0,
            "url": prefix,
            "ext": {"flag": list(OFFICIAL_FLAGS)},
        }
        for prefix in prefixes
        if "xmflv.com" not in prefix
    ]
    return {
        "spider": "",
        "sites": sites,
        "parses": parses,
        "flags": list(OFFICIAL_FLAGS),
        "ijk": [
            {"group": "软解码", "options": [{"category": 4, "name": "opensles", "value": "0"}]}
        ],
        "ads": [],
    }


def write_tvbox_source(path: Path | None = None, parser_prefixes: list[str] | None = None) -> Path:
    out = path or Path(__file__).resolve().parent / "official.json"
    cfg = build_tvbox_source(parser_prefixes)
    out.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return out


if __name__ == "__main__":
    target = write_tvbox_source()
    print(target)
