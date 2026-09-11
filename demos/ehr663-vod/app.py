#!/usr/bin/env python3
"""Minimal VOD demo wrapping EHR663 TVBox Python spiders. Do not rewrite those scripts."""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import threading
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote, unquote, urljoin

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
import requests

from catalog import classes_from_home
from playurl import classify_play, first_media_uri, is_av_payload, is_direct_media, is_jiexi, unwrap_jiexi, wrap_parser
from source import FAST_PARSER_PREFIXES

ROOT = Path(__file__).resolve().parent
EHR_ROOT = ROOT.parent / "EHR663"
EHR_PY = EHR_ROOT / "py"
EHR_REPO = "https://github.com/FGBLH/EHR663.git"
STATIC = ROOT / "static"

sys.path.insert(0, str(ROOT))

SOURCES = {
    "qq": {"name": "腾讯视频", "file": "腾讯视频.py"},
    "youku": {"name": "优酷", "file": "优酷视频.py"},
    "qiyi": {"name": "爱奇艺", "file": "腾爱优芒B🍀TG @hshsjk9.py"},
    "mgtv": {"name": "芒果TV", "file": "芒果TV.py"},
    "mifun": {"name": "MiFun动漫", "file": "MiFun动漫.py"},
    "ghgdm": {"name": "共和国动漫", "file": "共和国动漫🍀TG @hshsjk9.py"},
    "dm845": {"name": "动漫巴士", "file": "动漫巴士.py"},
    "dmla": {"name": "动漫啦", "file": "动漫啦.py"},
}

spiders: dict = {}
card_cache: dict[tuple[str, str], dict] = {}
_home_raw: dict[str, dict] = {}
_home_lock = threading.Lock()
_init_lock = threading.Lock()
_inited = False
_home_lock = threading.Lock()
_home_raw: dict[str, dict] = {}


def ensure_ehr663() -> None:
    if (EHR_PY / "腾讯视频.py").exists():
        return
    EHR_ROOT.parent.mkdir(parents=True, exist_ok=True)
    if EHR_ROOT.exists() and not (EHR_PY / "腾讯视频.py").exists():
        raise RuntimeError(f"EHR663 目录不完整: {EHR_ROOT}")
    print(f"Cloning EHR663 into {EHR_ROOT} ...")
    subprocess.check_call(["git", "clone", "--depth", "1", EHR_REPO, str(EHR_ROOT)])


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_spiders(only: set[str] | None = None) -> None:
    global _inited
    with _init_lock:
        if _inited:
            return
        ensure_ehr663()
        for key, meta in SOURCES.items():
            if only is not None and key not in only:
                continue
            path = EHR_PY / meta["file"]
            if not path.exists():
                print(f"missing spider file: {path}")
                continue
            try:
                mod = _load_module(f"ehr_{key}", path)
                spider = mod.Spider()
                try:
                    spider.init("")
                except Exception as exc:
                    print(f"{key} init warning: {exc}")
                spiders[key] = spider
                print(f"loaded {key}: {meta['file']}")
            except Exception as exc:
                print(f"failed to load {key}: {exc}")
        _inited = True


def _norm_card(source: str, item: dict) -> dict | None:
    vod_id = str(item.get("vod_id") or "").strip()
    name = (item.get("vod_name") or "").strip()
    if not vod_id or not name:
        return None
    card = {
        "source": source,
        "source_name": SOURCES[source]["name"],
        "id": vod_id,
        "title": name,
        "pic": item.get("vod_pic") or "",
        "year": item.get("vod_year") or "",
        "remarks": item.get("vod_remarks") or "",
    }
    card_cache[(source, vod_id)] = card
    return card


def _list_from(source: str, data: dict) -> list[dict]:
    out = []
    for item in (data or {}).get("list") or []:
        card = _norm_card(source, item)
        if card:
            out.append(card)
    return out


