#!/usr/bin/env python3
"""Scan EHR663 py scripts for MacCMS APIs, probe latency, write maccms.json.

Examples:
  python3 latency_maccms.py
  python3 latency_maccms.py --max-ms 1500
  python3 latency_maccms.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

from maccms_extract import (  # noqa: E402
    api_kind,
    extract_apis_from_dir,
    list_probe_url,
    probe_is_success,
)
from maccms_source import filter_api_rows, write_maccms_tvbox  # noqa: E402
from probe import UA  # noqa: E402

ROOT = Path(__file__).resolve().parent
EHR_PY = ROOT.parent / "EHR663" / "py"
EHR_REPO = "https://github.com/FGBLH/EHR663.git"


def ensure_ehr663() -> None:
    if (EHR_PY / "采集聚合.py").exists():
        return
    import subprocess

    EHR_PY.parent.parent.mkdir(parents=True, exist_ok=True)
    target = EHR_PY.parent
    if target.exists() and not (EHR_PY / "采集聚合.py").exists():
        raise RuntimeError(f"EHR663 incomplete: {target}")
    print(f"Cloning EHR663 into {target} ...", file=sys.stderr)
    subprocess.check_call(["git", "clone", "--depth", "1", EHR_REPO, str(target)])


def probe_api(row: dict[str, str], timeout: float) -> dict[str, Any]:
    api = row["api"]
    kind = row.get("kind") or api_kind(api)
    url = list_probe_url(api)
    out: dict[str, Any] = {
        "name": row.get("name") or "",
        "api": api,
        "kind": kind,
        "source_file": row.get("source_file") or "",
        "probe_url": url,
        "ok": False,
        "http": None,
        "ttfb_ms": None,
        "items": 0,
        "error": "",
    }
    t0 = time.perf_counter()
    try:
        rsp = requests.get(
            url,
            headers={"User-Agent": UA, "Accept": "application/json, text/plain, */*"},
            timeout=timeout,
            verify=False,
        )
        body = rsp.text or ""
        out["ttfb_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        out["http"] = rsp.status_code
        out["ok"] = probe_is_success(rsp.status_code, body, kind)
        if out["ok"]:
            try:
                data = rsp.json()
                lst = data.get("list") if isinstance(data, dict) else None
                if isinstance(lst, list):
                    out["items"] = len(lst)
            except Exception:  # noqa: BLE001
                out["items"] = body.count("<vod>") or body.count("<video>")
        elif rsp.status_code >= 400:
            out["error"] = f"HTTP {rsp.status_code}"
        else:
            out["error"] = "bad body"
    except Exception as exc:  # noqa: BLE001
        out["ttfb_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        out["error"] = str(exc)
    return out


def format_table(rows: list[dict[str, Any]]) -> str:
    lines = ["rank  ttfb     ok   http  items  name            api"]
    for i, row in enumerate(rows, 1):
        name = (row.get("name") or "")[:12]
        api = row.get("api") or ""
        if len(api) > 64:
            api = api[:64] + "…"
        lines.append(
            f"{i:<5} {row.get('ttfb_ms') if row.get('ttfb_ms') is not None else '-':<8} "
            f"{'yes' if row.get('ok') else 'no':<4} "
            f"{row.get('http') if row.get('http') is not None else '-':<5} "
            f"{row.get('items') or 0:<6} "
            f"{name:<14} {api}"
        )
        if row.get("error"):
            lines.append(f"      error: {row['error']}")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Probe MacCMS APIs extracted from EHR663 py scripts")
    ap.add_argument("--py-dir", default=str(EHR_PY), help="path to EHR663/py")
    ap.add_argument("--max-ms", type=float, default=2000, help="drop APIs slower than this TTFB")
    ap.add_argument("--timeout", type=float, default=8.0, help="HTTP timeout seconds")
    ap.add_argument("--workers", type=int, default=12, help="probe concurrency")
    ap.add_argument("--out", default=str(ROOT / "maccms.json"), help="output TVBox JSON")
    ap.add_argument("--json", action="store_true", help="print full JSON report")
    ap.add_argument("--keep-failed", action="store_true", help="do not write filtered file; report only")
    args = ap.parse_args()

    ensure_ehr663()
    py_dir = Path(args.py_dir)
    if not py_dir.is_dir():
        print(f"missing py dir: {py_dir}", file=sys.stderr)
        return 2

    catalog = extract_apis_from_dir(py_dir)
    print(f"# extracted {len(catalog)} unique APIs from {py_dir}", file=sys.stderr)
    if not catalog:
        return 2

    rows: list[dict[str, Any]] = []
    workers = max(1, args.workers)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = [pool.submit(probe_api, row, args.timeout) for row in catalog]
        for fut in as_completed(futs):
            rows.append(fut.result())

    rows.sort(key=lambda r: (0 if r.get("ok") else 1, r.get("ttfb_ms") if r.get("ttfb_ms") is not None else 1e12))
    kept = filter_api_rows(rows, max_ttfb_ms=args.max_ms)

    if not args.keep_failed:
        out = write_maccms_tvbox(kept, Path(args.out))
        print(f"# wrote {len(kept)} sites -> {out}", file=sys.stderr)

    if args.json:
        print(
            json.dumps(
                {"extracted": len(catalog), "kept": kept, "all": rows, "max_ms": args.max_ms},
                ensure_ascii=False,
                indent=2,
            )
        )
    else:
        print(format_table(rows))
        print(f"\n# kept {len(kept)}/{len(rows)} under {args.max_ms}ms")
        if kept:
            best = kept[0]
            print(f"# fastest: {best.get('name')} {best.get('ttfb_ms')}ms {best.get('api')}")
    return 0 if kept else 2


if __name__ == "__main__":
    raise SystemExit(main())
