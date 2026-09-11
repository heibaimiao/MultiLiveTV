"""Build TVBox type=1 source JSON from probed MacCMS APIs."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from source import FAST_PARSER_PREFIXES, OFFICIAL_FLAGS, PARSER_NAMES

RANK_PREFIX_RE = re.compile(r"^\d{1,3}[.\s|．、_-]+")


def key_for_api(api: str) -> str:
    host = (urlparse(api).hostname or "api").lower()
    parts = [p for p in host.split(".") if p not in ("www", "api", "caiji", "cdn", "collect", "m3u8")]
    base = parts[-2] if len(parts) >= 2 else (parts[0] if parts else "api")
    base = re.sub(r"[^a-z0-9]+", "", base) or "api"
    return f"maccms_{base}"


def sort_rows_by_latency(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Fastest TTFB first; missing ttfb sinks to the end."""
    return sorted(
        rows,
        key=lambda r: (
            float(r["ttfb_ms"]) if isinstance(r.get("ttfb_ms"), (int, float)) else 1e12,
            str(r.get("name") or ""),
            str(r.get("api") or ""),
        ),
    )


def filter_api_rows(rows: list[dict[str, Any]], max_ttfb_ms: float = 2000) -> list[dict[str, Any]]:
    kept = [
        r
        for r in rows
        if r.get("ok")
        and isinstance(r.get("ttfb_ms"), (int, float))
        and float(r["ttfb_ms"]) <= max_ttfb_ms
    ]
    return sort_rows_by_latency(kept)


def bare_name(name: str) -> str:
    return RANK_PREFIX_RE.sub("", (name or "").strip()).strip() or (name or "").strip()


def ranked_name(name: str, index: int, width: int) -> str:
    return f"{index:0{width}d}.{bare_name(name)}"


def _parse_name(prefix: str) -> str:
    host = urlparse(prefix).netloc.lower()
    return PARSER_NAMES.get(host, host.split(".")[0] or "解析")


def build_maccms_tvbox(rows: list[dict[str, Any]]) -> dict[str, Any]:
    ordered = sort_rows_by_latency(list(rows))
    width = max(2, len(str(len(ordered))))
    used_keys: set[str] = set()
    sites: list[dict[str, Any]] = []
    for i, row in enumerate(ordered, 1):
        api = str(row.get("api") or "").strip()
        if not api:
            continue
        key = key_for_api(api)
        if key in used_keys:
            n = 2
            while f"{key}{n}" in used_keys:
                n += 1
            key = f"{key}{n}"
        used_keys.add(key)
        site: dict[str, Any] = {
            "key": key,
            "name": ranked_name(str(row.get("name") or key), i, width),
            "type": 1,
            "api": api,
            "searchable": 1,
            "quickSearch": 1,
            "filterable": 1,
            "changeable": 1,
            "index": i,
        }
        if isinstance(row.get("ttfb_ms"), (int, float)):
            site["ttfb_ms"] = float(row["ttfb_ms"])
        sites.append(site)

    # 解析线路：保持测速后的快解析顺序（已去掉 xmflv.com）
    parses = [
        {
            "name": f"{i:02d}.{_parse_name(prefix)}",
            "type": 0,
            "url": prefix,
            "ext": {"flag": list(OFFICIAL_FLAGS)},
        }
        for i, prefix in enumerate(
            [p for p in FAST_PARSER_PREFIXES if "xmflv.com" not in p],
            1,
        )
    ]
    return {
        "spider": "",
        "sites": sites,
        "parses": parses,
        "flags": list(OFFICIAL_FLAGS),
        "ads": [],
    }


def write_maccms_tvbox(rows: list[dict[str, Any]], path: Path | None = None) -> Path:
    out = path or Path(__file__).resolve().parent / "maccms.json"
    cfg = build_maccms_tvbox(rows)
    out.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return out
