#!/usr/bin/env python3
"""Local UI: search → detail/episodes/lines → play.

  python3 scripts/bpz5-resolve-ui.py
  open http://127.0.0.1:8765

Features: search catalog, display detail/lines, play (direct or resolve-line).
Proxies signed /v1 requests to bpz5 (avoids browser CORS for API).
Also proxies media via /api/media (fixes official CDN Range / wrong MIME).
Docs: docs/souju-playback-api.md
"""

from __future__ import annotations

import argparse
import http.cookiejar
import importlib.util
import json
import re
import ssl
import sys
import threading
import uuid
from http.client import IncompleteRead
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, unquote, urlencode, urljoin, urlparse
from urllib.request import HTTPCookieProcessor, HTTPSHandler, ProxyHandler, Request, build_opener

_SCRIPT_DIR = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "bpz5_resolve_line", _SCRIPT_DIR / "bpz5-resolve-line.py"
)
_mod = importlib.util.module_from_spec(_spec)
assert _spec and _spec.loader
_spec.loader.exec_module(_mod)

request_json = _mod.request_json
sign_headers = _mod.sign_headers
DEFAULT_BASE = _mod.DEFAULT_BASE
DEFAULT_CLIENT = _mod.DEFAULT_CLIENT
DEFAULT_SECRET = _mod.DEFAULT_SECRET

HTML_PATH = _SCRIPT_DIR / "bpz5-resolve-ui.html"
ANON_ID_PATH = _SCRIPT_DIR / ".bpz5-anonymous-id"

CONFIG: dict[str, Any] = {
    "base": DEFAULT_BASE,
    "secret": DEFAULT_SECRET,
    "client": DEFAULT_CLIENT,
}

_COOKIE_JAR = http.cookiejar.CookieJar()
_SESSION_LOCK = threading.Lock()
_SESSION: dict[str, Any] = {
    "ready": False,
    "anonymous_id": "",
    "user_id": "",
    "display_name": "",
    "error": "",
}

_SSL = ssl.create_default_context()
_OPENER = build_opener(
    ProxyHandler({}),
    HTTPSHandler(context=_SSL),
    HTTPCookieProcessor(_COOKIE_JAR),
)


def upstream_get(path_with_query: str) -> tuple[int, Any]:
    url = CONFIG["base"].rstrip("/") + path_with_query
    return request_json("GET", url, CONFIG["secret"], CONFIG["client"])


def _anon_id() -> str:
    if ANON_ID_PATH.is_file():
        val = ANON_ID_PATH.read_text(encoding="utf-8").strip()
        if val:
            return val
    val = f"web_{uuid.uuid4()}"
    try:
        ANON_ID_PATH.write_text(val + "\n", encoding="utf-8")
    except OSError:
        pass
    return val


def _read_body(resp) -> bytes:
    try:
        return resp.read()
    except IncompleteRead as e:
        return e.partial or b""


def session_request(
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
    retries: int = 3,
) -> tuple[int, Any]:
    """Signed request that keeps ai_movie_session cookies."""
    url = CONFIG["base"].rstrip("/") + path
    data = None
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        headers = sign_headers(method, url, CONFIG["secret"], CONFIG["client"])
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode()
            headers["Content-Type"] = "application/json"
        req = Request(url, data=data, headers=headers, method=method)
        try:
            with _OPENER.open(req, timeout=40) as resp:
                raw = _read_body(resp)
                status = getattr(resp, "status", 200)
                if not raw:
                    return status, None
                try:
                    return status, json.loads(raw.decode("utf-8", "replace"))
                except json.JSONDecodeError:
                    return status, raw.decode("utf-8", "replace")
        except HTTPError as e:
            raw = _read_body(e)
            try:
                parsed = json.loads(raw.decode("utf-8", "replace")) if raw else None
            except json.JSONDecodeError:
                parsed = raw.decode("utf-8", "replace") if raw else None
            return e.code, parsed
        except (URLError, TimeoutError, ssl.SSLError, ConnectionError) as e:
            last_err = e
            if attempt < retries:
                import time

                time.sleep(0.4 * attempt)
                continue
            raise RuntimeError(f"session request failed: {method} {url}: {e}") from e
    raise RuntimeError(f"session request failed: {last_err}")


