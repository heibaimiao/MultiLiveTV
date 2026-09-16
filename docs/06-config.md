# 配置文档

> 密钥类一律写 `<SECRET>`，不记录仓库或环境中的真实值。

## 环境变量（Go API）

来源：`apps/api-go/internal/config/config.go` 的 `Load()`。无 `application.yml`。

| 配置 | 来源 | 是否必须 | 默认值 | 用途 |
| --- | --- | --- | --- | --- |
| `PORT` | env | 否 | `8080` | 监听端口 |
| `DATABASE_URL` | env | 否 | 空 | Postgres DSN；空则关闭用户路由 |
| `JWT_SECRET` | env | 生产建议必须 | `dev-secret-change-me` | 用户 JWT |
| `SOURCES_PATH` | env | 否 | `config/sources.json` | 采集站 JSON |
| `PLAY_LINE_WEIGHTS_PATH` | env | 否 | `config/play-line-weights.json` | 线路权重 |
| `UNIFIED_CATEGORIES_PATH` | env | 否 | `config/unified-categories.json` | 统一分类 |
| `BPZ5_BASE_URL` | env | 否 | `https://bpz5.com` | 搜剧 API 基址 |
| `BPZ5_HMAC_SECRET` | env | 官方线必须 | 空 | HMAC；空则 ticket 关闭 |
| `ADMIN_USERNAME` | env | 管理后台必须 | 空 | 与密码同时非空才挂 admin 路由 |
| `ADMIN_PASSWORD` | env | 管理后台必须 | 空 | 明文比对 |
| `ADMIN_JWT_SECRET` | env | 否 | 回退 `JWT_SECRET` | 管理员 JWT |
| `ADMIN_CORS_ORIGIN` | env | 否 | `http://localhost:3001` | CORS 无 Origin 头时的回落 |
| `GIN_MODE` | env（compose prod） | 否 | 未在 `Load()` 中读取；Gin 自身识别 | `release` |

启动时若当前目录没有 `config/sources.json`，`main.init` 会 `os.Chdir("apps/api-go")`。

权重 / 分类文件缺失：进程继续运行，log 提示使用默认权重或分类不可用。

## Compose / 生产 env 文件

### `docker-compose.yml`（开发）

| 服务 | 变量 | 备注 |
| --- | --- | --- |
| postgres | `POSTGRES_USER/PASSWORD/DB` | 代码写死 `multilivetv` / `multilivetv` / `multilivetv` |
| api | `PORT` `DATABASE_URL` `JWT_SECRET` `SOURCES_PATH` `ADMIN_USERNAME` `ADMIN_PASSWORD` `ADMIN_CORS_ORIGIN` | 未设 `BPZ5_*`、权重/分类 path |
| admin | build arg `VITE_API_BASE_URL=/api/v1` | 无 runtime env |

卷：`pgdata`；api 挂载宿主 `apps/api-go/config/sources.json`。

### `docker-compose.prod.yml`

| 变量 | 是否必须 | 用途 |
| --- | --- | --- |
| `POSTGRES_USER` | 否 | 默认 `multilivetv` |
| `POSTGRES_PASSWORD` | 是（`:?`） | `<SECRET>` |
| `POSTGRES_DB` | 否 | 默认 `multilivetv` |
| `JWT_SECRET` | 是 | `<SECRET>` |
| `ADMIN_USERNAME` | 否 | 默认 `admin` |
| `ADMIN_PASSWORD` | 是 | `<SECRET>` |
| `ADMIN_CORS_ORIGIN` | 否 | 默认 `http://localhost:3001` |
| `API_PORT` | 否 | 宿主机映射，默认 8080 |
| `ADMIN_PORT` | 否 | 默认 3001 |

生产文件 **未** 把 `.env.prod.example` 里的 `BPZ5_BASE_URL` / `BPZ5_HMAC_SECRET` 传入容器。要启用官方线需自行加 environment（**代码中未发现** compose 已接好）。

### `.env.prod.example`

变量名：`POSTGRES_USER` `POSTGRES_PASSWORD` `POSTGRES_DB` `JWT_SECRET` `API_PORT` `ADMIN_USERNAME` `ADMIN_PASSWORD` `ADMIN_PORT` `ADMIN_CORS_ORIGIN` `BPZ5_BASE_URL` `BPZ5_HMAC_SECRET`。

仓库 **无** `.env.example`。

## JSON 配置文件

三端（Go / web / Apple）及 Android assets 同步语义，权威运行时以 Go 进程读到的文件为准。

### `sources.json`（数组）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | int | 源 ID |
| `name` | string | 显示名 |
| `url` | string | MacCMS 基址 |
| `flag` | int | `0` 启用 |
| `jx_url` | string | 解析前缀，可空 |
| `vip_only` | bool | true 则公开 Enabled 排除 |
| `json_parse` | string | 结构体有；**无读取逻辑** |
| `danmaku_api_url` | string | 结构体有；**无读取逻辑** |

当前仓库副本约 **29** 条，均为 `flag=0`。

### `unified-categories.json`

| 字段 | 说明 |
| --- | --- |
| `version` | 版本 |
| `generated_at` | 生成时间 |
| `aliases` | 分类别名（公开 API `Public()` **不返回** 此字段） |
| `defaultSlug` | 默认 slug，空则代码设为 `movie` |
| `tree[].slug/label/sources/children` | `sources` 为 `sourceId 字符串 → type_id` |

公开接口只返回 `version`、`defaultSlug`、`tree` 的 slug/label/children（不含 sources 映射）。

### `play-line-weights.json`

`version`、`defaultWeight`、`byPlayFrom`、`byProviderId`、`bySourceId`。  
权重优先级：`providerId` > `playFrom` > `sourceId` > `defaultWeight`。

### 客户端 `lives.json`

`id`、`name`、`url`、`flag`。Apple 与 Android 各有一份包内副本。

## 前端构建变量

| 配置 | 来源 | 用途 |
| --- | --- | --- |
| `VITE_API_BASE_URL` | Admin Vite / Docker build arg | 默认 `/api/v1` |
| Android 源站 JSON | `clients/android/core/src/main/resources/` | 直连采集站；无 Go `BASE_URL` |
| `web/.env.local` | 本地文件 | `BPZ5_*`（冻结网页）；**不要提交密钥** |

## Docker 镜像

`apps/api-go/Dockerfile`：

- build：`golang:1.25-alpine`，`CGO_ENABLED=0`，`./cmd/server`
- runtime：`alpine:3.20` + ca-certificates
- **仅 COPY** `config/sources.json`（不含 weights / categories）

`apps/admin/Dockerfile`：Node 22 构建 + `nginx:alpine`。`nginx.conf` 反代 `/api/` → `http://api:8080/api/`。

## CI

`.github/workflows/api.yml`：Go 1.25 `go test ./...`；随后 build `apps/api-go` tag `multilivetv-api:ci`，`push: false`。

## Kubernetes / 独立 Nginx 网关

**代码中未发现** K8s manifest。文档 [`DEPLOY.md`](DEPLOY.md) 建议前置 Caddy/Nginx 做 HTTPS，仓库内无该配置文件（Admin 容器内 nginx 除外）。
