import unittest

from maccms_extract import (
    extract_apis_from_text,
    normalize_api_url,
    probe_is_success,
)


class MaccmsExtractTests(unittest.TestCase):
    def test_extracts_named_provide_vod(self):
        text = """
        sources = {
            's1': {'name': '量子', 'api': 'https://cj.lziapi.com/api.php/provide/vod'},
            's2': {'name': '1080', 'api': 'https://api.1080zyku.com/inc/api_mac10.php'},
        }
        """
        rows = extract_apis_from_text(text, source_file="采集聚合.py")
        urls = {r["api"] for r in rows}
        self.assertIn("https://cj.lziapi.com/api.php/provide/vod/", urls)
        self.assertIn("https://api.1080zyku.com/inc/api_mac10.php", urls)
        names = {r["api"]: r["name"] for r in rows}
        self.assertEqual(names["https://cj.lziapi.com/api.php/provide/vod/"], "量子")

    def test_extracts_bare_provide_and_constants(self):
        text = """
        HOT_API = "https://cj.10010888.xyz/api.php/provide/vod/"
        main_api = "https://tianwei.qzz.io/api.php/provide/vod/"
        ("极速", "https://jszyapi.com/api.php/provide/vod/from/jsm3u8/")
        """
        rows = extract_apis_from_text(text, source_file="x.py")
        urls = {r["api"] for r in rows}
        self.assertIn("https://cj.10010888.xyz/api.php/provide/vod/", urls)
        self.assertIn("https://tianwei.qzz.io/api.php/provide/vod/", urls)
        self.assertIn("https://jszyapi.com/api.php/provide/vod/from/jsm3u8/", urls)

    def test_normalize_api_url_adds_trailing_slash_for_provide(self):
        self.assertEqual(
            normalize_api_url("https://cj.lziapi.com/api.php/provide/vod"),
            "https://cj.lziapi.com/api.php/provide/vod/",
        )
        self.assertEqual(
            normalize_api_url("https://api.1080zyku.com/inc/api_mac10.php"),
            "https://api.1080zyku.com/inc/api_mac10.php",
        )

    def test_probe_success_for_json_list(self):
        self.assertTrue(probe_is_success(200, '{"code":1,"list":[{"vod_id":1}]}', "provide"))
        self.assertFalse(probe_is_success(200, '{"code":0,"msg":"err"}', "provide"))
        self.assertFalse(probe_is_success(500, "{}", "provide"))

    def test_probe_success_for_mac_xml_or_json(self):
        self.assertTrue(probe_is_success(200, '<?xml version="1.0"?><rss><list page="1"', "mac"))
        self.assertTrue(probe_is_success(200, '{"list":[]}', "mac"))
        self.assertFalse(probe_is_success(200, "<html>not api</html>", "mac"))

    def test_dir_merge_prefers_human_name(self):
        from pathlib import Path
        import tempfile

        from maccms_extract import extract_apis_from_dir

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "a.py").write_text(
                "https://cj.lziapi.com/api.php/provide/vod/\n",
                encoding="utf-8",
            )
            (root / "b.py").write_text(
                "{'name': '量子', 'api': 'https://cj.lziapi.com/api.php/provide/vod'}\n",
                encoding="utf-8",
            )
            rows = extract_apis_from_dir(root)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["name"], "量子")


if __name__ == "__main__":
    unittest.main()
