# MultiLiveTV

MacCMS 多源聚合点播：Go 后端 + Apple TV / iPad 原生客户端（可选 Admin 与 Android Pad/TV）。

仅供个人学习研究。第三方采集站不稳定，需自行维护 `sources.json`。

## 功能

- 跨源统一分类、搜索合并、详情多线路
- 线路权重排序；`jx_url` 解析；可选 bpz5 官方 ticket 解票（服务端）
- Apple：首页 / 直播 / 搜索 / 下载 / 播放（**直连采集站，不依赖 Go API**）
- Android Pad / TV：首页 / 直播 / 搜索 / 播放（直连采集站，对标 iPad / tvOS）
- 可选 Postgres：注册、JWT、收藏、进度
- 可选管理后台：源站 CRUD、用户、日志

详细产品说明：[docs/01-product.md](docs/01-product.md)（现状）· [docs/11-vod-aggregation-prd.md](docs/11-vod-aggregation-prd.md)（多源聚合目标）

## 技术栈

Go 1.25 + Gin + GORM + PostgreSQL 16（可选）· SwiftUI tvOS/iPadOS 17 · Admin：Vite/React · Android Pad/TV：Kotlin 2.0 + Compose

架构：[docs/04-architecture.md](docs/04-architecture.md) · 总览：[docs/00-project-overview.md](docs/00-project-overview.md)

## 项目结构

```text
apps/api-go/          Gin API
apps/admin/           管理后台 :3001
clients/apple/        tvOS + iPad（内嵌聚合）
clients/android/      Android Pad `:app` + TV `:tv`（内嵌聚合）
packages/openapi/     OpenAPI（不含 Admin）
web/                  已冻结的 Next.js
docs/                 产品与技术文档
```

## 快速启动

```bash
# 仅 VOD（无需数据库）
cd apps/api-go && go run ./cmd/server

# API + Postgres + Admin
docker compose up --build
```

- API：http://localhost:8080  
- 管理后台：http://localhost:3001（Compose 默认 `admin` / `admin`）  
- Smoke：`apps/api-go/scripts/smoke-test.sh`

Apple：见 [clients/apple/README.md](clients/apple/README.md)（`xcodegen generate && pod install`，打开 `.xcworkspace`）。

Android：见 [clients/android/README.md](clients/android/README.md)（`./gradlew :app:installDebug` 或 `:tv:installDebug`）。

## 配置

环境变量与 JSON 说明：[docs/06-config.md](docs/06-config.md)  
采集协议：[docs/maccms-api.md](docs/maccms-api.md) · EHR663 测速源：[docs/ehr663-sources-api.md](docs/ehr663-sources-api.md)  
bpz5 解票：[docs/souju-playback-api.md](docs/souju-playback-api.md)

编辑 [`apps/api-go/config/sources.json`](apps/api-go/config/sources.json)（`flag: 0` 启用）。Apple 使用包内同名文件。

## API

契约草稿：[`packages/openapi/openapi.yaml`](packages/openapi/openapi.yaml)  
逐接口说明（含 Admin）：[docs/02-api.md](docs/02-api.md)

| 路径 | 说明 |
| --- | --- |
| `GET /api/v1/vod/list` | 分类列表（`cat` 为统一 slug） |
| `GET /api/v1/vod/search` | 跨源搜索 |
| `GET /api/v1/vod/detail` | 合并详情 + 线路 |
| `POST /api/v1/play/resolve` | 取播 |
| `POST /api/v1/auth/login` | 登录（需 DATABASE_URL） |

## 数据库

可选 4 表：`users`、`favorites`、`watch_progress`、`refresh_tokens`。见 [docs/03-database.md](docs/03-database.md)。

## 部署

[docs/07-deployment.md](docs/07-deployment.md) · 短步骤 [docs/DEPLOY.md](docs/DEPLOY.md)

```bash
cp .env.prod.example .env.prod
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

## 测试

```bash
cd apps/api-go && go test ./...
cd clients/android && ./gradlew :core:test
```

说明与缺口：[docs/08-testing.md](docs/08-testing.md) · 手工清单 [docs/E2E.md](docs/E2E.md)

## 开发规范

- 改接口以 `main.go` 与 handler 为准，并同步 OpenAPI / [docs/02-api.md](docs/02-api.md)
- 事实核对：[docs/09-code-facts.md](docs/09-code-facts.md)
- 代码链路：[docs/05-code-flow.md](docs/05-code-flow.md)
- 不要把 `BPZ5_HMAC_SECRET` 下发客户端

## 文档索引

```text
docs/
├── 00-project-overview.md
├── 01-product.md
├── 02-api.md
├── 03-database.md
├── 04-architecture.md
├── 05-code-flow.md
├── 06-config.md
├── 07-deployment.md
├── 08-testing.md
├── 09-code-facts.md
└── 10-documentation-audit.md
```
