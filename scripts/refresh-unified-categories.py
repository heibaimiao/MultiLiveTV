#!/usr/bin/env python3
"""Refresh unified-categories.json from MacCMS class lists or local snapshots."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "apps/api-go/config/sources.json"
SNAP_DIR = ROOT / "web/config/category-snapshots"
OUT_PATHS = [
    ROOT / "apps/api-go/config/unified-categories.json",
    ROOT / "web/config/unified-categories.json",
    ROOT / "clients/apple/MultiLiveTV/Resources/unified-categories.json",
]

ALIASES = {
    "电视剧": "剧集",
    "连续剧": "剧集",
    "日本剧": "日剧",
    "韩国剧": "韩剧",
    "泰国剧": "泰剧",
    "台湾剧": "台剧",
    "香港剧": "港剧",
    "大陆剧": "国产剧",
    "记录片": "纪录片",
    "日本动漫": "日韩动漫",
    "电影片": "电影",
    "综艺片": "综艺",
    "动漫片": "动漫",
    "国产片": "电影",
}

TREE_TEMPLATE = [
    (
        "movie",
        "电影",
        [
            ("movie-action", "动作片"),
            ("movie-comedy", "喜剧片"),
            ("movie-romance", "爱情片"),
            ("movie-scifi", "科幻片"),
            ("movie-horror", "恐怖片"),
            ("movie-drama", "剧情片"),
            ("movie-war", "战争片"),
            ("movie-doc", "纪录片"),
            ("movie-cartoon", "动画片"),
        ],
    ),
    (
        "tv",
        "剧集",
        [
            ("tv-cn", "国产剧"),
            ("tv-hk", "港剧"),
            ("tv-tw", "台剧"),
            ("tv-jp", "日剧"),
            ("tv-kr", "韩剧"),
            ("tv-th", "泰剧"),
            ("tv-us", "欧美剧"),
            ("tv-oversea", "海外剧"),
        ],
    ),
    (
        "variety",
        "综艺",
        [
            ("variety-cn", "大陆综艺"),
            ("variety-hktw", "港台综艺"),
            ("variety-jpkr", "日韩综艺"),
            ("variety-us", "欧美综艺"),
        ],
    ),
    (
        "anime",
        "动漫",
        [
            ("anime-cn", "国产动漫"),
            ("anime-jpkr", "日韩动漫"),
            ("anime-us", "欧美动漫"),
            ("anime-oversea", "海外动漫"),
            ("anime-hktw", "港台动漫"),
        ],
    ),
    (
        "short",
        "短剧",
        [
            ("short-xianxia", "古装仙侠"),
            ("short-urban", "现代都市"),
            ("short-twist", "反转爽剧"),
            ("short-suspense", "脑洞悬疑"),
        ],
    ),
]

UA = "Mozilla/5.0 (compatible; MultiLiveTV-category-refresh/1.0)"


def norm(name: str) -> str:
    cleaned = (name or "").replace("[关]", "").strip()
    cleaned = re.sub(r"x$", "", cleaned, flags=re.I).strip()
    return ALIASES.get(cleaned, cleaned)


def visible(name: str) -> bool:
    if "[关]" in (name or ""):
        return False
    if re.search(r"x$", (name or "").strip(), re.I):
        return False
    if "伦理" in (name or "") or "倫理" in (name or ""):
        return False
    return True


def fetch_class(url: str) -> list[dict]:
    base = url if url.endswith("/") else url + "/"
    req = urllib.request.Request(
        base + "?ac=list&pg=1",
        headers={"User-Agent": UA, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8", "replace"))
    return data.get("class") or []


def load_from_snapshots() -> dict[str, dict[str, int]]:
    mapping: dict[str, dict[str, int]] = {}
    index_path = SNAP_DIR / "_index.json"
    if not index_path.exists():
        raise SystemExit(f"missing snapshots index: {index_path}")
    index = json.loads(index_path.read_text())
    for source in index.get("sources") or []:
        if not source.get("ok"):
            continue
        path = SNAP_DIR / f"{source['id']}-{source['name']}.json"
        if not path.exists():
            continue
        snap = json.loads(path.read_text())
        for item in snap.get("classes") or []:
            name = item.get("type_name") or ""
            if not visible(name):
                continue
            label = norm(name)
            mapping.setdefault(label, {})
            mapping[label].setdefault(str(source["id"]), int(item["type_id"]))
    return mapping


def load_from_network() -> dict[str, dict[str, int]]:
    sources = json.loads(SOURCES.read_text())
    mapping: dict[str, dict[str, int]] = {}
    for source in sources:
        if source.get("flag") != 0:
            continue
        sid = str(source["id"])
        try:
            classes = fetch_class(source["url"])
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {sid} {source.get('name')}: {exc}", file=sys.stderr)
            continue
        print(f"OK   {sid} {source.get('name')}: {len(classes)} classes")
        for item in classes:
            name = item.get("type_name") or ""
            if not visible(name):
                continue
            label = norm(name)
            mapping.setdefault(label, {})
            mapping[label].setdefault(sid, int(item["type_id"]))
    return mapping


def build_tree(mapping: dict[str, dict[str, int]]) -> dict:
    tree = []
    for slug, label, children in TREE_TEMPLATE:
        node = {
            "slug": slug,
            "label": label,
            "sources": dict(
                sorted(mapping.get(label, {}).items(), key=lambda x: int(x[0]))
            ),
            "children": [],
        }
        for child_slug, child_label in children:
            srcs = dict(
                sorted(
                    mapping.get(child_label, {}).items(), key=lambda x: int(x[0])
                )
            )
            node["children"].append(
                {"slug": child_slug, "label": child_label, "sources": srcs}
            )
        tree.append(node)
    return {
        "version": 1,
        "generated_at": datetime.now(
            timezone(timedelta(hours=8))
        ).isoformat(timespec="seconds"),
        "aliases": ALIASES,
        "defaultSlug": "movie",
        "tree": tree,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--from-snapshots",
        action="store_true",
        help="use web/config/category-snapshots instead of live fetch",
    )
    ap.add_argument(
        "--min-movie",
        type=int,
        default=15,
        help="fail if movie coverage below this",
    )
    args = ap.parse_args()

    mapping = load_from_snapshots() if args.from_snapshots else load_from_network()
    payload = build_tree(mapping)
    movie_n = len(payload["tree"][0]["sources"])
    if movie_n < args.min_movie:
        raise SystemExit(f"movie coverage {movie_n} < {args.min_movie}")

    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    for path in OUT_PATHS:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print("wrote", path)

    for node in payload["tree"]:
        print(
            f"{node['slug']}: {len(node['sources'])} sources, "
            f"{len(node['children'])} children"
        )


if __name__ == "__main__":
    main()
