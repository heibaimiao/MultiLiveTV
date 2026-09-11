# 测试文档

## 测试框架

| 区域 | 框架 | 命令 |
| --- | --- | --- |
| Go API | 标准库 `testing` + `net/http/httptest`（handler 测试） | `cd apps/api-go && go test ./...` |
| CI | 同上，Go 1.25 | `.github/workflows/api.yml` job `test` |
| 冒烟 | bash + curl + python3 | `apps/api-go/scripts/smoke-test.sh [BASE]` |
| Apple 逻辑 | Swift 脚本（非 XCTest target） | 见 `clients/apple/scripts/` |
| Web | 少量 `web/lib/__tests__/*.check.ts` | **代码中未发现** 接入 `package.json` test script 的正式 runner（`web/package.json` 无 `test` 脚本） |
| Android | — | **代码中未发现** `*Test.kt` |
| E2E 自动化 | — | **代码中未发现** Playwright / Appium；仅有手工清单 [`E2E.md`](E2E.md) |

Mock：Go 测试对 bpz5 使用 `httptest` 假上游（`TestResolvePlay_TicketViaMockUpstream`）。无独立 mock 框架依赖。

---

## 测试目录与已有用例

### `apps/api-go`

| 文件 | 覆盖 |
| --- | --- |
| `internal/handler/handler_test.go` | 空源 GetSources；搜索缺 wd；ticket 未启用 501；mock 解票；direct 无 sourceId |
| `internal/handler/admin_test.go` | Admin 登录、创建/列出源、清缓存；SourceStore 文件 CRUD |
| `internal/model/maccms_json_test.go` | Flex 数字/字符串 page |
| `internal/model/vod_time_test.go` | `vod_time` 解析 |
| `internal/service/merge/merge_test.go` | 标题归一化、合并键、同片合并、排序 |
| `internal/service/parser/weights_test.go` | 权重优先级与排序、读 JSON |
| `internal/service/bpz5/client_test.go` | ticket 规范化、签名头、选片、enrich、ResolveLine |
| `internal/service/unified/catalog_test.go` | Find / ParentSlug |

**未覆盖（缺失）：** 真实 Postgres 集成测试、JWT 中间件、favorites/progress handler、`GetVodList` fan-out、`GetVodDetail` 全链路、health、CORS。

### Smoke（`scripts/smoke-test.sh`）

对运行中的 API：

1. `/health` 含 `"status":"ok"`
2. `/api/v1/sources` 数量 > 0
3. 搜索「鲨笼绝境」`total==1`
4. 详情 `playSources` 长度 > 0

依赖外网采集站，不稳定时会失败。默认 BASE `http://localhost:8080`。

### Apple 脚本

| 脚本 | 作用 |
| --- | --- |
| `verify-aggregation.swift` | 跨源搜索合并（期望鲨笼绝境 1 组） |
| `verify-client-logic.swift` | 客户端逻辑单测脚本 |
| `verify-downloads.swift` | 下载相关验证 |
| `run-logic-tests.sh` | 包装逻辑测试 |
| `verify-pods-integration.py` | CocoaPods / VLCKit 集成检查 |

**代码中未发现** Xcode Test Target / XCTest。

### Web

`web/lib/__tests__/vodTimeSort.check.ts`、`playLineWeights.check.ts`：检查脚本风格，是否在 CI 运行 **待确认**（workflow 只测 `apps/api-go`）。

---

## E2E.md 与代码差异

[`E2E.md`](E2E.md) 要求 Apple「登录 → 详情页收藏」以及 VPS 改 `APIConfig.swift`。

当前事实：

- Apple **无** 登录 / 收藏 UI
- Apple **无** `APIConfig.swift`

该文件作为手工清单部分 **过时**，不能当作已实现验收项。

---

## 覆盖范围小结

| 能力 | 自动化 | 状态 |
| --- | --- | --- |
| 合并 / 权重 / bpz5 客户端 | 有单元测试 | 已实现 |
| 公开 VOD handler 全接口 | 少量 | 部分实现 |
| Auth / User DB | 无 | 缺失 |
| Admin 部分 | 有登录与源 CRUD | 部分实现 |
| 外网冒烟 | 有脚本，未进 CI | 部分实现 |
| Apple UI | 无 | 缺失 |
| Android | 无 | 缺失 |

CI 在 `apps/api-go/**` 变更时跑 `go test ./...`，**不**跑 smoke，**不**测 Apple/Admin/Android。
