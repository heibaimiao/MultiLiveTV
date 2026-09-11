#!/usr/bin/env python3
"""Minimal bpz5 / souju playback ticket resolver (local verification only).

Docs: docs/souju-playback-api.md

Flow:
  1) GET  /v1/playback/resolve/{episode_token}
  2) POST /v1/playback/resolve-line  {"ticket": "rpt1...."}

Requires the frontend HMAC secret (may rotate anytime).

Examples:
  python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3
  python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3 --parse-only
  python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3 --only cloudflare,qq
  python3 scripts/bpz5-resolve-line.py YJ-xxx --tickets-only
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import ssl
import sys
import time
import uuid
from http.client import IncompleteRead
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

DEFAULT_BASE = "https://bpz5.com"
DEFAULT_SECRET = "f39d73aa7a6426203cdee1ef17b31d3b7ea8c23f4c59c62a3a8aa0f39ee5e79d"
DEFAULT_CLIENT = "movie-search-frontend"


def sign_headers(method: str, url: str, secret: str, client: str) -> dict[str, str]:
    parsed = urlparse(url)
    path = parsed.path + (("?" + parsed.query) if parsed.query else "")
    ts = str(int(time.time() * 1000))
    nonce = uuid.uuid4().hex
    payload = f"{method}\n{path}\n{ts}\n{nonce}"
    sig = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    origin = f"{parsed.scheme}://{parsed.netloc}"
    return {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "application/json",
        "Origin": origin,
        "Referer": origin + "/",
        "x-ai-movie-timestamp": ts,
        "x-ai-movie-nonce": nonce,
        "x-ai-movie-signature": sig,
        "x-ai-movie-client-name": client,
    }


def _read_body(resp) -> bytes:
    try:
        return resp.read()
    except IncompleteRead as e:
        # Some CDN/WAF responses advertise a wrong Content-Length.
        return e.partial or b""


def request_json(
    method: str,
    url: str,
    secret: str,
    client: str,
    body: dict[str, Any] | None = None,
    retries: int = 3,
) -> tuple[int, Any]:
    data = None
    headers = sign_headers(method, url, secret, client)
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode()
        headers["Content-Type"] = "application/json"

    ctx = ssl.create_default_context()
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=ctx))
    last_err: Exception | None = None

    for attempt in range(1, retries + 1):
        headers = sign_headers(method, url, secret, client)
        if body is not None:
            headers["Content-Type"] = "application/json"
        req = Request(url, data=data, headers=headers, method=method)
        try:
            with opener.open(req, timeout=40) as resp:
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
                time.sleep(0.6 * attempt)
                continue
            raise RuntimeError(f"request failed after {retries} tries: {method} {url}: {e}") from e

    raise RuntimeError(f"request failed: {last_err}")


def ticket_from_line(line: dict[str, Any]) -> str | None:
    explicit = (line.get("resolve_ticket") or "").strip()
    if explicit:
        return explicit
    url = (line.get("url") or "").strip()
    if url.startswith("resolve://"):
        return url[len("resolve://") :].strip() or None
    if line.get("url_kind") == "resolve_ticket" and url:
        return url
    return None


def needs_resolve(line: dict[str, Any]) -> bool:
    if line.get("resolve_required") is True:
        return True
    if line.get("resolve_mode") == "parse":
        return True
    if line.get("url_kind") == "resolve_ticket":
        return True
    if line.get("resolved") is False and ticket_from_line(line):
        return True
    return False


def match_filter(line: dict[str, Any], only: set[str] | None) -> bool:
    if not only:
        return True
    fields = {
        (line.get("provider_id") or "").lower(),
        (line.get("play_from") or "").lower(),
        (line.get("provider_name") or "").lower(),
        (line.get("label") or "").lower(),
    }
    return any(f and (f in only or any(o in f for o in only)) for f in fields)


def main() -> int:
    ap = argparse.ArgumentParser(description="Resolve bpz5 playback tickets locally")
    ap.add_argument("token", help="episode token, e.g. YJ-a09cbb6e2204f84988b3")
    ap.add_argument("--base", default=DEFAULT_BASE, help=f"API origin (default {DEFAULT_BASE})")
    ap.add_argument("--secret", default=DEFAULT_SECRET, help="HMAC secret from frontend")
    ap.add_argument("--client", default=DEFAULT_CLIENT, help="x-ai-movie-client-name")
    ap.add_argument(
        "--only",
        default="",
        help="comma filter on provider_id/play_from/name (e.g. cloudflare,qq,4k)",
    )
    ap.add_argument(
        "--parse-only",
        action="store_true",
        help="only resolve parse/ticket lines (skip direct m3u8)",
    )
    ap.add_argument(
        "--tickets-only",
        action="store_true",
        help="only print resolve tickets, do not call resolve-line",
    )
    ap.add_argument("--json", action="store_true", help="print raw JSON results")
    ap.add_argument("--retries", type=int, default=3, help="HTTP retries on network errors")
    args = ap.parse_args()

    only = {x.strip().lower() for x in args.only.split(",") if x.strip()} or None
    base = args.base.rstrip("/")
    resolve_url = f"{base}/v1/playback/resolve/{args.token}"

    try:
        status, data = request_json("GET", resolve_url, args.secret, args.client, retries=args.retries)
    except Exception as e:
        print(f"resolve request error: {e}", file=sys.stderr)
        return 1

    if status != 200 or not isinstance(data, dict):
        print(f"resolve failed: HTTP {status}", file=sys.stderr)
        print(data, file=sys.stderr)
        return 1

    lines = data.get("line_options") or []
    print(f"object={data.get('object')} token={data.get('token')} lines={len(lines)}")
    ep = data.get("current_episode") or {}
    if ep:
        print(f"episode={ep.get('display_name')} next={ep.get('next_episode_token')}")

    results: list[dict[str, Any]] = []
    for line in lines:
        if not match_filter(line, only):
            continue
        if args.parse_only and not needs_resolve(line):
            continue

        provider = line.get("provider_id") or ""
        name = line.get("provider_name") or line.get("label") or ""
        play_from = line.get("play_from") or ""
        ticket = ticket_from_line(line)

        row: dict[str, Any] = {
            "provider_id": provider,
            "provider_name": name,
            "play_from": play_from,
            "url_kind": line.get("url_kind"),
            "resolved": line.get("resolved"),
            "preference_weight": line.get("preference_weight"),
            "price_multiplier_bps": line.get("price_multiplier_bps"),
        }

        if not needs_resolve(line):
            row["mode"] = "direct"
            row["url"] = line.get("url")
            results.append(row)
            continue

        row["mode"] = "parse"
        row["ticket"] = ticket
        if args.tickets_only or not ticket:
            if not ticket:
                row["error"] = "missing ticket"
            results.append(row)
            continue

        try:
            st2, resolved = request_json(
                "POST",
                f"{base}/v1/playback/resolve-line",
                args.secret,
                args.client,
                {"ticket": ticket},
                retries=args.retries,
            )
        except Exception as e:
            row["error"] = str(e)
            results.append(row)
            continue

        row["http_status"] = st2
        if st2 not in (200, 201) or not isinstance(resolved, dict):
            row["error"] = resolved
            results.append(row)
            continue

        out_line = resolved.get("line") or {}
        row["url"] = out_line.get("url")
        row["url_kind"] = out_line.get("url_kind")
        row["resolved"] = out_line.get("resolved")
        row["token_scenario"] = out_line.get("token_scenario")
        if resolved.get("quota_delta"):
            row["quota_delta"] = resolved["quota_delta"]
        results.append(row)

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return 0

    for row in results:
        head = (
            f"[{row.get('mode')}] {row.get('provider_name')} "
            f"({row.get('provider_id')} / {row.get('play_from')})"
        )
        print("\n" + head)
        if row.get("error"):
            print("  ERROR:", row["error"])
            continue
        if row.get("ticket") and args.tickets_only:
            t = row["ticket"]
            print("  ticket:", t[:80] + ("..." if len(t) > 80 else ""))
            continue
        print("  kind:", row.get("url_kind"), " resolved:", row.get("resolved"))
        print("  url:", row.get("url"))
        if row.get("price_multiplier_bps") is not None:
            print("  price_bps:", row["price_multiplier_bps"])

    if not only and not args.parse_only:
        parse_n = sum(1 for r in results if r.get("mode") == "parse")
        print(
            f"\n# tip: use --parse-only to only hit official/tencent tickets "
            f"({parse_n} parse lines above)"
        )

    if not results:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
