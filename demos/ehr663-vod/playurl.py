"""Classify spider play URLs: direct media, jiexi WebView, or official page."""

from urllib.parse import parse_qs, quote, urljoin, urlparse

OFFICIAL_HOSTS = (
    "v.qq.com",
    "film.qq.com",
    "m.v.qq.com",
    "youku.com",
    "v.youku.com",
    "m.youku.com",
    "iqiyi.com",
    "www.iqiyi.com",
    "m.iqiyi.com",
    "mgtv.com",
    "www.mgtv.com",
    "m.mgtv.com",
    "w.mgtv.com",
)

JIEXI_HINTS = (
    "jx.xmflv",
    "jx.playerjy",
    "jx.2s0",
    "jx.m3u8",
    "kptv",
    "daga.cc",
    "xmflv.cc",
    "jiexi",
)


def _host(url: str) -> str:
    try:
        return (urlparse(url).hostname or "").lower()
    except Exception:
        return ""


def is_jiexi(url: str) -> bool:
    raw = (url or "").lower()
    host = _host(url)
    return any(h in raw or h in host for h in JIEXI_HINTS)


def unwrap_jiexi(url: str) -> str:
    raw = (url or "").strip()
    if not raw:
        return ""
    if not is_jiexi(raw):
        return raw
    qs = parse_qs(urlparse(raw).query)
    inner = (qs.get("url") or [""])[0]
    return inner.strip() or raw


def is_direct_media(url: str) -> bool:
    u = (url or "").lower()
    if not u.startswith("http"):
        return False
    if is_jiexi(u):
        return False
    path = urlparse(u).path.lower()
    return any(ext in path or ext in u for ext in (".m3u8", ".mp4", ".flv", ".m3u"))


def is_official_page(url: str) -> bool:
    host = _host(url)
    return any(host == h or host.endswith("." + h) for h in OFFICIAL_HOSTS)


def wrap_parser(prefix: str, official: str) -> str:
    """prefix like https://jx.xmflv.com/?url=  official must be encoded (Youku has ?vid=)."""
    return (prefix or "") + quote(official or "", safe="")


def first_media_uri(playlist: str, base: str) -> str:
    for line in (playlist or "").splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            return urljoin(base, s)
    return ""


def is_av_payload(head: bytes) -> bool:
    if not head:
        return False
    if head.startswith(b"\x89PNG") or head.startswith(b"\xff\xd8\xff") or head.startswith(b"GIF8"):
        return False
    start = head.lstrip()
    if start.startswith((b"<", b"{", b"<!DOCTYPE", b"<!doctype")):
        return False
    if head[:1] == b"\x47":
        return True
    if b"ftyp" in head[:64]:
        return True
    if start.startswith(b"#EXTM3U"):
        return True
    return False


def classify_play(spider_result: dict) -> dict:
    """
    spider_result: playerContent() return value.
    mode: video | parse | need_parse | official
    """
    raw = str((spider_result or {}).get("url") or "").strip()
    parse = (spider_result or {}).get("parse")
    jx = (spider_result or {}).get("jx")

    if is_direct_media(raw):
        return {"mode": "video", "url": raw, "official": "", "parse": 0}

    if is_jiexi(raw):
        return {
            "mode": "parse",
            "url": raw,
            "official": unwrap_jiexi(raw),
            "parse": 1,
        }

    if (parse == 1 or jx == 1) and is_official_page(raw):
        return {"mode": "need_parse", "url": raw, "official": raw, "parse": 1}

    if is_official_page(raw):
        return {"mode": "need_parse", "url": raw, "official": raw, "parse": 1}

    return {"mode": "official", "url": raw, "official": raw, "parse": 1}
