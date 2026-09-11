import json
import unittest

from source import (
    FAST_PARSER_PREFIXES,
    build_tvbox_source,
    filter_parser_prefixes,
    parser_prefix,
)


class SourceScriptTests(unittest.TestCase):
    def test_fast_parsers_drop_high_latency_xmflv_com(self):
        blob = " ".join(FAST_PARSER_PREFIXES)
        self.assertNotIn("xmflv.com", blob)
        self.assertIn("xmflv.cc", blob)
        self.assertIn("m3u8.tv", blob)
        for dead in ("playerjy", "2s0", "kptv", "daga"):
            self.assertNotIn(dead, blob)

    def test_parser_prefix_keeps_jiexi_path(self):
        raw = "https://jx.m3u8.tv/jiexi/?url=https%3A%2F%2Fv.qq.com%2Fa.html"
        self.assertEqual(parser_prefix(raw), "https://jx.m3u8.tv/jiexi/?url=")

    def test_filter_parser_prefixes_drops_timeout_and_slow(self):
        rows = [
            {"role": "official", "url": "https://v.qq.com/x.html", "ok": True, "ttfb_ms": 120},
            {"role": "parser", "url": "https://jx.xmflv.cc/?url=https://v.qq.com/x.html", "ok": True, "ttfb_ms": 800},
            {"role": "parser", "url": "https://jx.m3u8.tv/jiexi/?url=https://v.qq.com/x.html", "ok": True, "ttfb_ms": 500},
            {"role": "parser", "url": "https://jx.xmflv.com/?url=https://v.qq.com/x.html", "ok": False, "ttfb_ms": 9231},
            {"role": "parser", "url": "https://jx.slow.example/?url=https://v.qq.com/x.html", "ok": True, "ttfb_ms": 3100},
        ]
        kept = filter_parser_prefixes(rows, max_ttfb_ms=2000)
        blob = " ".join(kept)
        self.assertEqual(kept[0], "https://jx.m3u8.tv/jiexi/?url=")
        self.assertIn("xmflv.cc", blob)
        self.assertNotIn("xmflv.com", blob)
        self.assertNotIn("slow.example", blob)

    def test_tvbox_source_puts_official_sites_first_without_slow_parses(self):
        cfg = build_tvbox_source()
        names = [s["name"] for s in cfg["sites"]]
        self.assertEqual(names[:4], ["腾讯视频", "优酷", "爱奇艺", "芒果TV"])
        for site in cfg["sites"][:4]:
            self.assertEqual(site["type"], 3)
            api = str(site["api"])
            self.assertTrue(api.startswith("https://raw.githubusercontent.com/FGBLH/EHR663/"))
            self.assertNotIn("ghfast.top", api)
            self.assertIn(".py", api)
        parse_blob = json.dumps(cfg["parses"], ensure_ascii=False)
        self.assertNotIn("xmflv.com", parse_blob)
        self.assertIn("xmflv.cc", parse_blob)
        self.assertIn("m3u8.tv", parse_blob)
        self.assertIn("qq", cfg["flags"])
        self.assertIn("腾讯", cfg["flags"])


if __name__ == "__main__":
    unittest.main()
