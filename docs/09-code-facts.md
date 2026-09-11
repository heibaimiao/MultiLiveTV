# 代码事实清单

后续改代码时优先核对本表。状态：`已确认` = 源码存在；`待确认` = 运行时行为未在本机验证；`代码中未发现` = 扫描无实现。

| 类型 | 事实 | 来源代码 | 状态 |
| --- | --- | --- | --- |
| 产品 | 名称 MultiLiveTV；MacCMS 多源点播聚合 | `README.md` | 已确认 |
| 语言 | Go 1.25 | `apps/api-go/go.mod` | 已确认 |
| HTTP | Gin 1.10，入口 `cmd/server/main.go` | 同上 | 已确认 |
| 路由 | 完整栈 31 条（含 health/swagger） | `main.go` | 已确认 |
| API | GET `/health` | `handler/health.go` | 已确认 |
| API | GET `/swagger/*any` | `main.go` gin-swagger | 已确认（产物待确认） |
| API | GET `/api/v1/sources` | `handler/vod.go` GetSources | 已确认 |
| API | GET `/api/v1/vod/list` | GetVodList | 已确认 |
| API | GET `/api/v1/vod/detail` | GetVodDetail | 已确认 |
| API | GET `/api/v1/vod/search` | SearchVod | 已确认 |
| API | GET `/api/v1/vod/types` | GetVodTypes | 已确认 |
| API | GET `/api/v1/vod/categories` | GetUnifiedCategories | 已确认 |
| API | GET `/api/v1/vod/pic` | GetVodPic | 已确认 |
| API | GET `/api/v1/play/parse` | ParsePlay | 已确认 |
| API | POST `/api/v1/play/resolve` | ResolvePlay | 已确认 |
| API | POST `/api/v1/auth/register` | `handler/auth.go` | 已确认（需 DB） |
| API | POST `/api/v1/auth/login` | Login | 已确认（需 DB） |
| API | POST `/api/v1/auth/refresh` | Refresh | 已确认（需 DB） |
| API | GET/POST/DELETE `/api/v1/user/favorites` | AuthHandler | 已确认（JWT+DB） |
| API | GET/PUT `/api/v1/user/progress` | AuthHandler | 已确认（JWT+DB） |
| API | POST `/api/v1/admin/login` | `handler/admin.go` | 已确认（需 Admin env） |
| API | CRUD `/api/v1/admin/sources` + test | AdminHandler | 已确认 |
| API | GET/DELETE `/api/v1/admin/users` + stats | AdminHandler | 已确认 |
| API | GET status / POST cache/clear / GET logs | AdminHandler | 已确认 |
| OpenAPI | 14 path，无 admin/health | `packages/openapi/openapi.yaml` | 已确认 |
| DB | Postgres，可选 | `repository/db.go`、compose | 已确认 |
| DB | AutoMigrate User/Favorite/WatchProgress/RefreshToken | `repository/db.go` | 已确认 |
| 表 | `users` | `model.User` | 已确认 |
| 表 | `favorites` unique (user_id, merge_key) 按 tag | `model.Favorite` | 已确认 |
| 表 | `watch_progress` | `model.WatchProgress` | 已确认（复合唯一待确认） |
| 表 | `refresh_tokens` | `model.RefreshToken` | 已确认 |
| SQL | `migrations/001_init.sql` goose 风格且 favorites 缺逗号 | 该文件 | 已确认 |
| 迁移执行 | 进程不跑 goose | 全库无调用 | 代码中未发现 |
| Redis | — | — | 代码中未发现 |
| Kafka/MQ | — | — | 代码中未发现 |
| WebSocket | — | — | 代码中未发现 |
| 定时任务 | 无 cron；仅 cache TTL 5min | `category/service.go` | 代码中未发现调度器 |
| 认证用户 | JWT HS256 15min + refresh 7d bcrypt12 | `service/auth/auth.go` | 已确认 |
| 认证管理 | 明文 env + JWT 8h role=admin | `service/admin/auth.go` | 已确认 |
| 源启用 | flag==0 && !vip_only | `config/sources.go` Enabled | 已确认 |
| 第三方 | MacCMS GET ac=list/detail | `service/maccms/client.go` 超时 15s | 已确认 |
| 第三方 | jx_url GET | `parser.ParsePlayAddress` | 已确认 |
| 第三方 | bpz5 HMAC /v1 catalog + resolve-line | `service/bpz5` | 已确认 |
| 配置 | 仅环境变量 + 三个 JSON 路径 | `config.Load` | 已确认 |
| Docker | api 只 COPY sources.json | `apps/api-go/Dockerfile` | 已确认 |
| Compose | 未注入 BPZ5_* | `docker-compose.yml` prod 同 | 已确认 |
| CI | go test + docker build push:false | `.github/workflows/api.yml` | 已确认 |
| Apple | 直连 MacCMS，不调 Go | `clients/apple/README.md`、MacCMSClient | 已确认 |
| Apple | Tab：首页/直播/搜索/下载 | `MultiLiveTVApp.swift` MainTabView | 已确认 |
| Apple | 无登录收藏 | Swift 源 | 代码中未发现 |
| Apple | 无 APIConfig.swift | 全树搜索 | 代码中未发现 |
| 直播 API | Go 无直播路由 | `main.go` | 代码中未发现 |
| Android | Retrofit 调 Go；无播放器；无 Gradle | `clients/android` | 已确认（部分实现） |
| Admin UI | Vite React :3001 | `apps/admin` | 已确认 |
| web | Next.js 已冻结 | `web/ARCHIVED.md` | 已确认 |
| PlaySource | JSON 字段 `name` 非 `label` | `model.PlaySource` | 已确认 |
| 未实现字段 | json_parse、danmaku_api_url 无读取 | 仅 `model.Source` | 已确认 |
| CORS | 回写请求 Origin | `CORSWithOrigin` | 已确认 |
| 错误信封 | `{"error": string}` 非 code/data | handlers | 已确认 |
| 源数量 | sources.json 29 条 | 配置文件 | 已确认 |
| 并发 | unified maxFanout=8 | `unified/list.go` | 已确认 |
| 详情变体上限 | maxVariants=16 | `merge/merge.go` | 已确认 |
| bpz5 匹配 | 分数阈值 80 | `bpz5/enrich.go` | 已确认 |
| 日志缓冲 | 200 条内存 | `NewRequestLogBuffer(200)` | 已确认 |
| K8s | — | — | 代码中未发现 |
| 支付/订单 | — | — | 代码中未发现 |

## 客户端 vs API

| 能力 | Go API | Apple | Android | Admin |
| --- | --- | --- | --- | --- |
| 点播列表/搜索/详情 | 有 | 本地实现 | 调 API | 无 |
| play/resolve | 有 | 本地 jx | 无 | 无 |
| 用户收藏进度 | 有 | 无 | 无 | 管用户不登录用户端 |
| 直播 | 无 | 有 | 无 | 无 |
| 下载 | 无 | 有 | 无 | 无 |

## 文档交叉引用（仓库原有，未删除）

| 文件 | 用途 |
| --- | --- |
| `docs/maccms-api.md` | 采集协议 |
| `docs/souju-playback-api.md` | bpz5 私有接口 |
| `docs/DEPLOY.md` | 短部署指南（含过时 Apple APIConfig） |
| `docs/E2E.md` | 手工验收（含过时登录项） |
| `docs/superpowers/*` | 历史设计/计划 |
