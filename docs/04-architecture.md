# 系统架构

> 描述当前仓库真实拓扑，不套用未使用的中间件。

## 1. 系统架构

```text
┌─────────────────────────────────────────────────────────┐
│ Apple tvOS / iPadOS                                      │
│  SourceStore / MacCMSClient / VodMerge / PlayParser      │
│  LiveStore (M3U) / DownloadManager / VLCKit / AVPlayer   │
└────────────┬────────────────────────────────────────────┘
             │ HTTPS 直连第三方
             ▼
     MacCMS 采集站（sources.json）
             ▲
             │ HTTPS 直连第三方
┌────────────┴──────────────┐     ┌─────────────────┐
│ Android Pad `:app` / TV `:tv`│     │ Admin SPA :3001 │
│ OkHttp + Media3            │     │ Vite / nginx    │
└───────────────────────────┘     └────────┬────────┘
                                           │ /api → api:8080
                                           ▼
┌─────────────────────────────────────────────────────────┐
│ Go Gin API :8080                                         │
│ middleware: CORSWithOrigin, RequestLogger                │
│ handler → service (maccms/merge/unified/parser/bpz5)     │
│         → 可选 GORM / Postgres                           │
│ SourceStore 读写 JSON 文件                               │
└───────┬──────────────────────────────┬──────────────────┘
        │                              │
        ▼                              ▼
  PostgreSQL 16                 bpz5.com（可选 HMAC）
  （用户/收藏/进度）              各源 jx_url（可选）
```

**代码中未发现：** API Gateway 产品、Redis、Kafka、ES、对象存储 SDK。

管理后台 Docker 内 nginx 只反代 `/api/` 到 `http://api:8080/api/`，不是独立网关。

## 2. 模块架构

### 2.1 Go API（`apps/api-go`）

```text
cmd/server/main.go
  ├── config.Load（环境变量）
  ├── SourceStore（JSON）
  ├── parser.LoadWeightsFile
  ├── unified.LoadFile
  ├── repository.Connect（可选）
  └── gin
        ├── handler/vod.go      公开点播
        ├── handler/auth.go     用户（需 DB）
        ├── handler/admin.go    管理（需环境变量）
        └── handler/health.go
```

包职责：

| 包 | 作用 |
| --- | --- |
| `internal/config` | 环境变量、`SourceStore` |
| `internal/handler` | HTTP 入参出参 |
| `internal/middleware` | CORS、用户 JWT、Admin JWT、请求日志 |
| `internal/model` | JSON / GORM 结构体 |
| `internal/repository` | **仅** `Connect` + AutoMigrate；无独立 DAO |
| `internal/service/maccms` | 采集站 HTTP |
| `internal/service/merge` | 标题合并、详情合并 |
| `internal/service/unified` | slug 目录与跨源 fan-out |
| `internal/service/category` | 单源分类树缓存、父子 type 列表 |
| `internal/service/parser` | 拆线路、权重、jx 解析 |
| `internal/service/bpz5` | 搜剧 catalog / resolve-line |
| `internal/service/auth` | 用户 bcrypt + JWT |
| `internal/service/admin` | 管理员明文登录 + JWT |

用户收藏 / 进度在 **handler 内直接使用 `*gorm.DB`**，没有 Repository 层。

### 2.2 Apple

```text
MultiLiveTVApp
  VodService（门面）
  DownloadManager
  DeepLinkRouter
    RootView / MainTabView
      HomeView / LiveView / SearchView / DownloadsView
      DetailView / PlayerView
```

资源：`sources.json`、`unified-categories.json`、`play-line-weights.json`、`lives.json`。

### 2.3 Admin

React Router：Login → Layout（Dashboard / Sources / Users / Logs）。Token 存 `localStorage` key `admin_token`。

### 2.4 Android

Gradle 多模块：`:core` 业务、`:app` 平板、`:tv` 电视。OkHttp 直连采集站，Media3 播放。详见 [clients/android/README.md](../clients/android/README.md)。

### 2.5 web/

