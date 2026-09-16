# 项目总览

> 依据仓库当前代码生成。无法从代码确认的内容已标明。  
> 生成日期：2026-09-04。

## 项目定位

**MultiLiveTV** 是一套 **MacCMS 多源点播聚合** 系统：把多个第三方苹果 CMS（MacCMS）采集站的影片目录合成统一分类与搜索结果，再按线路权重选线播放。

定位不是自建片库，也不是内容分发平台。片源、海报、播放地址全部来自第三方采集站；本仓库负责聚合、合并、解析与客户端展示。

根 README 原文：「仅供个人学习研究使用。第三方采集站可能不稳定，需自行维护源配置。」

## 技术栈

| 层 | 技术 | 来源 |
| --- | --- | --- |
| 后端 | Go 1.25、Gin 1.10、GORM 1.25、PostgreSQL 驱动 | `apps/api-go/go.mod` |
| 数据库 | PostgreSQL 16（可选；无则点播仍可用） | `docker-compose.yml`、`repository.Connect` |
| 用户认证 | JWT HS256 + bcrypt(12) + SHA-256 refresh | `internal/service/auth` |
| 管理认证 | 环境变量明文账号 + JWT HS256（8h） | `internal/service/admin` |
| Apple 客户端 | SwiftUI、XcodeGen、Swift 5.9、iOS/tvOS 17、VLCKit 3.6.0 | `clients/apple/project.yml`、Podfile.lock |
| Android 客户端 | Kotlin 2.0 + Compose + Gradle 8.13（`:core` / `:app` / `:tv`） | `clients/android/` |
| 管理后台 | Vite 6、React 19、Tailwind 4、nginx 静态托管 | `apps/admin/package.json` |
| API 契约 | OpenAPI 3.0.3（未覆盖 Admin） | `packages/openapi/openapi.yaml` |
| 网页端 | Next.js 15（**已冻结**） | `web/ARCHIVED.md` |
| 部署 | Docker Compose（dev / prod） | `docker-compose.yml`、`docker-compose.prod.yml` |
| CI | GitHub Actions：`go test` + Docker build（不 push） | `.github/workflows/api.yml` |

**代码中未发现：** Redis、Kafka、其它 MQ、Elasticsearch、OSS SDK、Kubernetes、WebSocket、定时任务框架。

## 功能模块

| 模块 | 实现位置 | 状态 |
| --- | --- | --- |
| 多源点播聚合（列表 / 搜索 / 详情） | Go API + Apple 本地同等逻辑 | 已实现 |
| 统一分类（slug） | `unified-categories.json` + `service/unified` | 已实现 |
| 播放线路权重与解析 | `play-line-weights.json` + `service/parser` | 已实现 |
| bpz5 官方线合并与解票 | `service/bpz5`，需 `BPZ5_HMAC_SECRET` | 已实现（默认关闭） |
| 用户注册 / 登录 / 收藏 / 进度 | Go API + Postgres | 已实现（需 `DATABASE_URL`） |
| 管理后台（源站 / 用户 / 日志） | `apps/admin` + `/api/v1/admin/*` | 已实现（需 Admin 环境变量） |
| Apple 点播浏览与播放 | `clients/apple` 直连采集站 | 已实现 |
| Apple 直播（M3U） | `LiveService` + `lives.json` | 已实现 |
| Apple 下载 | `DownloadManager` 等 | 已实现 |
| Android 浏览 / 搜索 / 详情 / 播放 / 直播 | 直连采集站；Media3；不调 Go | 已实现 |
| 用户登录 UI（Apple / Android） | — | 代码中未发现 |
| Next.js 网页 | `web/` | 已冻结 |
| 弹幕 `danmaku_api_url`、`json_parse` | 仅出现在 `Source` 结构体 | 未实现（无读取逻辑） |

## 系统架构

```text
Apple / Android 客户端（内嵌 sources.json）  ──直连──►  第三方 MacCMS 采集站
                                                     ▲
Admin / curl                                         │
        │                                            │
        ▼                                            │
   Go API :8080  ──代理 / 聚合───────────────────────┘
        │
        ├── 可选 Postgres（用户 / 收藏 / 进度 / refresh）
        ├── 可选 bpz5.com（HMAC 搜剧 / 解票）
        └── 可选 jx_url 解析站（源配置字段）
```

Apple **不依赖** Go API。Android Pad/TV 同样直连采集站，不调 Go API。管理后台依赖 Go API。

