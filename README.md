# MultiLiveTV

MacCMS 多源聚合点播 — **Go 后端 + Apple TV / iPad 原生客户端**。

## 架构

```
clients/apple/     SwiftUI（tvOS + iPadOS）
apps/api-go/       Gin + PostgreSQL + JWT
packages/openapi/  API 契约
web/               已归档的 Next.js 网页（冻结）
```

## 快速开始

### Go API

```bash
# 仅 VOD（无需数据库）
cd apps/api-go && go run ./cmd/server

# 完整栈（API + Postgres + Auth）
docker compose up --build
```

API：`http://localhost:8080`  
Smoke 测试：`apps/api-go/scripts/smoke-test.sh`

### Apple 客户端

见 [`clients/apple/README.md`](clients/apple/README.md)。

```bash
cd clients/apple
xcodegen generate   # 需安装 XcodeGen
open MultiLiveTV.xcodeproj
```

## API 路由

| 路径 | 说明 |
|------|------|
| `GET /api/v1/vod/list` | 分类列表 |
| `GET /api/v1/vod/search` | 跨源搜索（合并） |
| `GET /api/v1/vod/detail` | 合并详情 + 线路 |
| `GET /api/v1/play/parse` | 播放地址解析 |
| `POST /api/v1/auth/login` | 登录（需 DATABASE_URL） |
| `GET /api/v1/user/favorites` | 收藏（JWT） |

完整契约：[`packages/openapi/openapi.yaml`](packages/openapi/openapi.yaml)

## 配置资源站

编辑 [`apps/api-go/config/sources.json`](apps/api-go/config/sources.json)（`flag: 0` 启用）。

## 部署

见 [`docs/DEPLOY.md`](docs/DEPLOY.md)。

## 说明

仅供个人学习研究使用。第三方采集站可能不稳定，需自行维护源配置。
