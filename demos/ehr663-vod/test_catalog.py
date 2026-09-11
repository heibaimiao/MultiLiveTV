import unittest

from catalog import classes_from_home


class CatalogTests(unittest.TestCase):
    def test_tencent_keeps_script_class_ids(self):
        home = {
            "class": [
                {"type_name": "电视剧", "type_id": "100113"},
                {"type_name": "电影", "type_id": "100173"},
            ]
        }
        got = classes_from_home("qq", home)
        self.assertEqual(
            got,
            [
                {"id": "100113", "type_id": "100113", "type_name": "电视剧", "extend": {}},
                {"id": "100173", "type_id": "100173", "type_name": "电影", "extend": {}},
            ],
        )

    def test_qiyi_uses_genre_filter_not_platform_tabs(self):
        home = {
            "class": [
                {"type_id": "1", "type_name": "腾讯视频"},
                {"type_id": "2", "type_name": "爱奇艺"},
            ],
            "filters": {
                "2": [
                    {
                        "key": "class",
                        "name": "类型",
                        "value": [
                            {"n": "全部", "v": ""},
                            {"n": "电视剧", "v": "2"},
                            {"n": "电影", "v": "1"},
                        ],
                    }
                ]
            },
        }
        got = classes_from_home("qiyi", home)
        self.assertEqual(
            [c["type_name"] for c in got],
            ["电视剧", "电影"],
        )
        self.assertEqual(got[1]["type_id"], "2")
        self.assertEqual(got[1]["extend"], {"class": "1"})
        self.assertNotEqual(got[0]["id"], got[1]["id"])

    def test_youku_class_id_is_category_name(self):
        home = {"class": [{"type_name": "动漫", "type_id": "动漫"}]}
        got = classes_from_home("youku", home)
        self.assertEqual(got[0]["type_id"], "动漫")
        self.assertEqual(got[0]["id"], "动漫")

    def test_strips_html_in_class_name(self):
        home = {"class": [{"type_name": "<b>连载中</b>", "type_id": "manhua/list/lianzai"}]}
        got = classes_from_home("dmla", home)
        self.assertEqual(got[0]["type_name"], "连载中")


if __name__ == "__main__":
    unittest.main()
