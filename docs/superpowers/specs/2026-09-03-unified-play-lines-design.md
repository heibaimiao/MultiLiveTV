# 统一播放线路：模型 / 权重 / API 形状

- 日期：2026-09-03
- 状态：一期已实现；二期解票已实现；详情合并官方 line_options 另开
- 范围：契约与排序先统一；搜剧官方线接入为二期
- 关联：[`docs/souju-playback-api.md`](../../souju-playback-api.md)
- 相关：[`2026-09-03-unified-categories-design.md`](2026-09-03-unified-categories-design.md)、[`docs/souju-playback-api.md`](../../souju-playback-api.md)

## 1. 背景

产品里实际存在两套「取播」路径，形状不同：

| | MacCMS 直链（现网） | 搜剧官方 parse（仅脚本） |
| --- | --- | --- |
| 线路来源 | `vod_play_from` / `vod_play_url` | `GET /v1/playback/resolve/{token}` → `line_options` |
| 取地址 | URL 多为 m3u8；可选 `jx_url` | `POST /v1/playback/resolve-line` + ticket |
| 鉴权 | 无 | HMAC；官方线常需 session |
| 主应用 | Go / Web / Apple 已接 | **未接** |

目标：**先统一线路模型、权重排序与取播 API 形状**；主应用仍只填 `direct` 线路。二期再把 `ticket`（bpz5）接到同一形状上，客户端不用再改交互协议。

## 2. 分期

### 一期（本文必须交付）

1. 共享 `PlayLine` 模型（OpenAPI + Go/Web/Apple 对齐字段）
2. 共享线路权重配置，详情 `playSources` **按权重降序**
3. 统一取播 API 形状：`POST /api/v1/play/resolve`（一期只实现 `mode=direct`）
4. 默认选线：权重最高且当前可播的一条
5. 文档标明二期 `ticket` 字段与行为（实现可 stub：`501` / `unsupported_mode`）

### 二期（解票 + 详情官方线）

- [x] 服务端代调 bpz5 `resolve-line`（`BPZ5_HMAC_SECRET`）
- [x] 详情按片名合并官方 `line_options`（见 [`2026-09-03-bpz5-official-lines-merge-design.md`](2026-09-03-bpz5-official-lines-merge-design.md)）
- [x] 密钥 / session 不出客户端

## 3. 统一模型 `PlayLine`

取代各端零散 `PlaySource` 字段差异时，对外契约以本结构为准（内部可继续叫 PlaySource，但序列化对齐）：

```json
{
  "key": "cloudflare",
  "label": "高清-官方C",
  "weight": 900,
  "mode": "direct",
  "playFrom": "hnm3u8",
  "providerId": null,
  "sourceId": 164,
  "url": "https://....m3u8",
  "ticket": null,
  "requiresAuth": false,
  "episodes": [
    { "name": "第01集", "url": "https://....m3u8" }
  ]
}
```

| 字段 | 一期 | 说明 |
| --- | --- | --- |
| `key` | 必填 | 稳定标识：`{sourceId}:{playFrom}` 或 bpz5 `play_from` / `provider_id` |
| `label` | 必填 | 展示名（已有 `formatPlaySourceName` / 官方显示名） |
| `weight` | 必填 | 来自权重表；越大越靠前 |
| `mode` | 必填 | `direct` \| `ticket`；一期产物几乎全是 `direct` |
| `playFrom` | 建议 | 原始线路码：`hnm3u8`、`cloudflare`、`qq`… |
| `providerId` | 二期 | bpz5 `provider_id`；一期 `null` |
| `sourceId` | MacCMS 有则填 | 采集站 id |
| `url` | direct 单集时可在 episode 上 | 线路级可选；分集以 `episodes[].url` 为准 |
| `ticket` | 二期 | `rpt1…`；一期 `null` |
| `requiresAuth` | 默认 false | 二期官方线可为 true |
| `episodes` | 必填 | 与现网一致 |

**取播请求体（统一形状）：**

```json
{
  "mode": "direct",
  "sourceId": 164,
  "url": "https://....m3u8",
  "jx": true
}
```

二期扩展（一期可写进 OpenAPI，服务端对 `mode=ticket` 返回明确错误）：

