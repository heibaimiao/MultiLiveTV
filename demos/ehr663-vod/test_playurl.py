import unittest

from playurl import classify_play, unwrap_jiexi


class PlayUrlTests(unittest.TestCase):
    def test_unwrap_tencent_jiexi_to_official(self):
        raw = "https://jx.xmflv.com/?url=https://v.qq.com/x/cover/mzc00200abc/x001.html"
        self.assertEqual(unwrap_jiexi(raw), "https://v.qq.com/x/cover/mzc00200abc/x001.html")

    def test_tencent_jiexi_stays_parse_webview(self):
        result = classify_play(
            {
                "parse": 1,
                "url": "https://jx.xmflv.com/?url=https://v.qq.com/x/cover/mzc00200abc/x001.html",
                "header": "",
            }
        )
        self.assertEqual(result["mode"], "parse")
        self.assertIn("jx.xmflv.com", result["url"])
        self.assertIn("v.qq.com", result["official"])

    def test_youku_jx_flag_needs_parser(self):
        result = classify_play(
            {"jx": 1, "parse": 1, "url": "https://v.youku.com/video?vid=XNTI", "header": ""}
        )
        self.assertEqual(result["mode"], "need_parse")
        self.assertIn("youku.com", result["url"])

    def test_mgtv_official_needs_parser(self):
        result = classify_play(
            {"jx": 1, "parse": 1, "url": "https://www.mgtv.com/b/123/456.html", "header": ""}
        )
        self.assertEqual(result["mode"], "need_parse")

    def test_direct_m3u8_uses_video(self):
        result = classify_play({"parse": 0, "url": "https://cdn.example.com/a.m3u8", "header": {}})
        self.assertEqual(result["mode"], "video")

    def test_jiexi_wrapper_is_parse_not_video(self):
        result = classify_play(
            {"parse": 0, "url": "https://jx.kptv.us/?url=https://www.iqiyi.com/v_abc.html"}
        )
        self.assertEqual(result["mode"], "parse")
        self.assertIn("kptv", result["url"])

    def test_official_page_input_is_not_media(self):
        from playurl import is_direct_media, is_official_page

        url = "https://v.qq.com/x/cover/rjae621myqca41h/i0032qxbi2v.html"
        self.assertTrue(is_official_page(url))
        self.assertFalse(is_direct_media(url))

    def test_working_parsers_exclude_failed(self):
        from app import WORKING_PARSER_PREFIXES

        blob = " ".join(WORKING_PARSER_PREFIXES)
        self.assertNotIn("jx.xmflv.com", blob)
        self.assertIn("jx.xmflv.cc", blob)
        self.assertIn("jx.m3u8.tv", blob)
        for dead in ("playerjy", "2s0", "kptv", "daga"):
            self.assertNotIn(dead, blob)
        from playurl import wrap_parser

        wrapped = wrap_parser("https://jx.xmflv.cc/?url=", "https://v.youku.com/video?vid=XNTI")
        self.assertIn("url=https%3A%2F%2Fv.youku.com%2Fvideo%3Fvid%3DXNTI", wrapped)
        self.assertEqual(wrapped.count("?"), 1)

    def test_png_bytes_are_not_av(self):
        from playurl import is_av_payload

        self.assertFalse(is_av_payload(b"\x89PNG\r\n\x1a\n\x00\x00"))
        self.assertTrue(is_av_payload(b"\x47" + b"\x00" * 15))
        self.assertTrue(is_av_payload(b"#EXTM3U\n#EXT-X-STREAM-INF\n"))

    def test_parse_episodes_caps_long_lists(self):
        from app import parse_episodes

        vod = {
            "vod_play_from": "芒果TV",
            "vod_play_url": "#".join(f"第{i:03d}集$/b/{i}.html" for i in range(1, 201)),
        }
        groups = parse_episodes(vod)
        self.assertEqual(len(groups[0]["episodes"]), 80)


if __name__ == "__main__":
    unittest.main()
