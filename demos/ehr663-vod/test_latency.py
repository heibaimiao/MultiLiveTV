import unittest

from probe import OFFICIAL_KEYS, build_probe_targets, rank_rows, source_order


class LatencyProbeTests(unittest.TestCase):
    def test_default_source_order_puts_official_first(self):
        keys = source_order(["mifun", "qq", "dmla", "mgtv", "youku", "qiyi"])
        self.assertEqual(keys[:4], ["qq", "youku", "qiyi", "mgtv"])
        self.assertEqual(set(keys[4:]), {"mifun", "dmla"})

    def test_official_only_drops_unofficial_sources(self):
        keys = source_order(["qq", "mifun", "youku"], official_only=True)
        self.assertEqual(keys, ["qq", "youku"])

    def test_probe_targets_put_official_page_before_parsers(self):
        targets = build_probe_targets(
            {
                "mode": "parse",
                "url": "https://jx.xmflv.com/?url=https://v.qq.com/x/cover/a/b.html",
                "official": "https://v.qq.com/x/cover/a/b.html",
                "parse_urls": [
                    "https://jx.xmflv.com/?url=https%3A%2F%2Fv.qq.com%2Fx%2Fcover%2Fa%2Fb.html",
                    "https://jx.m3u8.tv/jiexi/?url=https%3A%2F%2Fv.qq.com%2Fx%2Fcover%2Fa%2Fb.html",
                ],
            }
        )
        roles = [t["role"] for t in targets]
        self.assertEqual(roles[0], "official")
        self.assertEqual(targets[0]["url"], "https://v.qq.com/x/cover/a/b.html")
        self.assertIn("parser", roles)
        self.assertLess(roles.index("official"), roles.index("parser"))

    def test_direct_media_is_probed_before_wrappers(self):
        targets = build_probe_targets(
            {
                "mode": "video",
                "url": "https://cdn.example.com/a.m3u8",
                "official": "https://v.qq.com/x/cover/a/b.html",
                "parse_urls": ["https://jx.xmflv.com/?url=https%3A%2F%2Fv.qq.com%2Fx%2Fcover%2Fa%2Fb.html"],
            }
        )
        self.assertEqual(targets[0]["role"], "direct")
        self.assertEqual(targets[0]["url"], "https://cdn.example.com/a.m3u8")

    def test_rank_rows_keeps_official_ahead_even_if_slower(self):
        ranked = rank_rows(
            [
                {"source": "mifun", "ok": True, "ttfb_ms": 40, "role": "direct"},
                {"source": "qq", "ok": True, "ttfb_ms": 400, "role": "official"},
            ]
        )
        self.assertEqual(ranked[0]["source"], "qq")
        self.assertEqual(ranked[1]["source"], "mifun")

    def test_rank_rows_within_official_sorts_ok_then_ttfb(self):
        ranked = rank_rows(
            [
                {"source": "youku", "ok": True, "ttfb_ms": 300, "role": "official"},
                {"source": "qq", "ok": False, "ttfb_ms": 10, "role": "official"},
                {"source": "mgtv", "ok": True, "ttfb_ms": 120, "role": "official"},
            ]
        )
        self.assertEqual([r["source"] for r in ranked], ["mgtv", "youku", "qq"])

    def test_official_keys_match_demo_platforms(self):
        self.assertEqual(OFFICIAL_KEYS, ("qq", "youku", "qiyi", "mgtv"))


if __name__ == "__main__":
    unittest.main()