```json
{
  "mode": "ticket",
  "ticket": "rpt1....",
  "providerId": "bytevod-cloudflare",
  "playFrom": "cloudflare"
}
```

**取播响应：**

```json
{
  "url": "https://cdn.../index.m3u8",
  "parsed": true,
  "mode": "direct",
  "expiresAt": null
}
```

## 4. 权重表

配置文件（三端同步，与分类表类似）：

- `apps/api-go/config/play-line-weights.json`
- `web/config/play-line-weights.json`
- `clients/apple/MultiLiveTV/Resources/play-line-weights.json`

```json
{
  "version": 1,
  "defaultWeight": 100,
  "byPlayFrom": {
    "cloudflare-4k": 1000,
    "cloudflare": 900,
    "huo": 800,
    "lv2": 750,
    "bytedance": 700,
    "rrys": 650,
    "qq": 600
  },
  "byProviderId": {
    "bytevod-cloudflare-4k": 1000,
    "bytevod-cloudflare": 900,
    "official-v": 800,
    "bytevod-lv2": 750,
    "bytedance": 700,
    "official-r": 650,
    "official-hot-playback": 600
  }
}
```

排序规则：

1. 查 `byProviderId[providerId]`，否则 `byPlayFrom[playFrom]`，否则 `defaultWeight`
2. 同权：可播直链（url 像 m3u8/mp4）优先于需解析；再比集数
3. 详情返回的数组 **已排序**；客户端默认选 `playSources[0]`（或第一个 `mode` 当前可解的）

一期 MacCMS 线路几乎都是 `defaultWeight=100`，组内仍可用现有「直链可播性」作同分 tie-break。二期官方线自然排到最前。

**组内优先顺序（已决）：**  
`4K → 官方C → V → Z → B → R → 腾讯` → 其它直链。

## 5. API 变更

### 5.1 `POST /api/v1/play/resolve`（新增，推荐）

统一取播入口。一期行为等价于现有 `GET /play/parse?sourceId=&url=`：

- `mode=direct`：走 `jx_url`（`jx=false` 则原样返回 url）
- `mode=ticket`：配置了 `BPZ5_HMAC_SECRET` 时代调 bpz5；否则 `501` + `{ "error": "ticket_not_enabled" }`

OpenAPI 同步；旧 `GET /play/parse` **保留**至少一个版本，内部可转调同一实现。

Web：`POST /api/play/resolve`。

### 5.2 详情中的 `playSources`

`GET /vod/detail`（及 Web 对应）返回的每条线路补齐 `weight`、`mode`、`playFrom`（能解析则填）。数组按权重排序。

不改变现有合并多源逻辑，只在 merge 之后 **stable sort by weight**。

## 6. 各端改动（一期）

| 端 | 改动 |
| --- | --- |
| OpenAPI | `PlayLine`、`PlayResolveRequest/Response`、weights 说明 |
| api-go | 读 weights；merge 后排序；新 resolve handler；parse 复用 |
| web | 类型对齐；详情/播放走新字段；可选改调 `POST /api/play/resolve` |
| Apple | `PlaySource` 增字段；`preferredSourceIndex` 改为按 `weight`；验证脚本 |

不在一期改：bpz5 客户端、片库 token、登录 session。

## 7. 与「统一分类」的关系

- **分类**：跨源浏览用 `cat` slug（另文）
- **线路**：详情内播放用 `PlayLine` + weight（本文）
- 二者独立交付；可并行实现，无阻塞依赖

## 8. 验收（一期）

- [x] 三端 weights JSON 一致，`cloudflare-4k` > `cloudflare` > `qq` > default
- [x] 人为构造含 `playFrom=qq` 与 `hnm3u8` 的列表时，排序 qq 在前（二期数据也适用同一函数）
- [x] `POST /play/resolve` + `mode=direct` 与旧 parse 结果一致（透传 / jx）
- [x] `mode=ticket` 返回明确未启用错误，而非崩溃
- [x] Apple / Web 默认选中权重最高线
- [x] OpenAPI 已描述二期 ticket 字段

## 9. 已决问题

- 先模型/权重/API 形状，后接入 bpz5
- 权重顺序：4K → C → V → Z → B → R → 腾讯 → 其它
- 旧 `/play/parse` 保留兼容
- 官方线密钥仅二期出现在服务端
