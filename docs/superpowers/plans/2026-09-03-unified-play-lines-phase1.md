# 统一播放线路一期 实现计划

> **面向 AI 代理的工作者：** 逐任务实现；完成后进入二期（bpz5 ticket）。步骤用复选框跟踪。

**目标：** 统一 `PlayLine` 字段形状、权重排序与 `POST /play/resolve`（仅 `direct`）；为二期 `ticket` 预留契约。

**架构：** 三端共享 `play-line-weights.json`；merge 播放源后按 weight 降序；新增 resolve API，旧 parse 保留并复用同一实现。

**技术栈：** Go Gin、Next.js、Swift、OpenAPI

**规格：** [`docs/superpowers/specs/2026-09-03-unified-play-lines-design.md`](../specs/2026-09-03-unified-play-lines-design.md)

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `apps/api-go/config/play-line-weights.json` | 权重权威配置 |
| `web/config/play-line-weights.json` | Web 副本 |
| `clients/apple/MultiLiveTV/Resources/play-line-weights.json` | Apple 副本 |
| `apps/api-go/internal/service/parser/weights.go` | 加载权重 + SortPlaySources |
| `apps/api-go/internal/service/parser/weights_test.go` | 单元测试 |
| `apps/api-go/internal/model/types.go` | PlaySource 扩字段；ParseResolve 类型 |
| `apps/api-go/internal/service/parser/parser.go` | merge 时填 playFrom/mode/weight；排序 |
| `apps/api-go/internal/handler/vod.go` + `main.go` | POST /play/resolve |
| `packages/openapi/openapi.yaml` | 契约 |
| `web/lib/playLineWeights.ts` | 权重 + 排序 |
| `web/lib/types.ts` / `parser.ts` | 字段与 merge 排序 |
| `web/app/api/play/resolve/route.ts` | POST resolve |
| `clients/apple/.../Models.swift` | PlaySource 字段 |
| `clients/apple/.../PlayParser.swift` | 权重排序 |
| `clients/apple/.../DetailView.swift` | preferredSourceIndex 按 weight |
| `clients/apple/scripts/verify-client-logic.swift` | 测试 |

---

### 任务 1：权重 JSON（三端）

- [x] 创建三份内容相同的 `play-line-weights.json`（见规格 §4）

### 任务 2：Go 权重与排序（TDD）

- [x] 写 `weights_test.go`：`cloudflare-4k` > `cloudflare` > `qq` > 默认；同权时直链可播优先
- [x] 实现 `weights.go`：读 JSON（相对 config 路径 / embed 或启动加载）
- [x] 扩展 `PlaySource`：`Weight, Mode, PlayFrom, ProviderID, Ticket, RequiresAuth`
- [x] `ParsePlayURL` / `MergePlaySourcesFromVods` 填充 `PlayFrom`（原始 key）、`Mode=direct`、`Weight`，最后 `SortPlaySources`
- [x] `go test ./internal/service/parser/...`

### 任务 3：Go POST /play/resolve

- [x] 类型 `PlayResolveRequest` / 扩展 `ParseResult` 含 `mode`、`expiresAt`
- [x] Handler：`mode=direct` → 现有 `ParsePlayAddress`；`mode=ticket` → 501 `ticket_not_enabled`
- [x] `main.go` 注册 `POST /play/resolve`；保留 `GET /play/parse`
- [x] 更新 OpenAPI

### 任务 4：Web

- [x] `playLineWeights.ts` + 断言
- [x] 扩展 types；`mergePlaySourcesFromVods` 填字段并排序
- [x] `POST /api/play/resolve`；详情页改走 resolve、默认选最高权

### 任务 5：Apple

- [x] Bundle 加入 weights JSON；PlaySource 扩字段（Codable 兼容缺省）
- [x] PlayParser merge 后排序；DetailView `preferredSourceIndex` 取最大 weight
- [x] `verify-client-logic.swift` 增加权重排序断言

### 任务 6：一期验收

- [x] `go test` handler + parser
- [x] Apple verify 脚本相关用例
- [x] ResolvePlay ticket → 501；direct 透传 OK
- [x] 规格验收清单勾选

---

## 二期预告（一期完成后再开计划）

- 服务端 bpz5 HMAC + resolve-line
- 详情合并官方 line_options
- ticket 模式真正解票