def _safe_call(source: str, method: str, *args):
    spider = spiders.get(source)
    if spider is None:
        raise HTTPException(503, f"{source} 脚本未加载")
    fn = getattr(spider, method)
    return fn(*args)


def parse_episodes(vod: dict, limit: int = 80) -> list[dict]:
    froms = str(vod.get("vod_play_from") or "播放").split("$$$")
    blocks = str(vod.get("vod_play_url") or "").split("$$$")
    groups = []
    for name, block in zip(froms, blocks):
        episodes = []
        for part in block.split("#"):
            part = part.strip()
            if not part or "$" not in part:
                continue
            title, pid = part.split("$", 1)
            episodes.append({"title": title, "id": pid})
            if len(episodes) >= limit:
                break
        if episodes:
            groups.append({"from": name, "episodes": episodes})
    return groups


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_spiders()
    yield


app = FastAPI(title="EHR663 VOD Demo", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=str(STATIC)), name="static")


@app.get("/")
def index():
    return FileResponse(
        STATIC / "index.html",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/api/sources")
def api_sources():
    return {
        "sources": [
            {"key": k, "name": v["name"], "file": v["file"], "ready": k in spiders}
            for k, v in SOURCES.items()
        ]
    }


@app.get("/api/home")
def api_home(source: str = Query("qq")):
    if source not in SOURCES:
        raise HTTPException(404, "unknown source")
    items: list[dict] = []
    error = None
    try:
        if source == "qiyi":
            data = _safe_call(source, "categoryContent", "2", "1", False, {"class": "2"})
        else:
            data = _safe_call(source, "homeVideoContent") or {}
        items = _list_from(source, data)
        home = {}
        if not items:
            home = _home_content(source)
            items = _list_from(source, home)
        if not items:
            classes = classes_from_home(source, home)
            if classes:
                first = classes[0]
                extra = first.get("extend") or {}
                data = _safe_call(source, "categoryContent", first["type_id"], "1", False, extra)
                items = _list_from(source, data)
    except Exception as exc:
        error = str(exc)
    return {"source": source, "source_name": SOURCES[source]["name"], "list": items, "error": error}


def _home_content(source: str) -> dict:
    with _home_lock:
        cached = _home_raw.get(source)
        if cached is not None:
            return cached
    data = _safe_call(source, "homeContent", True) or {}
    with _home_lock:
        _home_raw[source] = data
        return data


def _parse_extend(raw: str) -> dict:
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


@app.get("/api/classes")
def api_classes(source: str = Query("qq")):
    if source not in SOURCES:
        raise HTTPException(404, "unknown source")
    try:
        classes = classes_from_home(source, _home_content(source))
        return {"source": source, "source_name": SOURCES[source]["name"], "classes": classes}
    except Exception as exc:
        return {
            "source": source,
            "source_name": SOURCES[source]["name"],
            "classes": classes_from_home(source, {}),
            "error": str(exc),
        }


@app.get("/api/category")
def api_category(
    source: str = Query(...),
    tid: str = Query(...),
    pg: str = Query("1"),
    extend: str = Query(""),
):
    if source not in SOURCES:
        raise HTTPException(404, "unknown source")
    extra = _parse_extend(extend)
    try:
        _home_content(source)
    except Exception:
        pass
    try:
        data = _safe_call(source, "categoryContent", tid, str(pg), False, extra) or {}
        return {
            "source": source,
            "source_name": SOURCES[source]["name"],
            "tid": tid,
            "page": str(pg),
            "pagecount": data.get("pagecount") or 1,
            "list": _list_from(source, data),
        }
    except Exception as exc:
        return {
            "source": source,
            "source_name": SOURCES[source]["name"],
            "tid": tid,
            "page": str(pg),
            "pagecount": 1,
            "list": [],
            "error": str(exc),
        }


@app.get("/api/search")
def api_search(q: str = Query(..., min_length=1)):
    results = []
    errors = {}

    def one(source: str):
        try:
            data = _safe_call(source, "searchContent", q, False, "1")
            return source, _list_from(source, data), None
        except Exception as exc:
            return source, [], str(exc)

    with ThreadPoolExecutor(max_workers=8) as pool:
        futs = [pool.submit(one, key) for key in SOURCES]
        for fut in as_completed(futs):
            source, items, err = fut.result()
            if err:
                errors[source] = err
            results.extend(items)

    order = {k: i for i, k in enumerate(SOURCES)}
    results.sort(key=lambda x: (order.get(x["source"], 99), x["title"]))
    return {"q": q, "list": results, "errors": errors}


@app.get("/api/detail/{source}/{vod_id:path}")
def api_detail(source: str, vod_id: str):
    if source not in SOURCES:
        raise HTTPException(404, "unknown source")
    vod_id = unquote(vod_id)
    try:
        data = _safe_call(source, "detailContent", [vod_id])
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc
    lst = (data or {}).get("list") or []
    if not lst:
        raise HTTPException(404, "not found")
    vod = lst[0]
    cached = card_cache.get((source, vod_id)) or {}
    return {
        "source": source,
        "source_name": SOURCES[source]["name"],
        "id": vod_id,
        "title": vod.get("vod_name") or cached.get("title") or "",
        "pic": vod.get("vod_pic") or cached.get("pic") or "",
        "year": vod.get("vod_year") or cached.get("year") or "",
        "area": vod.get("vod_area") or "",
        "actor": vod.get("vod_actor") or "",
        "content": vod.get("vod_content") or "",
        "remarks": vod.get("vod_remarks") or cached.get("remarks") or "",
        "play_from": vod.get("vod_play_from") or "",
        "episodes": parse_episodes(vod),
    }


# 实测可用：xmflv.cc / m3u8.tv。已去掉延迟高的 xmflv.com，以及失效的 playerjy、2s0、kptv、daga。
WORKING_PARSER_PREFIXES = list(FAST_PARSER_PREFIXES)


def _parser_prefixes() -> list[str]:
    return list(WORKING_PARSER_PREFIXES)


def _parse_urls_for(url: str) -> tuple[list[str], str]:
    official = unwrap_jiexi(url) if is_jiexi(url) else url
    urls: list[str] = []
    if official.startswith("http"):
        for prefix in _parser_prefixes():
            wrapped = wrap_parser(prefix, official)
            if wrapped not in urls:
                urls.append(wrapped)
    return urls, official


def _peek_bytes(url: str, n: int = 32) -> bytes:
    rsp = requests.get(
        url,
        headers={"User-Agent": "Mozilla/5.0"},
        timeout=8,
        verify=False,
        stream=True,
    )
    if rsp.status_code != 200:
        return b""
    return next(rsp.iter_content(n), b"") or b""


def _media_ok(url: str) -> bool:
    if not url or not url.startswith("http"):
        return False
    try:
        rsp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=8, verify=False)
        if rsp.status_code != 200:
            return False
        head = rsp.content[:24]
        ctype = (rsp.headers.get("content-type") or "").lower()
        if "mp4" in ctype or url.lower().endswith(".mp4"):
            return is_av_payload(head)
        text = rsp.content.decode("utf-8", errors="ignore")
        if "#EXTM3U" not in text[:80] and "mpegurl" not in ctype:
            return False
        first = first_media_uri(text, url)
        if not first:
            return False
        seg = _peek_bytes(first)
        if seg.lstrip().startswith(b"#EXT"):
            nested = first_media_uri(seg.decode("utf-8", errors="ignore"), first)
            if not nested:
                return False
            seg = _peek_bytes(nested)
        return is_av_payload(seg)
    except Exception:
        return False


