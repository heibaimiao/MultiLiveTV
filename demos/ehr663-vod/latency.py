#!/usr/bin/env python3
"""Pull EHR663 spider play URLs and probe line latency. Official platforms first.

Examples:
  python3 latency.py
  python3 latency.py -q 庆余年
  python3 latency.py --all
  python3 latency.py --source qq,mgtv --json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

from app import (  # noqa: E402
    SOURCES,
    _list_from,
    _parse_urls_for,
    _safe_call,
    load_spiders,
    parse_episodes,
    spiders,
)
from catalog import classes_from_home  # noqa: E402
from playurl import classify_play, is_direct_media  # noqa: E402
from probe import build_probe_targets, probe_url, rank_rows, source_order  # noqa: E402

FALLBACK_KEYWORDS = ("庆余年", "流浪地球", "繁花")


def _home_items(source: str) -> tuple[list[dict], str]:
    errors: list[str] = []
    try:
        if source == "qiyi":
            data = _safe_call(source, "categoryContent", "2", "1", False, {"class": "2"})
        else:
            data = _safe_call(source, "homeVideoContent") or {}
        items = _list_from(source, data)
        if items:
            return items, ""
    except Exception as exc:  # noqa: BLE001
        errors.append(str(exc))

    try:
        home = _safe_call(source, "homeContent", True) or {}
        items = _list_from(source, home)
        if items:
            return items, ""
        for cls in classes_from_home(source, home)[:3]:
            extra = cls.get("extend") or {}
            data = _safe_call(source, "categoryContent", cls["type_id"], "1", False, extra) or {}
            items = _list_from(source, data)
            if items:
                return items, ""
        if source == "qiyi":
            data = _safe_call(source, "categoryContent", "1", "1", False, {"class": "2"}) or {}
            items = _list_from(source, data)
            if items:
                return items, ""
    except Exception as exc:  # noqa: BLE001
        errors.append(str(exc))
    return [], "; ".join(errors) or "home empty"


def _search_first(source: str, keyword: str) -> tuple[dict | None, str]:
    try:
        data = _safe_call(source, "searchContent", keyword, False, "1")
        items = _list_from(source, data)
        if items:
            return items[0], ""
        return None, "search empty"
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)


def pick_vod(source: str, keyword: str) -> tuple[dict | None, str]:
    if keyword:
        return _search_first(source, keyword)
    items, err = _home_items(source)
    if items:
        return items[0], ""
    for kw in FALLBACK_KEYWORDS:
        card, _ = _search_first(source, kw)
        if card:
            return card, ""
    return None, err or "home empty"


def first_episode(source: str, vod_id: str) -> tuple[dict | None, dict | None, str]:
    try:
        data = _safe_call(source, "detailContent", [vod_id])
    except Exception as exc:  # noqa: BLE001
        return None, None, str(exc)
    lst = (data or {}).get("list") or []
    if not lst:
        return None, None, "detail empty"
    vod = lst[0]
    groups = parse_episodes(vod, limit=2)
    if not groups or not groups[0]["episodes"]:
        return vod, None, "no episodes"
    return vod, groups[0], ""


def enrich_play(raw: dict, pid: str) -> dict:
    classified = classify_play(raw or {})
    official_hint = classified.get("official") or ""
    if (not official_hint) and str(pid).startswith("http") and not is_direct_media(pid):
        official_hint = pid
    watch = official_hint or classified.get("url") or pid
    if classified.get("mode") == "video":
        parse_urls, official = _parse_urls_for(watch if str(watch).startswith("http") else classified.get("url") or "")
        classified["parse_urls"] = parse_urls
        classified["official"] = official or classified.get("official") or ""
        return classified
    seed = watch if classified.get("mode") == "need_parse" else (classified.get("url") or watch)
    parse_urls, official = _parse_urls_for(seed or watch)
    classified["parse_urls"] = parse_urls
    classified["official"] = official or classified.get("official") or ""
    if parse_urls and classified.get("mode") != "video":
        classified["url"] = parse_urls[0]
    return classified


def collect_jobs(keys: list[str], keyword: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    jobs: list[dict[str, Any]] = []
    skips: list[dict[str, Any]] = []
    for source in keys:
        if source not in spiders:
            skips.append({"source": source, "error": "spider not loaded"})
            continue
        card, err = pick_vod(source, keyword)
        if not card:
            skips.append({"source": source, "error": err or "no vod"})
            continue
        vod, group, err = first_episode(source, card["id"])
        if not group:
            skips.append({"source": source, "title": card.get("title") or "", "error": err or "no episode"})
            continue
        ep = group["episodes"][0]
        flag = group["from"]
        t0 = time.perf_counter()
        try:
            raw = _safe_call(source, "playerContent", flag, ep["id"], [])
        except Exception as exc:  # noqa: BLE001
            skips.append({"source": source, "title": card.get("title") or "", "error": str(exc)})
            continue
        resolve_ms = round((time.perf_counter() - t0) * 1000, 1)
        classified = enrich_play(raw or {}, ep["id"])
        targets = build_probe_targets(classified)
        title = (vod or {}).get("vod_name") or card.get("title") or ""
        if not targets:
            skips.append({"source": source, "title": title, "error": "no probe url"})
            continue
        print(
            f"# resolve {SOURCES[source]['name']}  {title}  {ep.get('title') or ''}  "
            f"{resolve_ms}ms  targets={len(targets)}",
            file=sys.stderr,
        )
        for target in targets:
            jobs.append(
                {
                    "source": source,
                    "source_name": SOURCES[source]["name"],
                    "title": title,
                    "episode": ep.get("title") or "",
                    "role": target["role"],
                    "url": target["url"],
                    "resolve_ms": resolve_ms,
                    "mode": classified.get("mode") or "",
                }
            )
    return jobs, skips


def format_table(rows: list[dict[str, Any]]) -> str:
    headers = ("rank", "source", "title", "role", "kind", "http", "ttfb", "media", "ok", "url")
    lines = ["  ".join(f"{h:<8}" if h != "url" else h for h in headers)]
    for i, row in enumerate(rows, 1):
        title = (row.get("title") or "")[:16]
        url = row.get("url") or ""
        if len(url) > 72:
            url = url[:72] + "…"
        ttfb = row.get("ttfb_ms")
        media = row.get("media_ms")
        http = row.get("http")
        lines.append(
            f"{i:<8}  {row.get('source_name') or row.get('source') or '':<8}  "
            f"{title:<16}  {row.get('role') or '':<8}  {row.get('kind') or '':<8}  "
            f"{http if http is not None else '-':<8}  "
            f"{ttfb if ttfb is not None else '-':<8}  "
            f"{media if media is not None else '-':<8}  "
            f"{'yes' if row.get('ok') else 'no':<8}  {url}"
        )
        if row.get("error"):
            lines.append(f"         error: {row['error']}")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Probe EHR663 play-line latency (official first)")
    ap.add_argument("-q", "--keyword", default="", help="search title; default uses each source's home item")
    ap.add_argument("--all", action="store_true", help="include unofficial spiders after official")
    ap.add_argument("--source", default="", help="comma keys, e.g. qq,youku,qiyi,mgtv")
    ap.add_argument("--timeout", type=float, default=8.0, help="HTTP timeout seconds")
    ap.add_argument("--workers", type=int, default=6, help="probe concurrency")
    ap.add_argument("--json", action="store_true", help="print JSON instead of a table")
    args = ap.parse_args()

    selected = [x.strip() for x in args.source.split(",") if x.strip()]
    wanted = selected or list(SOURCES)
    keys = source_order(wanted, official_only=not args.all and not selected)
    if not keys:
        print("no sources to probe", file=sys.stderr)
        return 2

    load_spiders(only=set(keys))

    print(
        f"# EHR663 latency  sources={','.join(keys)}  keyword={args.keyword or '(home)'}  timeout={args.timeout}s",
        file=sys.stderr,
    )
    jobs, skips = collect_jobs(keys, args.keyword.strip())
    rows: list[dict[str, Any]] = []
    workers = max(1, args.workers)

    def run_one(job: dict[str, Any]) -> dict[str, Any]:
        probed = probe_url(job["url"], timeout=args.timeout)
        out = dict(job)
        out.update(probed)
        return out

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = [pool.submit(run_one, job) for job in jobs]
        for fut in as_completed(futs):
            rows.append(fut.result())

    ranked = rank_rows(rows)
    payload = {"sources": keys, "keyword": args.keyword, "rows": ranked, "skipped": skips}

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if ranked:
            print(format_table(ranked))
        if skips:
            print("\n# skipped")
            for item in skips:
                print(f"  {item.get('source')}: {item.get('error')}  {item.get('title') or ''}")
        ok_official = [r for r in ranked if r.get("source") in ("qq", "youku", "qiyi", "mgtv") and r.get("ok")]
        if ok_official:
            best = ok_official[0]
            print(
                f"\n# fastest official: {best.get('source_name')} {best.get('role')} "
                f"ttfb={best.get('ttfb_ms')}ms kind={best.get('kind')}"
            )
    return 0 if ranked else 2


if __name__ == "__main__":
    raise SystemExit(main())
