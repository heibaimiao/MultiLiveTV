# MacCMS 资源站采集接口文档

本文描述本仓库 `sources.json` 中全部资源站使用的苹果 CMS V10（MacCMS）开放采集协议。各站没有独立 REST 规范，请求路径、查询参数、JSON 字段均相同，差异只在基址、`vod_play_from` 标识和个别路径拼写。

官方说明：

- [入库接口说明 · magicblack/maccms10 Wiki](https://github.com/magicblack/maccms10/wiki/%E5%85%A5%E5%BA%93%E6%8E%A5%E5%8F%A3%E8%AF%B4%E6%98%8E)
- [采集接口 · maccms.plus](https://www.maccms.plus/api/collect.html)
- 源码：[Provide.php](https://github.com/magicblack/maccms10/blob/master/application/api/controller/Provide.php)

配置文件：[`apps/api-go/config/sources.json`](../apps/api-go/config/sources.json)（与 `web/config/sources.json`、`clients/apple/MultiLiveTV/Resources/sources.json` 同步）。

若需要搜剧 AI（bpz5）上的「官方高清 / 4K / 腾讯」等非 MacCMS 线路，见另文 [`souju-playback-api.md`](souju-playback-api.md)。

由 EHR663 脚本测速生成的 TVBox `maccms.json`，见 [`ehr663-sources-api.md`](ehr663-sources-api.md)（**不是**主站 `sources.json`）。

---

## 1. 约定

| 项 | 说明 |
| --- | --- |
| 协议 | HTTP / HTTPS，`GET` |
| Content-Type | 响应多为 `text/html; charset=utf-8` 或 `application/json`，正文仍是 JSON |
| 编码 | UTF-8；部分站带 BOM，解析前应去掉 |
| User-Agent | 建议浏览器 UA。空 UA 或部分站会 403 / 空包 |
| 超时 | 本仓库客户端 15 秒 |
| 基址 | `sources.json` 的 `url`。无尾斜杠时客户端会补 `/`，再拼查询参数 |
| 鉴权 | 公开采集，无需 Token |

基址形态通常为：

```text
https://{host}/api.php/provide/vod/
```

把查询参数接在后面，例如：

```text
https://www.hongniuzy2.com/api.php/provide/vod/?ac=list&pg=1
```

路径里也可以写死格式或播放线（与查询参数等价，部分站两种都认）：

```text
/api.php/provide/vod/at/json/
/api.php/provide/vod/from/hnm3u8/
/api.php/provide/vod/from/hnm3u8/at/xml/
```

---

## 2. 查询参数

| 参数 | 必填 | 取值 | 说明 |
| --- | --- | --- | --- |
| `ac` | 否 | `list` / `detail` / `videolist` | 默认 `list`。`list` 只有摘要，**没有** `vod_play_url`。要播放地址用 `detail` 或 `videolist` |
| `pg` | 否 | 正整数 | 页码，默认 `1` |
| `t` | 否 | 分类 ID | 对应响应 `class[].type_id` |
| `wd` | 否 | 关键词 | 按片名模糊搜索 |
| `h` | 否 | 小时数 | 最近 N 小时内更新，例如 `h=24` |
| `ids` | `ac=detail` 时建议 | `123` 或 `123,456` | 影片 ID，半角逗号分隔 |
| `pagesize` / `limit` | 否 | 通常 ≤ 100 | 部分站支持，本仓库未传 |
| `at` | 否 | `json` / `xml` / `josn` | 输出格式。个别站把 JSON 拼成 `josn` |
| `from` | 否 | 如 `hnm3u8` | 只返回指定播放线 |

`ac` 行为对照：

| `ac` | `class` 分类 | 列表字段 | `vod_play_url` |
| --- | --- | --- | --- |
| `list` | 有 | 摘要 | 无 |
| `detail` | 无 | 完整（需 `ids` / `t` / `pg` / `h`） | 有 |
| `videolist` | 无 | 完整分页列表 | 有 |

本仓库 Go 客户端：分类 / 列表 / 搜索走 `ac=list`，取播放地址走 `ac=detail&ids=`。Apple 客户端目录和搜索使用 `ac=detail`，以便带上海报和播放地址。

---

## 3. 接口

以下示例基址使用红牛：`https://www.hongniuzy2.com/api.php/provide/vod/`。

### 3.1 分类 + 影片列表

```http
GET {base}?ac=list&pg=1
GET {base}?ac=list&t=1&pg=2
```

```bash
curl -sS -A 'Mozilla/5.0' \
  'https://www.hongniuzy2.com/api.php/provide/vod/?ac=list&pg=1'
```

成功时 `code` 为 `1`。`list` 里通常只有 `vod_id`、`vod_name`、`type_id`、`type_name`、`vod_en`、`vod_time`、`vod_remarks`、`vod_play_from`。

### 3.2 搜索

```http
GET {base}?ac=list&wd={keyword}&pg=1
```

```bash
curl -sS -A 'Mozilla/5.0' --get \
  --data-urlencode 'ac=list' \
  --data-urlencode 'wd=早春晴朗' \
  --data-urlencode 'pg=1' \
  'https://www.hongniuzy2.com/api.php/provide/vod/'
```

同样不含播放地址。要播再对命中的 `vod_id` 调详情。

### 3.3 影片详情（含播放地址）

```http
GET {base}?ac=detail&ids=151661
GET {base}?ac=detail&ids=151661,151660
GET {base}?ac=detail&h=24
GET {base}?ac=detail&t=1&pg=1
```

```bash
curl -sS -A 'Mozilla/5.0' \
  'https://www.hongniuzy2.com/api.php/provide/vod/?ac=detail&ids=151661'
```

`list[]` 含封面、演员、简介和 `vod_play_from` / `vod_play_url`。

### 3.4 带播放地址的分页列表

```http
GET {base}?ac=videolist&pg=1
GET {base}?ac=videolist&t=13&pg=1
```

部分站 `ac=videolist` 与 `ac=detail` 不带 `ids` 时行为相同。数据量大，不适合当首页轮询。

---

## 4. 响应结构

### 4.1 列表（`ac=list`）

```json
{
  "code": 1,
  "msg": "数据列表",
  "page": 1,
  "pagecount": 7646,
  "limit": "20",
  "total": 152920,
  "list": [
    {
      "vod_id": 132525,
      "vod_name": "影片名",
      "type_id": 13,
      "type_name": "国产剧",
      "vod_en": "pinyin",
      "vod_time": "2026-09-02 12:00:00",
      "vod_remarks": "更新至16集",
      "vod_play_from": "liangzi,lzm3u8"
    }
  ],
  "class": [
    { "type_id": 1, "type_name": "电影" },
    { "type_id": 2, "type_name": "连续剧" }
  ]
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | number | `1` 成功。个别站用字符串，解析需兼容 |
| `msg` | string | 提示 |
| `page` | number / string | 当前页 |
| `pagecount` | number / string | 总页数 |
| `limit` | string | 每页条数，常见 `"20"` |
| `total` | number / string | 总条数 |
| `list` | array | 影片摘要 |
| `class` | array | 分类。仅 `ac=list` 稳定出现 |
| `list[].vod_id` | number / string | 站内 ID，详情接口用 |
| `list[].vod_name` | string | 片名 |
| `list[].type_id` | number | 分类 ID |
| `list[].type_name` | string | 分类名 |
| `list[].vod_en` | string | 拼音 / 英文 slug |
| `list[].vod_time` | string | 更新时间 |
| `list[].vod_remarks` | string | 更新至 xx 集 / 高清 等 |
| `list[].vod_play_from` | string | 播放线标识，列表里可能用逗号分隔 |

`page`、`pagecount`、`total`、`vod_id` 在不同站可能是数字或字符串，本仓库用弹性类型解析。

### 4.2 详情（`ac=detail`）

在列表字段基础上增加：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `vod_pic` | string | 海报 URL |
| `vod_area` | string | 地区 |
| `vod_lang` | string | 语言 |
| `vod_year` | string | 年份 |
| `vod_serial` | string | 连载集数，完结多为 `"0"` |
| `vod_actor` | string | 演员，逗号分隔 |
| `vod_director` | string | 导演 |
| `vod_class` | string | 扩展类型标签 |
| `vod_blurb` | string | 短简介（部分站） |
| `vod_content` | string | 简介，可能含 HTML |
| `vod_play_from` | string | 播放线，多线用 `$$$` |
| `vod_play_url` | string | 播放地址，与 `from` 按下标对齐 |
| `vod_play_server` | string | 服务器组，可忽略 |
| `vod_play_note` | string | 线路备注，可忽略 |

详情响应一般**没有** `class` / `pagecount`。

---

## 5. 播放地址编码

`vod_play_from` 与 `vod_play_url` 按下标一一对应。

```text
vod_play_from = hnyun$$$hnm3u8
vod_play_url  = <云播各集>$$$<m3u8 各集>
```

分隔符：

| 符号 | 含义 |
| --- | --- |
| `$$$` | 播放线之间 |
| `#` | 同一条线的各集 |
| `$` | `集名$url` |

列表接口里 `vod_play_from` 有时用逗号：`liangzi,lzm3u8`。详情里几乎都是 `$$$`。本仓库两种都解析。

单线多集示例：

```text
第1集$https://hn.bfvvs.com/a.m3u8#第2集$https://hn.bfvvs.com/b.m3u8
```

两线示例：

```text
from: hnyun$$$hnm3u8
url:  正片$https://yun.example/1.html$$$第1集$https://hn.bfvvs.com/1.m3u8#第2集$https://hn.bfvvs.com/2.m3u8
```

无 `$` 时，整段当作 URL，集名用「第」+ 原文。

m3u8 直链通常可直接播；`yun` 云播多为站点页，需 `jx_url` 解析。本仓库各源 `jx_url` 现为 `https://www.playm3u8.cn/jiexi.php?url=`。

---

## 6. 本仓库已接入的源

`flag: 0` 启用。`id` 为站内源编号，不是 MacCMS 的 `vod_id`。

| id | 名称 | 基址 | play_from | 备注 |
| ---: | --- | --- | --- | --- |
| 33 | 无忧 | `https://www.wyvod.com/api.php/provide/vod/` | 视站而定 | 无公开帮助页 |
| 125 | 猫眼 | `https://api.maoyanapi.top/api.php/provide/vod/` | `mym3u8` | [帮助](http://www.maoyanzy.com/maoyanzy/help.html) |
| 143 | 虎牙 | `https://www.huyaapi.com/api.php/provide/vod/at/json` | `hym3u8` / `hyyun` | [帮助](https://huyazy.net/index.php/help) |
| 146 | 影剧 | `https://caiji.maotaizy.cc/api.php/provide/vod/at/josn/` | `mtm3u8` / `mtyun` | 路径是 `josn` 不是 `json`。[帮助](https://caiji.maotaizy.cc/index.php/help) |
| 157 | 光速 | `https://api.guangsuapi.com/api.php/provide/vod/` | `gsm3u8` / `gsyun` | [帮助](https://www.guangsuzy.com/index.php/help) |
| 158 | 魔都 | `https://www.mdzyapi.com/api.php/provide/vod/` | `modum3u8` | |
| 159 | 非凡 | `http://api.ffzyapi.com/api.php/provide/vod/` | `ffm3u8` / `feifan` | HTTPS 备用 `https://cj.ffzyapi.com/api.php/provide/vod/`。[帮助](https://ffzy5.tv/help/) |
| 160 | 量子 | `https://cj.lziapi.com/api.php/provide/vod/` | `lzm3u8` / `liangzi` | [帮助](https://lzizy.net/help/) |
| 161 | 暴风 | `https://bfzyapi.com/api.php/provide/vod/` | `bfzym3u8` | |
| 162 | 极速 | `https://jszyapi.com/api.php/provide/vod/` | `jsm3u8` / `jsyun` | [帮助](https://jisuzy.com/index.php/help/index.html) |
| 163 | 速播 | `https://subocaiji.com/api.php/provide/vod/` | `subm3u8` / `subyun` | 与新浪共用 CDN `play.xluuss.com`。[帮助](https://www.subozy.com/index.php/help) |
| 164 | 红牛 | `https://www.hongniuzy2.com/api.php/provide/vod/` | `hnm3u8` / `hnyun` | [帮助](https://hongniuzy.tv/help/) |
| 165 | 无尽 | `https://api.wujinapi.com/api.php/provide/vod/` | `wjm3u8` | [帮助](https://help.wujinapi.me/) |
| 166 | 索尼 | `https://suonizy.com/api.php/provide/vod/` | `snm3u8` | |
| 167 | 无印 | `https://api.wsyzy.net/api.php/provide/vod/` | `wsym3u8` | [帮助](https://www.wsyzy.cc/help/) |
| 168 | 新浪 | `https://api.xinlangapi.com/xinlangapi.php/provide/vod/` | `xlm3u8` / `xlyun` | 文件名是 `xinlangapi.php` 不是 `api.php`。[帮助](https://www.xinlangzy.com/index.php/help/index.html) |
| 169 | 西瓜 | `https://caiji.xgzyapi.com/api.php/provide/vod/` | `xiguam3u8` / `xigua` | [帮助](https://xgzy8.tv/help/) |
| 170 | 豆瓣 | `https://dbzy.tv/api.php/provide/vod/` | `dbm3u8` / `dbyun` | `caiji.dbzy.tv` 当前 SSL 不稳定。[帮助](https://dbzy.tv/index.php/help) |
| 171 | 1080 | `https://api.1080zyku.com/inc/api_mac10.php` | `1080zyk` | 非标准 `api.php/provide/vod/`，参数相同 |
| 172 | 爱坤 | `https://ikunzyapi.com/api.php/provide/vod/` | `ikm3u8` | |
| 173 | 豪华 | `https://hhzyapi.com/api.php/provide/vod/` | `hhm3u8` / `hhyun` | [帮助](https://www.haohuaziyuan.com/index.php/help/index.html) |
| 174 | 如意 | `https://cj.rycjapi.com/api.php/provide/vod/` | `rym3u8` / `ruyi` | [帮助](https://ryzy.tv/help/) |
| 175 | U酷 | `https://api.ukuapi88.com/api.php/provide/vod/` | `ukm3u8` / `ukyun` | `api.ukuapi.com` 会 301 |
| 176 | 奇艺 | `https://iqiyizyapi.com/api.php/provide/vod/` | `iqym3u8` | 第三方采集站，不是爱奇艺官方 |
| 177 | 金鹰 | `https://jyzyapi.com/provide/vod/` | `jinyingm3u8` / `jinyingyun` | 无 `api.php` 前缀。备用 `https://jinyingzy.com/api.php/provide/vod/`。[帮助](https://jyzyapi.com/index.php/help) |
| 178 | 最大 | `https://api.zuidapi.com/api.php/provide/vod/` | `zuidam3u8` | |
| 179 | 天堂 | `http://caiji.dyttzyapi.com/api.php/provide/vod/` | `dyttm3u8` / `dytt` | HTTP |
| 180 | 牛牛 | `https://api.niuniuzy.me/api.php/provide/vod/` | `nnm3u8` | |
| 181 | 360 | `https://360zyzz.com/api.php/provide/vod/` | `360zy` | 备用 `https://360zy.com/api.php/provide/vod/`。[帮助](https://360zyzz.com/360zy/help.html) |

线路中文名映射见 [`web/lib/playSourceNames.ts`](../web/lib/playSourceNames.ts) 与 [`apps/api-go/internal/service/parser/names.go`](../apps/api-go/internal/service/parser/names.go)。

播放线路权重与统一取播形状见 [`docs/superpowers/specs/2026-09-03-unified-play-lines-design.md`](superpowers/specs/2026-09-03-unified-play-lines-design.md)：配置 `play-line-weights.json`，API `POST /api/v1/play/resolve`（`mode=direct` 走 MacCMS/`jx_url`；`mode=ticket` 需配置 `BPZ5_HMAC_SECRET` 代调解票）。配置密钥后，详情会按片名自动合并 bpz5 官方线（见 [`bpz5-official-lines-merge-design.md`](superpowers/specs/2026-09-03-bpz5-official-lines-merge-design.md)）。

---

## 7. 调用流程（本仓库）

```text
1. GET {base}?ac=list&pg=1          → class[] + 首页摘要
2. GET {base}?ac=list&t={id}&pg=n   → 分类翻页
3. GET {base}?ac=list&wd=词&pg=1    → 搜索（无播放地址）
4. GET {base}?ac=detail&ids={id}    → 海报 + vod_play_url
5. 按 $$$ / # / $ 拆成线路和分集，并按 play-line-weights 排序
6. POST /api/v1/play/resolve {mode:direct, sourceId, url}  （兼容旧 GET /play/parse）
```

实现位置：

- Go：[`apps/api-go/internal/service/maccms/client.go`](../apps/api-go/internal/service/maccms/client.go)
- 播放线拆分 / 权重：[`apps/api-go/internal/service/parser/`](../apps/api-go/internal/service/parser/)

---

## 8. 跨源统一分类（本仓库聚合层）

各站 `type_id` **不能跨源复用**。本仓库用静态映射表统一为 slug（如 `movie`、`movie-action`），再扇出到各站真实 `t`。

| 项 | 说明 |
| --- | --- |
| 配置 | 三端同内容：`apps/api-go/config/unified-categories.json`、`web/config/unified-categories.json`、`clients/apple/.../unified-categories.json` |
| 刷新 | `scripts/refresh-unified-categories.py`（可 `--from-snapshots`） |
| Go / Web | `GET /vod/categories`；`GET /vod/list?cat={slug}&pg=`（`cat` 优先于 `t`） |
| Apple | 内嵌 JSON；首页 Tab 与列表按 slug 多源并行 |
| 规格 | [`docs/superpowers/specs/2026-09-03-unified-categories-design.md`](superpowers/specs/2026-09-03-unified-categories-design.md) |

---

## 9. 错误与兼容

| 现象 | 处理 |
| --- | --- |
| HTTP 非 2xx | 视为该源失败，换源或重试 |
| 正文是 HTML 首页 | 基址被 SPA / 防火墙接管，接口失效 |
| JSON 解析失败 | 先去 BOM；再检查是否 XML（需 `at=json` 或换站） |
| `IncompleteRead` / 连接被掐 | 缓冲读完整包，勿按 Content-Length 截断 |
| Cloudflare 301 自循环 | 当前出口被拦，换 DNS / 线路 |
| `code != 1` | 以 `msg` 为准，常见为空列表 |
| 有影片不能播 | `from` 与播放器编码不一致，或云播未走解析 |

分类 ID **不能跨站混用**：红牛的 `t=13` 和量子的 `t=13` 不是同一分类。请用上文统一分类 `cat`。

---

## 10. XML（本仓库不用）

老接口加 `at=xml` 或路径 `/at/xml/`。海洋 CMS 常用 `/at/xmlsea/`。根节点多为 `<rss>` / `<list>`。本仓库只解析 JSON。

---

仅供个人学习研究。第三方采集站随时改域名、限流或关站，以 `sources.json` 实测为准。