def ensure_anonymous_session(force: bool = False) -> dict[str, Any]:
    """Create / refresh anonymous site session so official resolve-line works."""
    with _SESSION_LOCK:
        if _SESSION["ready"] and not force:
            return dict(_SESSION)
        anon = _anon_id()
        _SESSION["anonymous_id"] = anon
        try:
            status, data = session_request(
                "POST", "/v1/users/anonymous", {"anonymous_id": anon}
            )
            if status >= 400 or not isinstance(data, dict):
                _SESSION.update(
                    {
                        "ready": False,
                        "error": f"anonymous failed: {status} {data}",
                        "user_id": "",
                        "display_name": "",
                    }
                )
                return dict(_SESSION)
            user = data.get("user") if isinstance(data.get("user"), dict) else {}
            _SESSION.update(
                {
                    "ready": True,
                    "error": "",
                    "user_id": str(user.get("id") or ""),
                    "display_name": str(user.get("display_name") or "匿名会话"),
                }
            )
        except Exception as e:
            _SESSION.update(
                {
                    "ready": False,
                    "error": str(e),
                    "user_id": "",
                    "display_name": "",
                }
            )
        return dict(_SESSION)

def parse_range(header: str | None, total: int) -> tuple[int, int] | None:
    if not header or total <= 0:
        return None
    m = re.fullmatch(r"bytes=(\d*)-(\d*)", header.strip())
    if not m:
        return None
    start_s, end_s = m.group(1), m.group(2)
    if start_s == "" and end_s == "":
        return None
    if start_s == "":
        # suffix: last N bytes
        length = int(end_s)
        start = max(0, total - length)
        end = total - 1
    else:
        start = int(start_s)
        end = int(end_s) if end_s else total - 1
    if start < 0 or start >= total or end < start:
        return None
    end = min(end, total - 1)
    return start, end


def sniff_content_type(url: str, body: bytes, upstream_ct: str | None) -> str:
    path = urlparse(url).path.lower()
    if path.endswith(".m3u8") or body.lstrip()[:7] == b"#EXTM3U":
        return "application/vnd.apple.mpegurl"
    if len(body) >= 12 and body[4:8] == b"ftyp":
        return "video/mp4"
    if body[:4] == b"\x1aE\xdf\xa3":
        return "video/webm"
    # Official C: PNG/JPEG wrapper + MPEG-TS payload (often after 120-byte header)
    if body[:1] == b"G" or (len(body) > 120 and body[120] == 0x47):
        return "video/mp2t"
    if len(body) >= 188 and body[0] == 0x47:
        return "video/mp2t"
    ct = (upstream_ct or "").split(";")[0].strip().lower()
    if ct in ("image/jpeg", "image/png", "binary/octet-stream", "application/octet-stream"):
        if len(body) >= 12 and body[4:8] == b"ftyp":
            return "video/mp4"
        if body[:1] == b"G" or (len(body) > 120 and body[120] == 0x47):
            return "video/mp2t"
    if ct and ct not in ("image/jpeg", "image/png"):
        return ct
    if path.endswith(".mp4"):
        return "video/mp4"
    if path.endswith((".ts", ".m2ts")):
        return "video/mp2t"
    return ct or "application/octet-stream"


def rewrite_m3u8(text: str, playlist_url: str) -> bytes:
    out: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            out.append(raw)
            continue
        abs_url = urljoin(playlist_url, line)
        out.append("/api/media?url=" + quote(abs_url, safe=""))
    return ("\n".join(out) + "\n").encode("utf-8")


def media_req_headers(range_header: str | None = None) -> dict[str, str]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "*/*",
        "Referer": CONFIG["base"].rstrip("/") + "/",
        "Origin": CONFIG["base"].rstrip("/"),
    }
    if range_header:
        headers["Range"] = range_header
    return headers


def host_needs_range_fix(url: str) -> bool:
    """wikjdd official-C segments ignore Range and wrap TS in PNG."""
    host = urlparse(url).hostname or ""
    return host.endswith("wikjdd.cn") or host.endswith("zshtys888.com")


def force_video_content_type(url: str, upstream_ct: str | None) -> str:
    path = urlparse(url).path.lower()
    ct = (upstream_ct or "").split(";")[0].strip().lower()
    host = urlparse(url).hostname or ""
    if path.endswith(".m3u8"):
        return "application/vnd.apple.mpegurl"
    if host.endswith("byteimg.com") or "cmecloud" in host or path.endswith(".mp4"):
        return "video/mp4"
    if path.endswith(".png") or path.endswith(".jpg") or path.endswith(".jpeg"):
        # disguised segments / progressive
        if host.endswith("wikjdd.cn"):
            return "video/mp2t"
        return "video/mp4"
    if ct in ("image/jpeg", "image/png", "binary/octet-stream"):
        return "video/mp4"
    return ct or "application/octet-stream"