def _play_payload(source: str, pid: str, classified: dict, raw_parse) -> dict:
    return {
        "source": source,
        "source_name": SOURCES[source]["name"],
        "id": pid,
        "mode": classified.get("mode"),
        "url": classified.get("url") or "",
        "official": classified.get("official") or "",
        "parse_urls": classified.get("parse_urls") or [],
        "raw_parse": raw_parse,
    }


def _play(source: str, pid: str) -> dict:
    if source not in SOURCES:
        raise HTTPException(404, "unknown source")
    pid = unquote(pid or "")
    if not pid:
        raise HTTPException(400, "missing id")

    if is_direct_media(pid):
        classified = {"mode": "video" if _media_ok(pid) else "parse", "url": pid, "official": ""}
        parse_urls, official = _parse_urls_for(pid)
        classified["parse_urls"] = parse_urls
        classified["official"] = official
        if classified["mode"] != "video":
            classified["url"] = (parse_urls[0] if parse_urls else pid)
        return _play_payload(source, pid, classified, 0 if classified["mode"] == "video" else 1)

    try:
        raw = _safe_call(source, "playerContent", SOURCES[source]["name"], pid, [])
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc

    classified = classify_play(raw or {})
    official_hint = classified.get("official") or ""
    if (not official_hint) and str(pid).startswith("http") and not is_direct_media(pid):
        official_hint = pid
    watch = official_hint or classified.get("url") or pid

    if classified["mode"] == "video" and _media_ok(classified.get("url") or ""):
        parse_urls, official = _parse_urls_for(watch if str(watch).startswith("http") else classified["url"])
        classified["parse_urls"] = parse_urls
        classified["official"] = official
        return _play_payload(source, pid, classified, 0)

    seed = watch if classified["mode"] == "need_parse" else (classified.get("url") or watch)
    parse_urls, official = _parse_urls_for(seed or watch)
    return _play_payload(
        source,
        pid,
        {
            "mode": "parse" if parse_urls else "official",
            "url": (parse_urls[0] if parse_urls else official) or watch,
            "official": official,
            "parse_urls": parse_urls,
        },
        1,
    )