## 核心接口数量

在 `apps/api-go/cmd/server/main.go` 注册的 HTTP 路由：

| 分组 | 数量 | 启用条件 |
| --- | --- | --- |
| 健康检查 + Swagger UI | 2 | 始终 |
| 点播 / 播放（公开） | 9 | 始终 |
| 用户认证与数据 | 8 | `DATABASE_URL` 非空且连接成功 |
| 管理后台 | 12 | `ADMIN_USERNAME` 与 `ADMIN_PASSWORD` 均非空 |
| **合计** | **31** | 完整栈全部挂载 |

`packages/openapi/openapi.yaml` 记录 **14 条 path**（含多 method），**不含** `/health`、`/swagger`、全部 `/admin/*`。

## 数据表数量

运行时由 GORM `AutoMigrate` 创建 **4 张表**：

- `users`
- `favorites`
- `watch_progress`
- `refresh_tokens`

采集站、分类、线路权重 **不是数据库表**，而是 JSON 文件。

`apps/api-go/migrations/001_init.sql` 存在 goose 风格 SQL，**运行时未被调用**。

## 外部依赖

| 依赖 | 用途 | 配置 |
| --- | --- | --- |
| MacCMS 采集站（`sources.json`，当前 29 条） | 列表 / 搜索 / 详情 | `flag=0` 且 `vip_only=false` 才对公开 API 启用 |
| 各源 `jx_url` | 将播放页 URL 解析为直链 | 源字段；空则不解析 |
| bpz5.com | 官方 ticket 线路搜索与解票 | `BPZ5_BASE_URL`、`BPZ5_HMAC_SECRET` |
| 直播 M3U | `lives.json` 中的播放列表 URL | Apple / Android 客户端 |

## 当前实现情况

- Go API 可无数据库运行纯点播；Docker Compose 开发栈默认带 Postgres + Admin。
- Apple 是功能最完整的用户端（首页、直播、搜索、下载、播放）。
- Android 是完整 Gradle 工程（`:core` / `:app` / `:tv`），直连采集站，命令见 [clients/android/README.md](../clients/android/README.md)。
- `web/` 已归档，目录仍可 `npm run dev`，主 README 标明冻结。
- Docker 镜像只 COPY `config/sources.json`；compose 未注入 `BPZ5_*`、未挂载权重 / 分类 JSON（容器内走默认路径，文件可能缺失，进程用内置默认权重并打 log）。

## 已发现的问题

1. **Swagger UI 已挂载，但仓库无 `swag` 生成的 `docs` 包**，`/swagger/index.html` 实际内容待确认（可能为空或报错）。
2. **OpenAPI 未覆盖 Admin 全部接口**；也未给出多数响应 schema。
3. **`migrations/001_init.sql` 的 `favorites` 表在 `created_at` 与 `UNIQUE` 之间缺逗号**，且 goose 未被调用。
4. **`WatchProgress` 的 GORM tag** 只在 `progress_key` 上声明 `uniqueIndex:idx_user_progress`，`user_id` 未参与该复合索引；与 SQL 文件中的 `UNIQUE(user_id, progress_key)` 不一致。实际库结构以 AutoMigrate 为准。
5. **`docs/E2E.md` / `docs/DEPLOY.md` 提到 Apple `APIConfig.swift` 与「登录 → 收藏」**；当前 Apple 树内 **无** `APIConfig.swift`，也 **无** 登录 / 收藏 UI。
6. **CORS `CORSWithOrigin`**：请求带 `Origin` 时直接回写该 Origin（非白名单）。
7. **`Source.json_parse` / `danmaku_api_url`** 无业务读取。
8. **生产 compose 未传递 `BPZ5_HMAC_SECRET`**，官方线解票在默认部署中关闭。
9. **单源列表接口**在上游失败时仍可能返回 HTTP 200 + 空列表（`emptyListResponse`），错误写在 `msg`。

## 待完善事项

- 将 OpenAPI 与 Admin、`/health` 对齐，并补全响应 schema。
- Docker 镜像纳入 `play-line-weights.json`、`unified-categories.json`，compose 注入 `BPZ5_*`（若需要官方线）。
- 明确 goose migration 是否弃用，或修复 SQL 并接入启动流程。
- 端侧用户登录 / 收藏：仅 API 已实现，Apple / Android **代码中未发现** 调用。
- 修正 E2E / DEPLOY 中过时的 Apple API 客户端描述。