def fetch_media(url: str, range_header: str | None) -> tuple[int, dict[str, str], bytes]:
    req = Request(url, headers=media_req_headers(range_header), method="GET")
    try:
        with _OPENER.open(req, timeout=45) as resp:
            status = getattr(resp, "status", 200)
            body = _read_body(resp)
            meta = {
                "Content-Type": resp.headers.get("Content-Type") or "",
                "Content-Range": resp.headers.get("Content-Range") or "",
                "Accept-Ranges": resp.headers.get("Accept-Ranges") or "",
                "Content-Length": resp.headers.get("Content-Length") or "",
            }
            return status, meta, body
    except HTTPError as e:
        body = _read_body(e)
        meta = {
            "Content-Type": e.headers.get("Content-Type") if e.headers else "",
            "Content-Range": e.headers.get("Content-Range") if e.headers else "",
            "Accept-Ranges": e.headers.get("Accept-Ranges") if e.headers else "",
            "Content-Length": e.headers.get("Content-Length") if e.headers else "",
        }
        return e.code, meta, body


class Handler(BaseHTTPRequestHandler):
    server_version = "bpz5-resolve-ui/2.2"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Range")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")

    def _send(self, code: int, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        if extra:
            for k, v in extra.items():
                if v:
                    self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, code: int, obj: Any) -> None:
        raw = json.dumps(obj, ensure_ascii=False).encode()
        self._send(code, raw, "application/json; charset=utf-8")

    def _proxy_result(self, status: int, data: Any) -> None:
        if isinstance(data, (dict, list)):
            self._json(status if 200 <= status < 600 else 502, data)
        else:
            self._json(status, {"error": data})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _stream_media(self, url: str, range_header: str | None) -> None:
        """Stream large MP4 etc. without buffering the whole file."""
        req = Request(url, headers=media_req_headers(range_header), method="GET")
        try:
            resp = _OPENER.open(req, timeout=60)
        except HTTPError as e:
            body = _read_body(e)
            self._send(e.code, body or b"", e.headers.get("Content-Type") if e.headers else "application/octet-stream")
            return
        except (URLError, TimeoutError, ssl.SSLError, ConnectionError) as e:
            self._json(502, {"error": f"media fetch failed: {e}"})
            return

        try:
            status = getattr(resp, "status", 200)
            upstream_ct = resp.headers.get("Content-Type") or ""
            ct = force_video_content_type(url, upstream_ct)
            self.send_response(status)
            self.send_header("Content-Type", ct)
            self.send_header("Cache-Control", "no-store")
            self._cors()
            for hk in ("Content-Length", "Content-Range", "Accept-Ranges"):
                hv = resp.headers.get(hk)
                if hv:
                    self.send_header(hk, hv)
            if not resp.headers.get("Accept-Ranges"):
                self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            while True:
                chunk = resp.read(64 * 1024)
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    break
        finally:
            try:
                resp.close()
            except Exception:
                pass

    def _handle_media(self, qs: dict[str, list[str]]) -> None:
        url = (qs.get("url") or [""])[0].strip()
        if not url.startswith(("http://", "https://")):
            self._json(400, {"error": "url required"})
            return

        range_header = self.headers.get("Range")
        path = urlparse(url).path.lower()
        is_playlist = path.endswith(".m3u8")
        needs_buffer = is_playlist or host_needs_range_fix(url)

        # Large progressive MP4 (官方 V/Z/腾讯): stream only
        if not needs_buffer:
            self._stream_media(url, range_header)
            return

        try:
            # For Range-broken PNG segments, always fetch full object then slice
            fetch_range = None if host_needs_range_fix(url) else range_header
            status, meta, body = fetch_media(url, fetch_range)
        except (URLError, TimeoutError, ssl.SSLError, ConnectionError) as e:
            self._json(502, {"error": f"media fetch failed: {e}"})
            return

        if status >= 400:
            self._send(status, body or b"", meta.get("Content-Type") or "application/octet-stream")
            return

        ct = sniff_content_type(url, body, meta.get("Content-Type"))

        if ct == "application/vnd.apple.mpegurl" or body.lstrip().startswith(b"#EXTM3U"):
            text = body.decode("utf-8", "replace")
            body = rewrite_m3u8(text, url)
            self._send(200, body, "application/vnd.apple.mpegurl", {"Accept-Ranges": "bytes"})
            return

        # Satisfy HLS.js BYTERANGE when upstream ignored Range
        if range_header and (status == 200 or host_needs_range_fix(url)):
            rng = parse_range(range_header, len(body))
            if rng:
                start, end = rng
                piece = body[start : end + 1]
                piece_ct = sniff_content_type(url, piece, ct)
                extra = {
                    "Accept-Ranges": "bytes",
                    "Content-Range": f"bytes {start}-{end}/{len(body)}",
                }
                self._send(206, piece, piece_ct, extra)
                return

        extra = {"Accept-Ranges": "bytes"}
        if status == 206 and meta.get("Content-Range"):
            extra["Content-Range"] = meta["Content-Range"]
            self._send(206, body, ct, extra)
            return

        self._send(200, body, ct, extra)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query, keep_blank_values=False)

        if path in ("/", "/index.html"):
            self._send(200, HTML_PATH.read_bytes(), "text/html; charset=utf-8")
            return

        if path == "/api/health":
            sess = ensure_anonymous_session()
            self._json(
                200,
                {
                    "ok": True,
                    "base": CONFIG["base"],
                    "media_proxy": True,
                    "session": {
                        "ready": sess.get("ready"),
                        "display_name": sess.get("display_name"),
                        "user_id": sess.get("user_id"),
                        "error": sess.get("error"),
                    },
                },
            )
            return

        if path == "/api/session/ensure":
            self._json(200, ensure_anonymous_session(force=True))
            return

        if path == "/api/media":
            self._handle_media(qs)
            return

        try:
            if path == "/api/suggest":
                q = (qs.get("q") or [""])[0].strip()
                if not q:
                    self._json(400, {"error": "q required"})
                    return
                limit = (qs.get("limit") or ["12"])[0]
                params = urlencode({"q": q, "limit": limit, "mode": "home"})
                status, data = upstream_get(f"/v1/suggest?{params}")
                self._proxy_result(status, data)
                return

            if path == "/api/browse/catalog":
                q = (qs.get("q") or [""])[0].strip()
                page = (qs.get("page") or ["1"])[0]
                limit = (qs.get("limit") or ["20"])[0]
                params: dict[str, str] = {
                    "page": page,
                    "limit": limit,
                    "intent": "catalog_search" if q else "latest_catalog",
                }
                if q:
                    params["q"] = q
                status, data = upstream_get(f"/v1/browse/catalog?{urlencode(params)}")
                self._proxy_result(status, data)
                return

            if path == "/api/feed/home":
                status, data = upstream_get("/v1/feed/home")
                self._proxy_result(status, data)
                return

            m = re.fullmatch(r"/api/catalog/([^/]+)", path)
            if m:
                vid = unquote(m.group(1))
                status, data = upstream_get(f"/v1/catalog/{quote(vid, safe='')}")
                self._proxy_result(status, data)
                return

            m = re.fullmatch(r"/api/catalog/([^/]+)/episodes", path)
            if m:
                vid = unquote(m.group(1))
                offset = (qs.get("offset") or ["0"])[0]
                limit = (qs.get("limit") or ["40"])[0]
                params = urlencode({"offset": offset, "limit": limit})
                status, data = upstream_get(
                    f"/v1/catalog/{quote(vid, safe='')}/episodes?{params}"
                )
                self._proxy_result(status, data)
                return

            m = re.fullmatch(r"/api/playback/resolve/([^/]+)", path)
            if m:
                token = unquote(m.group(1))
                status, data = upstream_get(f"/v1/playback/resolve/{quote(token, safe='')}")
                self._proxy_result(status, data)
                return

        except Exception as e:
            self._json(502, {"error": str(e)})
            return

        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/playback/resolve-line":
            self._json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid json"})
            return

        ticket = (body.get("ticket") or "").strip()
        if not ticket:
            self._json(400, {"error": "ticket required"})
            return

        try:
            sess = ensure_anonymous_session()
            status, data = session_request(
                "POST", "/v1/playback/resolve-line", {"ticket": ticket}
            )
            # Session expired / missing → refresh anonymous once and retry
            if (
                status == 401
                and isinstance(data, dict)
                and data.get("code") == "playback_user_session_required"
            ):
                sess = ensure_anonymous_session(force=True)
                status, data = session_request(
                    "POST", "/v1/playback/resolve-line", {"ticket": ticket}
                )
            if isinstance(data, dict):
                data = {**data, "_session": {"ready": sess.get("ready"), "name": sess.get("display_name")}}
        except Exception as e:
            self._json(502, {"error": str(e)})
            return

        self._proxy_result(status, data)


def main() -> int:
    ap = argparse.ArgumentParser(description="bpz5 catalog + resolve UI (local)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--secret", default=DEFAULT_SECRET)
    ap.add_argument("--client", default=DEFAULT_CLIENT)
    ap.add_argument("--no-open", action="store_true", help="do not open browser")
    args = ap.parse_args()

    if not HTML_PATH.is_file():
        print(f"missing UI file: {HTML_PATH}", file=sys.stderr)
        return 1

    CONFIG["base"] = args.base.rstrip("/")
    CONFIG["secret"] = args.secret
    CONFIG["client"] = args.client

    sess = ensure_anonymous_session()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}/"
    print(f"bpz5 catalog UI → {url}")
    print(f"upstream base   → {CONFIG['base']}")
    print("media proxy      → /api/media?url=...")
    if sess.get("ready"):
        print(f"anon session    → {sess.get('display_name')} ({sess.get('user_id')})")
    else:
        print(f"anon session    → FAILED: {sess.get('error')}")
    print("Keep this terminal open. Ctrl+C to stop.")

    if not args.no_open:
        import threading
        import webbrowser

        threading.Timer(0.4, lambda: webbrowser.open(url)).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