@app.get("/api/play/{source}")
def api_play_query(source: str, id: str = Query(...)):
    return _play(source, id)


@app.get("/api/play/{source}/{play_id:path}")
def api_play_path(source: str, play_id: str):
    return _play(source, play_id)


def _rewrite_playlist(text: str, base: str) -> str:
    lines = []
    for line in text.splitlines():
        raw = line.strip()
        if raw.startswith("#EXT-X-KEY") and "URI=" in raw:

            def repl(m):
                uri = m.group(1)
                abs_url = urljoin(base, uri)
                return f'URI="/api/media?url={quote(abs_url, safe="")}"'

            lines.append(re.sub(r'URI="([^"]+)"', repl, line))
        elif raw and not raw.startswith("#"):
            abs_url = urljoin(base, raw)
            lines.append("/api/media?url=" + quote(abs_url, safe=""))
        else:
            lines.append(line)
    return "\n".join(lines) + "\n"


@app.get("/api/media")
def api_media(url: str = Query(...)):
    target = unquote(url)
    if not target.startswith(("http://", "https://")):
        raise HTTPException(400, "invalid url")
    try:
        rsp = requests.get(
            target,
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=20,
            verify=False,
        )
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc
    if rsp.status_code >= 400:
        raise HTTPException(rsp.status_code, "upstream error")
    content = rsp.content
    ctype = (rsp.headers.get("content-type") or "").lower()
    is_list = "mpegurl" in ctype or content.lstrip().startswith(b"#EXT")
    if is_list:
        text = content.decode("utf-8", errors="replace")
        return Response(
            _rewrite_playlist(text, target),
            media_type="application/vnd.apple.mpegurl",
            headers={"Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"},
        )
    return Response(
        content,
        media_type=ctype or "video/MP2T",
        headers={"Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"},
    )


if __name__ == "__main__":
    import uvicorn

    load_spiders()
    uvicorn.run(app, host="0.0.0.0", port=8000)
