# MultiLiveTV Admin

独立管理后台，端口 **3001**。

## 功能

- 资源站 CRUD + 连通性测试
- 用户列表/统计/删除
- 系统状态、清缓存、请求日志

## 开发

```bash
# 终端 1：API（需配置管理员账号）
cd apps/api-go
ADMIN_USERNAME=admin ADMIN_PASSWORD=admin go run ./cmd/server

# 终端 2：管理前端
cd apps/admin
npm install
npm run dev
```

访问 http://localhost:3001 ，默认代理 `/api` → `localhost:8080`。

## Docker

```bash
docker compose up --build
# Admin: http://localhost:3001
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `VITE_API_BASE_URL` | API 基址，默认 `/api/v1`（Docker 内由 nginx 反代） |

API 侧需设置 `ADMIN_USERNAME` / `ADMIN_PASSWORD`。
