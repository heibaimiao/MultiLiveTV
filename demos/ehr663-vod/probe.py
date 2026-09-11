"""Play-line latency helpers. Official platforms are probed and ranked first."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlparse

from playurl import first_media_uri, is_av_payload

OFFICIAL_KEYS = ("qq", "youku", "qiyi", "mgtv")
OFFICIAL_INDEX = {key: i for i, key in enumerate(OFFICIAL_KEYS)}

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


def source_order(keys: list[str], official_only: bool = False) -> list[str]:
    seen: set[str] = set()
    official: list[str] = []
    rest: list[str] = []
    for key in keys:
        if key in seen:
            continue
        seen.add(key)
        if key in OFFICIAL_INDEX:
            official.append(key)
        elif not official_only:
            rest.append(key)
    official.sort(key=lambda k: OFFICIAL_INDEX[k])
    return official + rest


def _dedupe(targets: list[dict[str, str]]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in targets:
        url = (item.get("url") or "").strip()
        if not url or url in seen:
            continue
        seen.add(url)
        out.append({"role": item["role"], "url": url})
    return out


def build_probe_targets(classified: dict[str, Any]) -> list[dict[str, str]]:
    """direct → official page → parser wrappers. Skip empty / duplicates."""
    targets: list[dict[str, str]] = []
    url = str(classified.get("url") or "").strip()
    official = str(classified.get("official") or "").strip()
    parse_urls = classified.get("parse_urls") or []

    if classified.get("mode") == "video" and url.startswith("http"):
        targets.append({"role": "direct", "url": url})
    if official.startswith("http"):
        targets.append({"role": "official", "url": official})
    for wrapped in parse_urls:
        wrapped = str(wrapped or "").strip()
        if wrapped.startswith("http"):
            targets.append({"role": "parser", "url": wrapped})
    if classified.get("mode") != "video" and url.startswith("http"):
        role = "official" if url == official else "parser"
        targets.append({"role": role, "url": url})
    return _dedupe(targets)


def rank_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(row: dict[str, Any]) -> tuple:
        src = str(row.get("source") or "")
        official = 0 if src in OFFICIAL_INDEX else 1
        src_rank = OFFICIAL_INDEX.get(src, 100)
        fail = 0 if row.get("ok") else 1
        ttfb = row.get("ttfb_ms")
        ttfb_key = ttfb if isinstance(ttfb, (int, float)) else 1e12
        return (official, fail, ttfb_key, src_rank)

    return sorted(rows, key=key)


def _kind_from_head(head: bytes, content_type: str, url: str) -> str:
    raw = head.lstrip()
    ctype = (content_type or "").lower()
    path = urlparse(url).path.lower()
    if raw.startswith(b"#EXTM3U") or "mpegurl" in ctype:
        return "m3u8"
    if is_av_payload(head) or "mp4" in ctype or path.endswith(".mp4"):
        return "mp4"
    if raw.startswith((b"<", b"<!DOCTYPE", b"<!doctype")) or "html" in ctype:
        return "html"
    if raw.startswith((b"{", b"[")):
        return "json"
    return "other"


def probe_url(url: str, timeout: float = 8.0) -> dict[str, Any]:
    import time

    import requests

    t0 = time.perf_counter()
    row: dict[str, Any] = {
        "url": url,
        "ok": False,
        "kind": "unknown",
        "http": None,
        "ttfb_ms": None,
        "media_ms": None,
        "error": "",
    }
    try:
        rsp = requests.get(
            url,
            headers={"User-Agent": UA, "Accept": "*/*"},
            timeout=timeout,
            verify=False,
            stream=True,
        )
        chunk = next(rsp.iter_content(64 * 1024), b"") or b""
        row["ttfb_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        row["http"] = rsp.status_code
        ctype = rsp.headers.get("content-type") or ""
        row["kind"] = _kind_from_head(chunk, ctype, url)
        if rsp.status_code >= 400:
            row["error"] = f"HTTP {rsp.status_code}"
            return row

        if row["kind"] == "m3u8":
            text = chunk.decode("utf-8", errors="ignore")
            first = first_media_uri(text, url)
            if first:
                t1 = time.perf_counter()
                seg = requests.get(
                    first,
                    headers={"User-Agent": UA, "Accept": "*/*"},
                    timeout=timeout,
                    verify=False,
                    stream=True,
                )
                head = next(seg.iter_content(64), b"") or b""
                row["media_ms"] = round((time.perf_counter() - t1) * 1000, 1)
                if head.lstrip().startswith(b"#EXT"):
                    nested = first_media_uri(head.decode("utf-8", errors="ignore"), first)
                    if nested:
                        t2 = time.perf_counter()
                        inner = requests.get(
                            nested,
                            headers={"User-Agent": UA},
                            timeout=timeout,
                            verify=False,
                            stream=True,
                        )
                        head = next(inner.iter_content(64), b"") or b""
                        row["media_ms"] = round((time.perf_counter() - t2) * 1000, 1)
                row["ok"] = is_av_payload(head) or bool(head)
            else:
                row["ok"] = True
            return row

        if row["kind"] == "mp4":
            row["ok"] = is_av_payload(chunk) or rsp.status_code == 200
            return row

        row["ok"] = rsp.status_code == 200 and bool(chunk)
        return row
    except Exception as exc:  # noqa: BLE001
        row["ttfb_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        row["error"] = str(exc)
        return row
