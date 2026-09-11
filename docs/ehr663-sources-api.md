# EHR663 测速源接口文档

本文描述 `demos/ehr663-vod/` 下由 EHR663 脚本抽取、测速后生成的 TVBox MacCMS 源配置及其背后的**真实远程接口**。

| 产物 | 路径 | 站点类型 |
| --- | --- | --- |
| MacCMS 采集源 | [`demos/ehr663-vod/maccms.json`](../demos/ehr663-vod/maccms.json) | `type: 1`，`api` = 采集基址 |

上游脚本仓库：[FGBLH/EHR663](https://github.com/FGBLH/EHR663)（本地克隆目录 `demos/EHR663/`，已在 `.gitignore`）。

相关文档：

- 苹果 CMS 采集协议（`type: 1` 共用）：[`docs/maccms-api.md`](maccms-api.md)
- 本仓库主站 `sources.json`（与本文 **不是** 同一份名单）：[`apps/api-go/config/sources.json`](../apps/api-go/config/sources.json)
- MultiLiveTV Go HTTP API：[`docs/02-api.md`](02-api.md)

**范围声明（严格）：**

- 本文 **不是** `apps/api-go` 的 REST 文档。
- `maccms.json` **未**写入主站 `sources.json`，主 App 默认不读该文件。
- `ttfb_ms` / 站名序号来自本地测速快照，网络变化后需重跑脚本；**以当前 JSON 文件为准**。
- 仅收录脚本中可抽出的 `provide/vod` / `api_mac` 等采集接口；网页爬虫站（无 MacCMS API）不在本文范围。

---

## 1. 约定

| 项 | 说明 |
| --- | --- |
| 配置格式 | TVBox / OK 影视类 JSON：`sites` + `parses` + `flags` |
| MacCMS 协议 | HTTP(S) `GET`，查询参数见 [`maccms-api.md`](maccms-api.md) |
| 鉴权 | 采集站公开，无需 Token |
| User-Agent | 测速与请求建议浏览器 UA |
| 测速默认阈值 | 成功且 TTFB ≤ 2000 ms（可用 `--max-ms` 修改） |

生成命令：

```bash
cd demos/ehr663-vod
python3 latency_maccms.py --max-ms 2000
```

---

## 2. TVBox 配置字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `spider` | string | 本文产物为空字符串 |
| `sites` | array | 源列表，已按 `ttfb_ms` 升序，站名带 `01.` 序号 |
| `parses` | array | 解析站（WebView / 官方页兜底） |
| `flags` | array | 需走解析的播放标识（腾讯 / 优酷等） |
| `ads` | array | 空数组 |

### 2.1 `sites[]`（`type: 1`）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `key` | string | 稳定键，如 `maccms_lziapi` |
| `name` | string | 展示名，前缀序号表示延迟名次 |
| `type` | number | 固定 `1` |
| `api` | string | **采集基址**（真实 `provide/vod` 或带 `from`/`at` 的变体），不是 `.py` |
| `searchable` | number | `1` |
| `quickSearch` | number | `1` |
| `filterable` | number | `1` |
| `changeable` | number | `1` |
| `index` | number | 排序名次，从 1 起 |
| `ttfb_ms` | number | 最近一次 `?ac=list&pg=1` 测速 TTFB（毫秒） |

### 2.2 `parses[]`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `name` | string | 如 `01.解析cc` |
| `type` | number | `0`（URL 拼接解析） |
| `url` | string | 前缀，官方页拼在 `url=` 后 |
| `ext.flag` | array | 适用的 `flags` 列表 |

当前保留（高延迟的 `jx.xmflv.com` 已删除）：

| name | url |
| --- | --- |
| 解析cc | `https://jx.xmflv.cc/?url=` |
| 解析m3u8 | `https://jx.m3u8.tv/jiexi/?url=` |

---

## 3. MacCMS 源接口（`maccms.json`）

### 3.1 协议

与 [`maccms-api.md`](maccms-api.md) **完全相同**：

| `ac` | 用途 | 播放地址 |
| --- | --- | --- |
| `list` | 分类 + 摘要列表 / 搜索 | 无 |
| `detail` | 详情（建议带 `ids`） | 有 `vod_play_url` |
| `videolist` | 带播放地址的分页列表 | 有 |

列表测速探针（生成本 JSON 时使用）：

```http
GET {api}?ac=list&pg=1
```

成功判定：HTTP &lt; 400，正文可解析为 JSON，且含 `list`（或等价成功形态）；详见 `demos/ehr663-vod/maccms_extract.py` 的 `probe_is_success`。

示例（电影天堂，基址以 `maccms.json` 当前条目为准）：

```bash
curl -sS -A 'Mozilla/5.0' \
  'http://caiji.dyttzyapi.com/api.php/provide/vod/from/dyttm3u8/at/json?ac=list&pg=1'
```

```bash
curl -sS -A 'Mozilla/5.0' \
  'https://cj.rycjapi.com/api.php/provide/vod/?ac=detail&ids=1'
```

响应字段表见 [`maccms-api.md` §4](maccms-api.md)。本文不重复字段定义。

### 3.2 抽取规则

从 `demos/EHR663/py/*.py` 扫描：

1. `.../api.php/provide/vod...`
2. `.../provide/vod...`
3. `.../inc/api_mac*.php`、`.../inc/api.php`
4. 脚本内 `'api': 'http...'` / `HOT_API` / 元组名值对

去重后测速；失败或 TTFB &gt; `--max-ms`（默认 2000）不写入 `maccms.json`。

### 3.3 当前已收录基址

以下为生成 `maccms.json` 时的快照。**`ttfb_ms` 会变**；导入以文件为准。

| index | name | api | ttfb_ms |
| ---: | --- | --- | ---: |
| 1 | 01.电影天堂 | `http://caiji.dyttzyapi.com/api.php/provide/vod/from/dyttm3u8/at/json` | 384.5 |
| 2 | 02.如意影视 | `https://cj.rycjapi.com/api.php/provide/vod/` | 428.6 |
| 3 | 03.最大 | `https://api.zuidapi.com/api.php/provide/vod/` | 680.9 |
| 4 | 04.无尽 | `https://api.wujinapi.cc/api.php/provide/vod/` | 706.1 |
| 5 | 05.索尼 | `https://suoniapi.com/api.php/provide/vod/` | 727.9 |
| 6 | 06.樱花 | `https://m3u8.apiyhzy.com/api.php/provide/vod/` | 780.1 |
| 7 | 07.虎牙 | `https://www.huyaapi.com/api.php/provide/vod/` | 788.4 |
| 8 | 08.索尼闪电 | `https://xsd.sdzyapi.com/api.php/provide/vod/` | 798.6 |
| 9 | 09.飘零 | `https://p2100.net/api.php/provide/vod/` | 822.0 |
| 10 | 10.量子 | `https://cj.lziapi.com/api.php/provide/vod/` | 839.5 |
| 11 | 11.牛牛 | `https://api.niuniuzy.me/api.php/provide/vod/` | 895.7 |
| 12 | 12.大众资源 | `https://cdn.dzzyapi.com/api.php/provide/vod/` | 899.3 |
| 13 | 13.无水印 | `https://api.wsyzy.net/api.php/provide/vod/` | 933.9 |
| 14 | 14.百度云 | `https://api.apibdzy.com/api.php/provide/vod/` | 934.7 |
| 15 | 15.闪电 | `https://sdzyapi.com/api.php/provide/vod/` | 961.9 |
| 16 | 16.光速 | `https://api.guangsuapi.com/api.php/provide/vod/` | 1015.6 |
| 17 | 17.暴风 | `https://bfzyapi.com/api.php/provide/vod/` | 1028.0 |
| 18 | 18.速播 | `https://subocaiji.com/api.php/provide/vod/` | 1028.1 |
| 19 | 19.极速 | `https://jszyapi.com/api.php/provide/vod/from/jsm3u8/` | 1041.8 |
| 20 | 20.魔都 | `https://www.mdzyapi.com/api.php/provide/vod/` | 1070.1 |
| 21 | 21.豆瓣2 | `https://dbzy.tv/api.php/provide/vod/` | 1121.1 |
| 22 | 22.火狐影视 | `https://hhzyapi.com/api.php/provide/vod/` | 1142.3 |
| 23 | 23.xoxowin86cisyap | `https://bf.xoxowin86cisyap.com/api.php/provide/vod/` | 1257.0 |
| 24 | 24.155资源 | `https://155api.com/api.php/provide/vod/` | 1313.8 |
| 25 | 25.金鹰 | `https://jinyingzy.com/api.php/provide/vod/` | 1599.2 |
| 26 | 26.qzz | `https://tianwei.qzz.io/api.php/provide/vod/` | 1638.4 |
| 27 | 27.10010888 | `https://cj.10010888.xyz/api.php/provide/vod/` | 1899.3 |

最近一次测速中未收录（失败或超时）的示例：`98zy.vip`、`api.1080zyku.com/inc/api_mac10.php`、`ikuapi` / `ikunzyapi`、`mozhuazy.com`、`collect.wolongzyw.com`（body 不合格）、`api.wwzy.tv` 等。完整名单以 `python3 latency_maccms.py` 终端输出为准。

---

## 4. 解析站（`parses`）

用于官方站点页（腾讯 / 优酷 / 爱奇艺 / 芒果等）无法直链时的 WebView / 拼接解析。

```text
{parse.url}{urlencoded_official_page}
```

示例：

```text
https://jx.xmflv.cc/?url=https%3A%2F%2Fv.qq.com%2Fx%2Fcover%2F...
```

`flags` 当前为：`qq`、`腾讯`、`腾讯视频`、`qiyi`、`爱奇艺`、`youku`、`优酷`、`mgtv`、`芒果`、`芒果TV`。

---

## 5. 与主工程的关系

| 项 | 主站 `sources.json` | 本文 `maccms.json` |
| --- | --- | --- |
| 用途 | Go / Apple / Web 聚合运行时配置 | EHR663 测速 demo / TVBox 导入实验 |
| MacCMS | 有，字段为 `url` | 有，字段为 `api` |
| 延迟字段 | 无 `ttfb_ms` | 有 |
| 自动生成 | 否 | `latency_maccms.py` |

把 `maccms.json` 中某条 `api` 迁入主站时：按 [`maccms-api.md`](maccms-api.md) 与现有 `sources.json` 条目格式增加 `id` / `name` / `url` / `jx_url`，**不要**照搬 TVBox 的 `type`/`key` 字段。

---

## 6. 本地脚本索引

| 脚本 | 作用 |
| --- | --- |
| `latency_maccms.py` | 抽 MacCMS API → 测速 → 写 `maccms.json` |
| `maccms_extract.py` | 抽取与成功判定 |
| `maccms_source.py` | 排序与 type=1 JSON |
| `probe.py` | 通用 TTFB 探测辅助 |

单元测试：`test_maccms_extract.py`、`test_maccms_source.py`。

```bash
cd demos/ehr663-vod
python3 test_maccms_extract.py
python3 test_maccms_source.py
```
