# 搜剧 AI（bpz5 / souju）播放接口文档

本文记录从 [bpz5.com](https://bpz5.com/)（品牌 souju.ai / 白嫖者）前端逆向得到的 **私有 `/v1` 播放接口**。  
**不是**苹果 CMS `api.php/provide/vod/`，不能写入本仓库 `sources.json`。

本地验证脚本：[`scripts/bpz5-resolve-line.py`](../scripts/bpz5-resolve-line.py)  
本地解票页面：[`scripts/bpz5-resolve-ui.py`](../scripts/bpz5-resolve-ui.py)（`http://127.0.0.1:8765`）  
接口说明：本文。

相关：MacCMS 采集协议见 [`docs/maccms-api.md`](maccms-api.md)。

---

## 1. 约定

| 项 | 说明 |
| --- | --- |
| 基址 | `https://bpz5.com`（`canonical_host` 可能变化；`souju.ai` 同源前端） |
| 协议 | HTTPS，`GET` / `POST`，JSON |
| 鉴权 | 每个请求需 HMAC 签名头（见下节） |
| 密钥 | 前端打包内硬编码，**随时会换** |
| Content-Type | 请求体 `application/json`；响应 `application/json` |

与本仓库 MacCMS 源的关系：

- `line_options` 里大量 `*m3u8` 直链 → 对应各家苹果 CMS 采集站（红牛、量子等），已在 `sources.json`
- `resolve_ticket` / `resolve_mode=parse` → 官方高清 / 4K / 腾讯等，只能走本文接口解票

---

## 2. 请求签名

每个 `/v1/...` 请求带：

| Header | 说明 |
| --- | --- |
| `x-ai-movie-timestamp` | 毫秒时间戳字符串 |
| `x-ai-movie-nonce` | 随机 hex（如 UUID 去横线） |
| `x-ai-movie-signature` | HMAC-SHA256 十六进制 |
| `x-ai-movie-client-name` | 前端固定 `movie-search-frontend` |

签名 payload（原文，四行）：

```text
{METHOD}\n
{pathname}{?query}\n
{timestamp}\n
{nonce}
```

示例：

```text
GET
/v1/playback/resolve/YJ-a09cbb6e2204f84988b3
1730000000000
a1b2c3d4e5f6...
```

```python
import hmac, hashlib

sig = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
```

当前前端密钥（会失效，仅供本地验证）：

```text
f39d73aa7a6426203cdee1ef17b31d3b7ea8c23f4c59c62a3a8aa0f39ee5e79d
```

建议同时带浏览器 `User-Agent`、`Origin`、`Referer`（同源）。

---

## 3. 相关片库接口（取 token 用）

播放解票需要 **集 token**（如 `YJ-...`）。常见入口：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/v1/runtime/bootstrap` | 运行时配置（`canonical_host` 等） |
| `GET` | `/v1/feed/home` | 首页推荐 |
| `GET` | `/v1/browse/catalog` | 片库浏览 |
| `GET` | `/v1/yj/catalog` | yj 片库 |
| `GET` | `/v1/yj/trending` | 热门 |
| `GET` | `/v1/catalog/{variant_id}` | 详情 |
| `GET` | `/v1/catalog/{variant_id}/episodes` | 分集分页 |
| `GET` | `/v1/catalog/{variant_id}/variants` | 变体 |

详情 / 分集响应里会带 episode `token` 或可拼出播放入口。前端播放页路径形如 `/yj/{hex}`，对应集 token `YJ-{hex}`。

---

## 4. 列出本集线路

### `GET /v1/playback/resolve/{episode_token}`

把一集解析成全部可播线路（含直链与待解票线路）。

```http
GET /v1/playback/resolve/YJ-a09cbb6e2204f84988b3
Accept: application/json
x-ai-movie-timestamp: ...
x-ai-movie-nonce: ...
x-ai-movie-signature: ...
x-ai-movie-client-name: movie-search-frontend
```

```bash
python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3 --tickets-only --parse-only
```

### 响应 `object: playback.resolve`

| 字段 | 说明 |
| --- | --- |
| `token` | 当前集 token |
| `current_episode` | 集信息：`display_name`、`next_episode_token`、`path` 等 |
| `current_episode.urls` | 常为 `{}`；选中 parse 线且未解票时为空 |
| `line_options[]` | 线路列表（官方 parse 线通常排在前） |

### `line_options[]` 字段

| 字段 | 说明 |
| --- | --- |
| `playback_source_id` / `id` | 线路 ID，如 `playback:yj:...` |
| `provider_id` | 内部源，如 `bytevod-cloudflare`、`hongniu` |
| `provider_name` / `label` | 显示名，如「高清-官方C」「腾讯视频」 |
| `play_from` | 线路编码：`cloudflare`、`qq`、`hnm3u8` 等 |
| `source_vod_id` | 该源内部片 ID，**不可跨站混用** |
| `url` | 直链 m3u8，或 `resolve://rpt1.{jwt}.{sig}` |
| `url_kind` | `m3u8` / `resolve_ticket` / 解票后可能是 `mp4` |
| `resolved` | 是否已是可播 URL |
| `resolve_mode` | `direct` 或 `parse` |
| `resolve_required` | 是否必须再调 resolve-line |
| `preference_weight` | 排序权重，越大越靠前 |
| `default_priority` | 是否默认优先组 |
| `selected` | 当前是否选中 |
| `price_multiplier_bps` | 计价倍数（基点）；直链多为无此字段 |
| `token_scenario` | 直链常见 `direct_zero` |
| `minimum_user_level` | 最低用户等级 |

### 线路两类

```text
line_options
├── parse（官方高清 / 4K / 腾讯等）
│     url_kind = resolve_ticket
│     url = resolve://rpt1.{payload}.{hmac}
│     resolved = false，resolve_required = true
└── direct（红牛、量子等 MacCMS 同源）
      url_kind = m3u8
      url = https://.../index.m3u8
      resolved = true，resolve_mode = direct
```

`resolve://` 去掉前缀后的 ticket payload（JWT 中段）大致为：

```json
{
  "episodeId": "episode:yj:...",
  "playbackSourceId": "playback:yj:...",
  "expiresAt": 1788336041440
}
```

`expiresAt` 为毫秒时间戳，过期后需重新 `GET resolve` 拿新票。

---

## 5. 解票换真实播放地址

### `POST /v1/playback/resolve-line`

```http
POST /v1/playback/resolve-line
Content-Type: application/json
x-ai-movie-timestamp: ...
x-ai-movie-nonce: ...
x-ai-movie-signature: ...
x-ai-movie-client-name: movie-search-frontend

{"ticket":"rpt1.eyJ..."}
```

成功多为 **HTTP 201**，`object` 为 `playback.line.resolve`。

请求体 schema（前端校验）：

```json
{ "ticket": "<string, 1..4096>" }
```

### 响应要点

| 字段 | 说明 |
| --- | --- |
| `token` | 集 token |
| `content_kind` | 如 `series` |
| `episode_count` | 总集数（若有） |
| `current_episode` | 集信息 |
| `line` | **解出后的单条线路**（含真实 `url`） |
| `quota_delta` | 可选；额度变化 |

`line` 在解票成功后：

| 字段 | 说明 |
| --- | --- |
| `url` | 可播地址（m3u8 或带签名的 mp4） |
| `url_kind` | `m3u8` / `mp4` / `unknown` |
| `resolved` | `true` |
| `resolve_required` | `false` |
| `resolve_mode` | 仍可能是 `parse`（表示来源类型） |

```bash
# 只解官方 parse 线
python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3 --parse-only

# 过滤 Cloudflare + 腾讯
python3 scripts/bpz5-resolve-line.py YJ-a09cbb6e2204f84988b3 --parse-only --only cloudflare,qq

# 本地解票页面（本机代理签名，避免浏览器 CORS）
python3 scripts/bpz5-resolve-ui.py
# 浏览器打开 http://127.0.0.1:8765
```

页面能力：输入集 token → 拉取 `line_options` → 单条/批量解票 → 复制真实 URL。代理路由：

| 页面接口 | 上游 |
| --- | --- |
| `GET /api/suggest?q=` | `GET /v1/suggest` |
| `GET /api/browse/catalog?q=` | `GET /v1/browse/catalog` |
| `GET /api/catalog/{id}` | `GET /v1/catalog/{id}` |
| `GET /api/catalog/{id}/episodes` | `GET /v1/catalog/{id}/episodes` |
| `GET /api/playback/resolve/{token}` | `GET /v1/playback/resolve/{token}` |
| `POST /api/playback/resolve-line` | `POST /v1/playback/resolve-line` |

页面流程：搜索 → 展示详情/分集/线路 → 点「播放」（直链直接播；官方线先 `resolve-line` 再播）。
官方 C/V/Z/B/R/腾讯 与采集站直链都会列出。部分官方线需登录，失败时换「仅直链」。

---

## 6. 官方 parse 线路（实测解析）

以下线路**没有**开放 MacCMS 采集口，只能：

```text
GET  /v1/playback/resolve/{episode_token}   → line_options 里拿到 resolve://rpt1... 票
POST /v1/playback/resolve-line  {"ticket":"rpt1..."}  → 真播放地址（需会话 cookie）
```

本地测试台会自动 `POST /v1/users/anonymous` 建匿名会话后再解票。

### 6.1 站内自建 CDN 族

| 显示名 | play_from | provider_id | 解票后形态 | 备注 |
| --- | --- | --- | --- | --- |
| 高清-官方C | `cloudflare` | `bytevod-cloudflare` | `lf1.wikjdd.cn/.../index.m3u8?verify=...` | 分片常为 PNG 包 TS + BYTERANGE |
| 4K-官方C | `cloudflare-4k` | `bytevod-cloudflare-4k` | 同上域另一条 m3u8 | 可能扣词元 |
| 1080P-官方V | `huo` | `official-v` | `*.byteimg.com` 签名 **mp4**（URL 像 jpg） | MIME 常伪装 image/jpeg |
| 1080P-官方Z | `lv2` | `bytevod-lv2` | `*-heycan-sign.byteimg.com` 签名 **mp4** | 同上 |
| 高清-官方B | `bytedance` | `bytedance` | `ixigua.com` / `onewsvod.com` | `url_kind` 常为 unknown |
| 1080P-官方R | `rrys` | `official-r` | `sign.site.zshtys888.com/file.m3u8?ucode=` | |

### 6.2 热播聚合族（`official-hot-playback`）

同一 `provider_id`，用不同 `play_from` 区分平台名；解票后多为对象存储 / 专用 m3u8 网关，**不是**各平台开放 API。

| 显示名 | play_from | 解票后常见 host | 形态 |
| --- | --- | --- | --- |
| 腾讯视频 | `qq` | `*.cmecloud.cn` 或 `43.248.128.134:2222/Tencent/` | mp4 或 m3u8，短时签名 |
| 爱奇艺 | `qiyi` | `43.248.128.134:2222/Tencent/` | m3u8 |
| 优酷 | `youku` | 同上网关 | m3u8 |
| 芒果TV | `mgtv` | 同上网关 | m3u8 |
| 哔哩哔哩 | `bilibili` | （偶发） | 可能 404 |

另有 **1080P-官方D**（`play_from=Dong` / `provider_id=dong`）→ `*.cmecloud.cn` 签名 mp4，与热播文件类似。

### 6.3 解析要点

- 列表阶段只有票，**不播放**；真 URL 短时有效，过期需重新 resolve → resolve-line
- 部分片名解票返回 `quota_delta.used_tokens`（如 60000），会扣词元
- 「4K / 1080P / 高清」是展示名，响应里一般不带分辨率元数据
- **不能**写入 `sources.json`；要接官方线只能做 bpz5 专用适配器

说明：

- 「4K / 高清」是站点线路名，解票响应里一般不带分辨率元数据
- 腾讯线不是腾讯开放 API，只是聚合站映射后的热播文件
- 部分线带 `price_multiplier_bps`（如官方 C 5000 = 50%），可能与额度有关

---

## 7. 站点真实播放逻辑（前端）

前端核心在 `native-download-media-type-*.js`（播放准备）+ `global-player-host-*.js`（播放器宿主）。  
官方高清 / 4K / 腾讯 **不是** 再去请求苹果 CMS，而是站点自己的 CDN 票；红牛等才是采集站直链。

### 7.1 片源从哪来

| 类型 | `resolve_mode` | 片源含义 | 典型字段 |
| --- | --- | --- | --- |
| 官方线 | `parse` | 站内聚合/转码 CDN（Cloudflare、字节、人人影视映射、腾讯热播文件等） | `provider_id=bytevod-cloudflare` 等；`url=resolve://rpt1...` |
| 采集站线 | `direct` | 第三方 MacCMS 资源站已经给出的 m3u8 | `play_from=hnm3u8`；`source_vod_id=source:hongniu:123`；`url=https://...m3u8` |

`GET /v1/playback/resolve/{token}` 一次返回两类 `line_options`。列表阶段**不播放**；官方线此时只有短时票据。

### 7.2 播放主路径

```text
打开播放页（集 token = YJ-...）
        │
        ▼
$o / fe:
GET /v1/playback/resolve/{token}
  ?line=&provider_id=&play_from=&source_vod_id=
  &episode_index=&episode_count=&content_kind=
  [&consume=...] [&quota_debug=...]
auth: 默认 "auto"（HMAC）；若带 consume 则 "session"
        │
        ▼
Fe / Z: 选线
  1) 用户指定的 line / provider+play_from / source_vod_id
  2) 否则 selected=true
  3) 否则第一条
  （sessionStorage 可设 prefer_direct，倾向直链）
        │
        ├─ direct：url 已是 m3u8 ──────────────► 交给播放器（HLS / 原生）
        │
        └─ parse：ee() 判断要不要解票
                 │ 未 resolved / 票过期 / 无 expires_at 且超时
                 ▼
              Ie → Se:
              POST /v1/playback/resolve-line
              body: {"ticket":"rpt1..."}
              auth: "session"   ← 必须登录会话（credentials include）
                 │
                 ├─ 201：line.url 真地址；可能有 quota_delta 扣词元
                 ├─ 401 login_required：弹登录 / 不可播官方线
                 ├─ 402：词元用尽
                 └─ 其它：提示换线
                 │
                 ▼
              播放器播 m3u8 或 mp4（短时 CDN 签名 URL）
```

### 7.3 鉴权差异（重要）

| 接口 | 前端 `auth` | 含义 |
| --- | --- | --- |
| `GET .../playback/resolve` | `auto`（默认可匿名） | 只要 HMAC，即可拿线路列表和直链 |
| `POST .../playback/resolve-line` | **`session`（强制）** | 要登录 cookie / 账户会话；仅 HMAC 会在部分片上 401 |

因此：未登录时，官方线列表看得到、解票常失败；同页的红牛等 `direct` 线仍可播。  
部分剧集官方线允许匿名解票（如部分热播剧），站点按片策略控制，不是客户端写死「只能解固定剧」。

### 7.4 错误码（前端文案）

| HTTP | 前端理解 |
| --- | --- |
| 400 | 播放参数无效，请从详情重进 |
| 401 / 403 | 当前播放请求不可用（含要登录） |
| 402 | 今日词元耗尽；可邀请得临时词元 |
| 404 | 资源暂不可用，换线 |
| 429 | 太频繁 |
| ≥500 | 服务暂不可用 |

另有业务码 `playback_line_level_required`：等级不足。

### 7.5 和本地脚本的差距

本地 `bpz5-resolve-ui` 启动时会调用 `POST /v1/users/anonymous` 建立匿名会话（cookie `ai_movie_session`），  
`resolve-line` 会带上该会话。多数原先 401 的官方 V/Z/C 线因此可解票（无需注册账号）。  
`bpz5-resolve-line.py` 命令行默认仍只有 HMAC；要对齐 UI，需同样携带会话 cookie。

---

本地解票脚本默认**未登录**。部分官方 parse 线会返回：

```json
{
  "statusCode": 401,
  "code": "playback_user_session_required",
  "state": "login_required",
  "message": "该内容需要登录后播放"
}
```

这与 HMAC 签名无关：片库/线路列表仍可匿名拉取，但 **解票换真实地址** 对该片要求用户会话。  
同片的 `direct` / `*m3u8` 采集站线路通常仍可直接播；「花开锦绣」等片的部分官方线允许匿名解票，所以会表现为「只有部分片能解官方线」。

注意：路径名是 **`/v1/playback/resolve-line`**，不是 `line/resolve`。误用会 404。

---

## 8. 错误与限制

| 现象 | 处理 |
| --- | --- |
| `playback_user_session_required` / 401 | 该片官方线要登录；改用 direct 采集站线，或带用户 session 再解票 |
| 签名错误 / 缺头 | 401/403 或业务错误；检查 payload 是否含 query、METHOD 大小写 |
| ticket 过期 | 重新 `GET resolve` 拿新票再 `resolve-line` |
| 解出 URL 403 | CDN 签名过期或 Referer/IP 限制；重新解票 |
| 密钥失效 | 从前端 JS 重新提取 `secret`，用脚本 `--secret` 覆盖 |
| `IncompleteRead` | 部分响应 Content-Length 不准，按读到的 JSON 解析 |
| 写入 `sources.json` | **不可行**；无 `provide/vod` |

---

## 9. 其它已观察到的 `/v1` 路径

播放周边（非解票核心）：

| 路径 | 说明 |
| --- | --- |
| `POST /v1/playback/skip-settings/report` | 片头片尾跳过上报 |
| `GET /v1/danmuku/episodes/{id}/source` | 弹幕源 |
| `GET /v1/danmuku/episodes/{id}/items` | 弹幕条目 |

用户 / 其它：`/v1/users/*`、`/v1/suggest`、`/v1/threads`、`/v1/tv-cast/*`、`/v1/midnight-theater/*` 等，与资源站采集无关，此处不展开。

---

仅供个人学习研究。接口、密钥、域名均可随时变更；以脚本实测为准。不要将该私有链路当作稳定 MacCMS 源接入生产。