已冻结的 Next.js，自带 `app/api/*` 路由，与 Go **平行实现历史逻辑**，不是当前主路径。

## 3. 数据流

### 点播元数据

```text
MacCMS JSON（ac=list / detail）
  → model.VodItem / MacCmsListResponse（含 FlexString 兼容）
  → MergeableVodItem（带 sourceId）
  → MergedVodItem（variants + primarySourceId）
  → HTTP JSON
```

### 播放地址

```text
vod_play_from $$$ 分隔
vod_play_url  $$$ 线路、# 分集、$ 名称与 URL
  → []PlaySource（key / weight / mode / episodes）
  → 客户端选一条
  → ParsePlayAddress 或 bpz5.ResolveLine
  → { url, parsed }
```

## 4. 请求链路

```text
Client
 ↓
Gin（无独立 Gateway）
 ↓
CORS / RequestLogger
 ↓
（/user/*）JWT 中间件 或（/admin/* 除 login）AdminJWT
 ↓
Handler 参数校验
 ↓
Service（多数点播无 DB）
 ↓
http.Client 15s → MacCMS  或  bpz5 40s  或  GORM
 ↓
JSON 响应（错误体多为 {"error":"..."}）
```

## 5. 异步链路

**代码中未发现** 消息队列或后台 worker。

存在的并发：

- `unified.FetchListBySlug`：worker pool，`maxFanout = 8`
- `bpz5.EnrichOfficialPlaySources`：goroutine + 5s 超时；内部 `enrichConcurrency = 4`
- Apple：`async` 网络与下载 URLSession（含后台 session）

分类缓存与请求日志在进程内存，**不跨实例共享**。

## 6. 消息链路

**代码中未发现** Kafka / RabbitMQ / NATS / WebSocket。

## 7. 外部依赖

| 依赖 | 协议 | 超时 | 失败策略 |
| --- | --- | --- | --- |
| MacCMS `source.url` | GET query `ac/pg/t/wd/ids` | 15s | 列表：跳过源或 200 空列表；详情：502 |
| `source.jx_url` + QueryEscape(url) | GET | 15s | 回退原始 URL，`parsed: false` |
| bpz5 `/v1/*` | GET/POST + HMAC 头 | Client 40s；enrich 另 5s | enrich 失败则只用 MacCMS 线；resolve 502 |

MacCMS 约定详见 [`maccms-api.md`](maccms-api.md)。bpz5 详见 [`souju-playback-api.md`](souju-playback-api.md)。

## 8. 第三方服务

- **bpz5.com / souju：** 非 MacCMS。密钥只应在服务端。默认 `BPZ5_HMAC_SECRET` 空则 `Enabled()==false`。
- **playm3u8 等解析站：** 出现在 `sources.json` 的 `jx_url`，不是独立配置项。
- **直播 M3U 主机：** Apple `lives.json` 的 `url` 字段。

## 9. 认证体系

| 体系 | 算法 | Access TTL | Refresh | 存储 |
| --- | --- | --- | --- | --- |
| 用户 | HS256，claims `user_id`+`email` | 15 分钟 | 32 字节 hex，DB SHA-256，7 天 | `refresh_tokens` |
| 管理员 | HS256，claims `role=admin`+`username` | 8 小时 | 无 | 无 |

用户密码：bcrypt cost 12。管理员密码：与环境变量明文相等。

中间件要求 `Authorization: Bearer <token>`。缺头 → `{"error":"missing token"}`；无效 → `invalid token`。

Swagger 挂载路径 **无认证**。

## 10. 权限体系

无 RBAC 表。规则是路由级：

- 公开：`/health`、`/swagger/*`、`/api/v1/sources`、`/vod/*`、`/play/*`、`/auth/*`、`POST /admin/login`
- 用户 JWT：`/api/v1/user/*`
- 管理员 JWT：`/api/v1/admin/*` 其余

`vip_only` 源：公开 `ByID` / `Enabled` 不可见；Admin `ByIDAdmin` / `All` 可见。没有「VIP 用户可播」的接口。
