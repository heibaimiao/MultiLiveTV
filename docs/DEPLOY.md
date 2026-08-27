# VPS 部署指南

单台 VPS 部署 Go API + PostgreSQL，前置 Nginx/Caddy 提供 HTTPS。

## 前置条件

- Docker + Docker Compose v2
- 域名（可选，推荐 HTTPS）

## 步骤

### 1. 克隆仓库

```bash
git clone git@github.com:heibaimiao/MultiLiveTV.git
cd MultiLiveTV
```

### 2. 配置环境变量

```bash
cp .env.prod.example .env.prod
# 编辑 .env.prod，设置强密码 JWT_SECRET 与 POSTGRES_PASSWORD
```

### 3. 启动

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

### 4. 验证

```bash
curl https://your-domain/health
# {"status":"ok","db":"ok"}

apps/api-go/scripts/smoke-test.sh https://your-domain
```

### 5. 反向代理（Caddy 示例）

```
your-domain {
    reverse_proxy localhost:8080
}
```

## 资源站配置

编辑 [`apps/api-go/config/sources.json`](../apps/api-go/config/sources.json) 后重建 API 镜像：

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build api
```

## Apple 客户端

在 Xcode 中将 `APIConfig.releaseBaseURL` 改为 `https://your-domain/api/v1`。

## 备份

定期备份 Postgres volume `pgdata`：

```bash
docker compose -f docker-compose.prod.yml exec postgres pg_dump -U multilivetv multilivetv > backup.sql
```
