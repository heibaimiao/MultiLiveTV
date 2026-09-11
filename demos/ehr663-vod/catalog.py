"""Normalize EHR663 spider homeContent into Demo category tabs."""

from __future__ import annotations

import re


def classes_from_home(source: str, home: dict | None) -> list[dict]:
    home = home or {}
    if source == "qiyi":
        return _qiyi_genre_classes(home)
    out = []
    for item in home.get("class") or []:
        tid = str(item.get("type_id") or "").strip()
        name = re.sub(r"<[^>]+>", "", str(item.get("type_name") or "")).strip()
        if not tid or not name:
            continue
        out.append({"id": tid, "type_id": tid, "type_name": name, "extend": {}})
    return out


def _qiyi_genre_classes(home: dict) -> list[dict]:
    """爱奇艺脚本的 class 是平台（腾讯/爱奇艺/…），影视类型在 filters.class。"""
    filters = (home.get("filters") or {}).get("2") or []
    type_filter = next((f for f in filters if f.get("key") == "class"), None)
    values = (type_filter or {}).get("value") or [
        {"n": "电视剧", "v": "2"},
        {"n": "电影", "v": "1"},
        {"n": "动漫", "v": "4"},
        {"n": "综艺", "v": "3"},
        {"n": "少儿", "v": "5"},
        {"n": "纪录片", "v": "6"},
        {"n": "短剧", "v": "7"},
    ]
    out = []
    for item in values:
        name = str(item.get("n") or "").strip()
        vid = str(item.get("v") or "").strip()
        if not name or not vid or name == "全部":
            continue
        out.append(
            {
                "id": f"qiyi:{vid}",
                "type_id": "2",
                "type_name": name,
                "extend": {"class": vid},
            }
        )
    return out
