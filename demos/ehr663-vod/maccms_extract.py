"""Extract MacCMS / mac10 style API URLs from EHR663 Python spiders."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import urlparse, urlunparse

PROVIDE_RE = re.compile(
    r"https?://[^\s'\"\\<>]+?(?:api\.php/provide|/provide/vod)[^\s'\"\\<>]*",
    re.I,
)
MAC_RE = re.compile(
    r"https?://[^\s'\"\\<>]+?(?:inc/api_mac\d*\.php|inc/api\.php)[^\s'\"\\<>]*",
    re.I,
)
API_FIELD_RE = re.compile(
    r"""['"]api['"]\s*:\s*['"](https?://[^'"]+)['"]""",
)
CONST_RE = re.compile(
    r"""(?:main_api|HOT_API|SHORT_API|LZ_API)\s*=\s*['"](https?://[^'"]+)['"]""",
)
TUPLE_RE = re.compile(
    r"""\(\s*['"]([^'"]+)['"]\s*,\s*['"](https?://[^'"]+)['"]\s*\)""",
)
NAMED_DICT_RE = re.compile(
    r"""['"]name['"]\s*:\s*['"]([^'"]+)['"]\s*,\s*['"]api['"]\s*:\s*['"](https?://[^'"]+)['"]""",
)

EMOJI_RE = re.compile(
    "[\U0001F300-\U0001F9FF\U00002600-\U000027BF\U0001F600-\U0001F64F\ufe0f\u200d]+",
)


def strip_emoji(name: str) -> str:
    return EMOJI_RE.sub("", name or "").strip() or (name or "").strip()


def normalize_api_url(url: str) -> str:
    raw = (url or "").strip().rstrip("\\")
    if not raw.startswith("http"):
        return ""
    # Drop trailing punctuation accidentally captured
    while raw and raw[-1] in ",);]}'\"":
        raw = raw[:-1]
    parsed = urlparse(raw)
    path = parsed.path or ""
    if "/provide/vod" in path.lower() and not path.endswith(".php") and not path.endswith("/"):
        # keep query/suffix like /from/xxx/at/json
        if path.rstrip("/").endswith("vod"):
            path = path.rstrip("/") + "/"
            raw = urlunparse(parsed._replace(path=path))
    return raw


def api_kind(url: str) -> str:
    u = (url or "").lower()
    if "api_mac" in u or "/inc/api" in u:
        return "mac"
    return "provide"


def _default_name(url: str) -> str:
    host = (urlparse(url).hostname or "maccms").lower()
    parts = host.split(".")
    if len(parts) >= 2:
        return parts[-2]
    return host


def extract_apis_from_text(text: str, source_file: str = "") -> list[dict[str, str]]:
    found: dict[str, dict[str, str]] = {}

    def add(url: str, name: str = "", kind: str | None = None) -> None:
        api = normalize_api_url(url)
        if not api:
            return
        # Only keep collection-style endpoints (scheme 3)
        low = api.lower()
        if not any(
            x in low
            for x in ("provide/vod", "api_mac", "/inc/api.php", "/inc/api_mac")
        ):
            # Still allow generic http api field if it looks like mac/cms
            if "provide" not in low and "api" not in low:
                return
            if not any(x in low for x in ("provide", "api_mac", "/inc/api", "zyapi", "caiji")):
                # keep if matched provide/mac regex already via caller
                if kind is None and "provide" not in low and "mac" not in low:
                    return
        k = kind or api_kind(api)
        if not any(x in low for x in ("provide/vod", "api_mac", "/inc/api")):
            return
        display = strip_emoji(name) or found.get(api, {}).get("name") or _default_name(api)
        prev = found.get(api)
        if prev and prev.get("name") and not name:
            display = prev["name"]
        found[api] = {
            "api": api,
            "name": display,
            "kind": k,
            "source_file": source_file,
        }

    for m in NAMED_DICT_RE.finditer(text or ""):
        add(m.group(2), m.group(1))
    for m in TUPLE_RE.finditer(text or ""):
        add(m.group(2), m.group(1))
    for m in API_FIELD_RE.finditer(text or ""):
        add(m.group(1))
    for m in CONST_RE.finditer(text or ""):
        add(m.group(1))
    for m in PROVIDE_RE.finditer(text or ""):
        add(m.group(0), kind="provide")
    for m in MAC_RE.finditer(text or ""):
        add(m.group(0), kind="mac")

    return list(found.values())


def extract_apis_from_dir(py_dir: Path) -> list[dict[str, str]]:
    merged: dict[str, dict[str, str]] = {}
    for path in sorted(py_dir.glob("*.py")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for row in extract_apis_from_text(text, source_file=path.name):
            api = row["api"]
            prev = merged.get(api)
            if prev is None:
                merged[api] = row
                continue
            files = {prev.get("source_file", ""), row.get("source_file", "")}
            prev["source_file"] = ",".join(sorted(f for f in files if f))
            # Prefer human names over domain stubs
            stub = _default_name(api)
            prev_name = prev.get("name") or ""
            new_name = row.get("name") or ""
            if new_name and new_name != stub and (not prev_name or prev_name == stub):
                prev["name"] = new_name
            elif new_name and prev_name == stub:
                prev["name"] = new_name
    return sorted(merged.values(), key=lambda r: r["api"])


def probe_is_success(http: int | None, body: str, kind: str) -> bool:
    if http is None or http >= 400:
        return False
    text = (body or "").lstrip()
    if not text:
        return False
    if kind == "mac":
        low = text[:200].lower()
        if low.startswith("<html") or "<!doctype html" in low:
            return False
        if text.startswith("<?xml") or "<rss" in low or "<list" in low:
            return True
        if text.startswith("{") or text.startswith("["):
            try:
                data = json.loads(text)
            except json.JSONDecodeError:
                return False
            return isinstance(data, dict) and ("list" in data or "data" in data or "code" in data)
        return False

    # provide / json
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        # some endpoints return XML mac format even under provide path
        low = text[:200].lower()
        return text.startswith("<?xml") or "<rss" in low or "<list" in low
    if not isinstance(data, dict):
        return False
    if data.get("code") in (0, "0") and not data.get("list"):
        return False
    return "list" in data or bool(data.get("list")) or data.get("code") in (1, "1")


def list_probe_url(api: str) -> str:
    base = normalize_api_url(api)
    if not base:
        return ""
    if "api_mac" in base.lower() or base.lower().endswith("/inc/api.php"):
        sep = "&" if "?" in base else "?"
        return f"{base}{sep}ac=list"
    # provide/vod
    if "?" in base:
        return f"{base}&ac=list&pg=1"
    return f"{base}?ac=list&pg=1"
