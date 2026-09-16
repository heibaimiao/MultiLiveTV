# 部署文档

仓库内真实部署方式是 **Docker Compose**。Kubernetes / Systemd / PM2：**代码中未发现**。更短的操作清单见既有 [`DEPLOY.md`](DEPLOY.md)。

## 环境

代码 **没有** `dev` / `staging` / `prod` 多套配置文件。能区分的只有：

| 环境 | 如何启动 | 依据 |
| --- | --- | --- |
| 本地纯点播 | `cd apps/api-go && go run ./cmd/server` | README；可不设 `DATABASE_URL` |
| 本地完整栈 | `docker compose up --build` | `docker-compose.yml` |
| 生产 Compose | `docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build` | `DEPLOY.md`、`docker-compose.prod.yml` |

测试环境：**代码中未发现** 独立 compose 或 CI 部署环境。CI 只跑测试并本地 build 镜像（不 push）。

Apple / Android 各有本机构建，不经过上述 Compose。

---

## 部署流程（生产 Compose）

```text
代码
 ↓
cp .env.prod.example .env.prod（填 <SECRET>）
 ↓
docker compose -f docker-compose.prod.yml --env-file .env.prod build
    ├── api：golang:1.25-alpine → alpine 二进制
    └── admin：node:22 构建静态资源 → nginx:alpine
 ↓
启动 postgres（无宿主机端口）+ api + admin
 ↓
Health：GET /health 期望 {"status":"ok","db":"ok"}
 ↓
前置 Caddy/Nginx HTTPS（仓库无配置文件，DEPLOY.md 给了 Caddy 示例）
```

生产 postgres **不**映射 `5432` 到宿主机。api 映射 `${API_PORT:-8080}`，admin 映射 `${ADMIN_PORT:-3001}`。

---

## 服务与端口

| 服务 | 开发端口 | 镜像 / 构建 |
| --- | --- | --- |
| postgres | 5432 | `postgres:16-alpine` |
| api | 8080 | `./apps/api-go` |
| admin | 3001 → 容器 80 | `./apps/admin` |

Admin 容器内 nginx 将 `/api/` 反代到 `http://api:8080/api/`。浏览器访问 `http://localhost:3001` 时，前端 `VITE_API_BASE_URL=/api/v1` 走同源反代。

---

## 启动命令（摘自仓库）

### Go API（无 Docker）

```bash
cd apps/api-go && go run ./cmd/server
```

带管理与数据库时需自行 export `DATABASE_URL`、`ADMIN_USERNAME`、`ADMIN_PASSWORD` 等（见 [06-config.md](06-config.md)）。

### 开发 Compose

```bash
docker compose up --build
```

默认 Admin：`admin` / `admin`（可用宿主 `ADMIN_PASSWORD` 覆盖）。JWT 开发值为 compose 内字符串，生产勿用。

### 生产

```bash
cp .env.prod.example .env.prod
# 编辑密码与 JWT_SECRET
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

验证：

```bash
curl http://localhost:8080/health
apps/api-go/scripts/smoke-test.sh http://localhost:8080
```

`DEPLOY.md` 写的是 `https://your-domain/health`（需已做反代）。

### 管理后台独立开发

```bash
cd apps/api-go
ADMIN_USERNAME=admin ADMIN_PASSWORD=your-pass go run ./cmd/server

cd apps/admin
npm install && npm run dev
```

Vite 端口 3001，`vite.config.ts` 把 `/api` 代理到 `localhost:8080`。

### Apple

```bash
cd clients/apple
xcodegen generate
pod install
open MultiLiveTV.xcworkspace
```

选 scheme `MultiLiveTV-tvOS` 或 `MultiLiveTV-iOS`。必须用 `.xcworkspace`。

**注意：** `DEPLOY.md` 要求改 `APIConfig.releaseBaseURL`。当前 Apple 源码 **无此文件**，客户端直连采集站，改 Go 域名 **不会**改变 Apple 点播流量。

### Android

内嵌聚合，不调 Go API。Gradle Wrapper 8.13，模块 `:core` / `:app` / `:tv`。命令与产物见 [clients/android/README.md](../clients/android/README.md)。

```bash
cd clients/android
./gradlew :core:test
./gradlew :app:installDebug
./gradlew :tv:installDebug
```

### 冻结网页（不作为产品部署路径）

```bash
cd web && npm install && npm run dev
```

---

## Health Check

Compose postgres：`pg_isready`。  
API：`GET /health`。代码中 **没有** Docker `HEALTHCHECK` 指令。

---

## 备份

`DEPLOY.md`：

```bash
docker compose -f docker-compose.prod.yml exec postgres pg_dump -U multilivetv multilivetv > backup.sql
```

卷名 `pgdata`。源站变更还依赖 `sources.json` 文件（compose 挂载该文件）。

---

## CI 与镜像仓库

`.github/workflows/api.yml` 构建 tag `multilivetv-api:ci` 且 `push: false`。**代码中未发现** 推送到 GHCR/Docker Hub 的步骤。

---

## 生产缺口（源码事实）

- compose **未**传入 `BPZ5_HMAC_SECRET`，官方线默认关。
- API Dockerfile **未**打包 `play-line-weights.json`、`unified-categories.json`。
- Admin 3001 建议限制网络（`DEPLOY.md`）；compose 仍默认映射到宿主机。
