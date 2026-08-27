# MultiLiveTV Go API

Gin + PostgreSQL + JWT 后端，替代 Supabase / Next.js API。

## 快速开始

```bash
# 仅 VOD API（无需数据库）
cd apps/api-go
go run ./cmd/server

# 完整栈（API + Postgres + Auth）
cd ../..
docker compose up --build
```

API 默认 `http://localhost:8080`

## 路由

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/sources` | 资源站列表 |
| GET | `/api/v1/vod/list` | 分类列表 |
| GET | `/api/v1/vod/detail` | 合并详情 |
| GET | `/api/v1/vod/search` | 跨源搜索 |
| GET | `/api/v1/vod/types` | 分类 |
| GET | `/api/v1/vod/pic` | 海报 |
| GET | `/api/v1/play/parse` | 解析播放地址 |
| POST | `/api/v1/auth/register` | 注册（需 DATABASE_URL） |
| POST | `/api/v1/auth/login` | 登录 |
| POST | `/api/v1/auth/refresh` | 刷新 token |
| GET/POST/DELETE | `/api/v1/user/favorites` | 收藏（JWT） |
| GET/PUT | `/api/v1/user/progress` | 播放进度（JWT） |

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `PORT` | `8080` | 监听端口 |
| `SOURCES_PATH` | `config/sources.json` | MacCMS 源配置 |
| `DATABASE_URL` | — | PostgreSQL 连接串 |
| `JWT_SECRET` | `dev-secret-change-me` | JWT 密钥 |

## 测试

```bash
go test ./...
./scripts/smoke-test.sh http://localhost:8080
```

搜索「鲨笼绝境」应合并为 **1 条**（多资源站 variants）。

## OpenAPI

契约文件：`packages/openapi/openapi.yaml`  
Swagger UI：`http://localhost:8080/swagger/index.html`
