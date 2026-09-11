# 详情合并 bpz5 官方播放线

- 日期：2026-09-03
- 状态：已实现
- 范围：`apps/api-go`（权威）+ `web/` 对齐；Apple 经 Go API 自然获益
- 前置：[`2026-09-03-unified-play-lines-design.md`](2026-09-03-unified-play-lines-design.md) 一期权重 / 二期解票；[`docs/souju-playback-api.md`](../../souju-playback-api.md)

## 1. 目标

详情接口返回的 `playSources` 在 MacCMS 直链之外，按**片名自动搜索**挂上 bpz5 官方 `parse` 线（C / 4K / V / Z / B / R / 腾讯等）。播放仍走 `POST /play/resolve`（`mode=ticket`）。

非目标：

- 不改首页 / 列表数据源
- 不合并 bpz5 里的 MacCMS 同源 direct 线（避免重复）
- Apple 不内嵌 HMAC；客户端不持密钥
- 不做注册用户 / 词元账户 UI

## 2. 流程

```text
GET /vod/detail?sourceId=&ids=
  1. 现有 FetchMergedVodDetail（MacCMS）
  2. 若 BPZ5 已配置：EnrichOfficialPlaySources(vod)
  3. 返回 playSources = Sort(MacCMS ∪ 官方)
```

`EnrichOfficialPlaySources`：

1. 用 `vod.vod_name`（+ 可选 `vod_year`）搜 `GET /v1/browse/catalog?q=&intent=catalog_search`
2. 选最佳变体（`selected_variant_id` / `default_variant_id` / `id`）
3. `GET /v1/catalog/{id}/episodes?offset=0&limit=…`
4. 按集序号对齐 MacCMS 最长线路的集数；电影仅第 1 集
5. 对需覆盖的每一集（上限 40）`GET /v1/playback/resolve/{episode_token}`
6. 过滤 `resolve_mode=parse` 或 `url_kind=resolve_ticket` 的 `line_options`
7. 按 `provider_id`（或 `play_from`）聚合成 `PlaySource`，`episodes[i].url = resolve://…`

## 3. 匹配规则

| 规则 | 说明 |
| --- | --- |
| 标题归一 | 与现有 `NormalizeVodTitle` 一致（小写、去空白/常见标点） |
| 全等优先 | 归一后全等得分最高 |
| 包含次之 | 双向包含且长度差惩罚 |
| 年份 | `vod_year` 与候选年份一致加分 |
| 阈值 | 达不到阈值则不合并（静默） |

## 4. PlaySource 字段

| 字段 | 值 |
| --- | --- |
| `key` | `bpz5:{provider_id}` |
| `name` | `provider_name` / `label` |
| `mode` | `ticket` |
| `playFrom` | bpz5 `play_from` |
| `providerId` | bpz5 `provider_id` |
| `ticket` | 可选；分集票主要在 `episodes[].url` |
| `requiresAuth` | `true`（官方线依赖匿名 session） |
| `weight` | `play-line-weights` byPlayFrom / byProviderId |
| `episodes[].url` | `resolve://rpt1…` 或已是直链时原样 |

## 5. 会话与解票

- 服务端 `POST /v1/users/anonymous` 建立 cookie 会话并缓存
- `ResolveLine` 带 session；遇 `playback_user_session_required` 刷新匿名会话重试一次
- 未配置 `BPZ5_HMAC_SECRET`：跳过 enrich，行为与现网一致

## 6. 性能与失败

- enrich 单独超时预算约 5s；失败不影响 MacCMS 详情
- 内存短缓存：`(titleKey, year) → variantId`（TTL 建议 30–60min）
- 并发：分集 resolve 并发上限 4

## 7. Web

归档 `web` 在 detail API 同等 enrich（或调用同一逻辑思路）；详情页已能识别 `mode=ticket` / `resolve://`。

## 8. 验收

- [x] 无 secret：详情与现网一致
- [x] mock catalog + episodes + resolve：详情含 `bpz5:bytevod-cloudflare` 等
- [x] 片名无关命中：不合并
- [x] `go test` 相关包通过；Web tsc 通过
