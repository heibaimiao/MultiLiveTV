import unittest

from maccms_source import build_maccms_tvbox, filter_api_rows, key_for_api, sort_rows_by_latency


class MaccmsSourceTests(unittest.TestCase):
    def test_filter_drops_failed_and_slow(self):
        rows = [
            {"name": "快", "api": "https://a.com/api.php/provide/vod/", "ok": True, "ttfb_ms": 200},
            {"name": "慢", "api": "https://b.com/api.php/provide/vod/", "ok": True, "ttfb_ms": 3500},
            {"name": "挂", "api": "https://c.com/api.php/provide/vod/", "ok": False, "ttfb_ms": 100},
        ]
        kept = filter_api_rows(rows, max_ttfb_ms=2000)
        self.assertEqual([r["name"] for r in kept], ["快"])

    def test_sort_rows_by_latency_ascending(self):
        rows = [
            {"name": "慢", "api": "https://b.com/api.php/provide/vod/", "ok": True, "ttfb_ms": 900},
            {"name": "快", "api": "https://a.com/api.php/provide/vod/", "ok": True, "ttfb_ms": 120},
            {"name": "中", "api": "https://c.com/api.php/provide/vod/", "ok": True, "ttfb_ms": 400},
        ]
        ordered = sort_rows_by_latency(rows)
        self.assertEqual([r["name"] for r in ordered], ["快", "中", "慢"])

    def test_build_sites_sorted_and_ranked_by_latency(self):
        cfg = build_maccms_tvbox(
            [
                {"name": "慢站", "api": "https://slow.example/api.php/provide/vod/", "ttfb_ms": 800, "ok": True},
                {"name": "快站", "api": "https://fast.example/api.php/provide/vod/", "ttfb_ms": 100, "ok": True},
            ]
        )
        self.assertEqual([s["name"] for s in cfg["sites"]], ["01.快站", "02.慢站"])
        self.assertEqual(cfg["sites"][0]["api"], "https://fast.example/api.php/provide/vod/")
        self.assertEqual(cfg["sites"][0]["index"], 1)
        self.assertEqual(cfg["sites"][1]["index"], 2)

    def test_build_sites_are_type1_with_real_api(self):
        cfg = build_maccms_tvbox(
            [
                {"name": "量子", "api": "https://cj.lziapi.com/api.php/provide/vod/", "ttfb_ms": 120, "ok": True},
                {"name": "1080", "api": "https://api.1080zyku.com/inc/api_mac10.php", "ttfb_ms": 300, "ok": True},
            ]
        )
        self.assertEqual(len(cfg["sites"]), 2)
        self.assertEqual(cfg["sites"][0]["type"], 1)
        self.assertEqual(cfg["sites"][0]["api"], "https://cj.lziapi.com/api.php/provide/vod/")
        self.assertNotIn(".py", cfg["sites"][0]["api"])
        self.assertTrue(cfg["sites"][0]["key"].startswith("maccms_"))
        blob = str(cfg["parses"])
        self.assertIn("xmflv.cc", blob)
        self.assertNotIn("xmflv.com", blob)

    def test_key_for_api_stable(self):
        self.assertEqual(key_for_api("https://cj.lziapi.com/api.php/provide/vod/"), "maccms_lziapi")


if __name__ == "__main__":
    unittest.main()
