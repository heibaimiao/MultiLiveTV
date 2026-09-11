# API 文档

> 以 `apps/api-go/cmd/server/main.go` 与 handler 源码为准。  
> OpenAPI：`packages/openapi/openapi.yaml`（**不含** Admin、`/health`、`/swagger`）。  
> 错误体默认：`{"error": "<string>"}`。**没有**统一的 `code/message/data` 信封。

基址：`http://localhost:8080`。业务前缀：`/api/v1`。

全局中间件：`CORSWithOrigin`、`RequestLogger`（内存 200 条）。

条件挂载：

- 用户接口：`DATABASE_URL` 连接成功
- 管理接口：`ADMIN_USERNAME` 与 `ADMIN_PASSWORD` 均非空

---

## 接口总览

| Method | URL | 功能 | 权限 | 状态 |
| --- | --- | --- | --- | --- |
| GET | `/health` | 健康检查 | 公开 | 已实现 |
| GET | `/swagger/*any` | Swagger UI | 公开 | 部分实现（无 swag 产物，UI 内容待确认） |
| GET | `/api/v1/sources` | 启用采集站列表 | 公开 | 已实现 |
| GET | `/api/v1/vod/list` | 影片列表（统一分类或单源） | 公开 | 已实现 |
| GET | `/api/v1/vod/detail` | 合并详情 + 线路 | 公开 | 已实现 |
| GET | `/api/v1/vod/search` | 跨源搜索合并 | 公开 | 已实现 |
| GET | `/api/v1/vod/types` | 单源分类列表 | 公开 | 已实现 |
| GET | `/api/v1/vod/categories` | 统一分类树（公开形状） | 公开 | 已实现 |
| GET | `/api/v1/vod/pic` | 海报 URL | 公开 | 已实现 |
| GET | `/api/v1/play/parse` | jx_url 解析（query） | 公开 | 已实现 |
| POST | `/api/v1/play/resolve` | 统一取播 | 公开 | 已实现 |
| POST | `/api/v1/auth/register` | 注册 | 公开 | 已实现（需 DB） |
| POST | `/api/v1/auth/login` | 登录 | 公开 | 已实现（需 DB） |
| POST | `/api/v1/auth/refresh` | 刷新 Token | 公开 | 已实现（需 DB） |
| GET | `/api/v1/user/favorites` | 收藏列表 | 用户 JWT | 已实现（需 DB） |
| POST | `/api/v1/user/favorites` | 添加收藏 | 用户 JWT | 已实现（需 DB） |
| DELETE | `/api/v1/user/favorites` | 删除收藏 | 用户 JWT | 已实现（需 DB） |
| GET | `/api/v1/user/progress` | 观看进度 | 用户 JWT | 已实现（需 DB） |
| PUT | `/api/v1/user/progress` | 写入进度 | 用户 JWT | 已实现（需 DB） |
| POST | `/api/v1/admin/login` | 管理员登录 | 公开 | 已实现（需 Admin 启用） |
| GET | `/api/v1/admin/sources` | 全部源（含禁用） | 管理员 JWT | 已实现 |
| POST | `/api/v1/admin/sources` | 创建源 | 管理员 JWT | 已实现 |
| PUT | `/api/v1/admin/sources/:id` | 更新源 | 管理员 JWT | 已实现 |
| DELETE | `/api/v1/admin/sources/:id` | 删除源 | 管理员 JWT | 已实现 |
| POST | `/api/v1/admin/sources/:id/test` | 测采集站 | 管理员 JWT | 已实现 |
| GET | `/api/v1/admin/users` | 用户分页 | 管理员 JWT | 已实现 |
| GET | `/api/v1/admin/users/stats` | 用户统计 | 管理员 JWT | 已实现 |
| DELETE | `/api/v1/admin/users/:id` | 删除用户 | 管理员 JWT | 已实现 |
| GET | `/api/v1/admin/system/status` | 系统状态 | 管理员 JWT | 已实现 |
| POST | `/api/v1/admin/system/cache/clear` | 清分类缓存 | 管理员 JWT | 已实现 |
| GET | `/api/v1/admin/system/logs` | 最近请求日志 | 管理员 JWT | 已实现 |

未挂载且 OpenAPI 未写的：GraphQL、WebSocket、RPC。**代码中未发现**。

`web/app/api/*` 为冻结网页的 Next.js Route，**不是**本 API。

---

## 公共错误

| HTTP | `error` 示例 | 场景 |
| --- | --- | --- |
| 400 | 缺参 / bind 校验 / `unsupported_mode` / `invalid json body` | 入参 |
| 401 | `missing token` / `invalid token` / `invalid credentials` / `invalid refresh token` / `invalid user` | 认证 |
| 404 | `Source not found` / `Category not found` / `Vod not found` / `No sources available` | 资源 |
| 409 | `email already registered` / `source id already exists` | 冲突 |
| 500 | GORM `err.Error()` | 写库失败 |
| 501 | `ticket_not_enabled` | ticket 模式未开 |
| 502 | 上游 `err.Error()` | MacCMS / bpz5 |
| 503 | health DB；`database not configured` | 库不可用 |

OPTIONS 预检：`204`。

---

## 1. GET `/health`

- **模块：** 运维  
- **Handler：** `handler.Health`  
- **Token：** 否  
- **公开：** 是  

无参数。

成功：

```json
{"status": "ok", "db": "ok"}
```

`db` 取值：`ok` | `disabled`（无 DATABASE_URL）。Ping 失败：HTTP 503，`{"status":"error","db":"<驱动错误>"}`。

```bash
curl -s http://localhost:8080/health
```

---

## 2. GET `/swagger/*any`

- **Handler：** `ginSwagger.WrapHandler`（`cmd/server/main.go`）  
- **Token：** 否  

仓库 **无** `swag init` 生成的 `docs` 包。UI 是否可用 **待确认**。契约请用 `packages/openapi/openapi.yaml`。

---

## 3. GET `/api/v1/sources`

- **Handler：** `(*Handler).GetSources`  
- **Token：** 否  

无参数。仅返回 `Enabled()`。

```json
{
  "sources": [
    {
      "id": 33,
      "name": "无忧",
      "url": "https://www.wyvod.com/api.php/provide/vod/",
      "flag": 0,
      "vip_only": false
    }
  ]
}
```

```bash
curl -s http://localhost:8080/api/v1/sources
```

---

## 4. GET `/api/v1/vod/list`

- **Handler：** `GetVodList`  
- **Token：** 否  

| 参数 | 类型 | 必填 | 来源 | 默认值 | 说明 |
| --- | --- | --- | --- | --- | --- |
| cat | string | 否 | Query | 空 | 统一分类 slug；**优先于** sourceId/t |
| sourceId | string(int) | 否 | Query | 空 | 单源模式 |
| pg | int | 否 | Query | 1 | 小于 1 时改为 1 |
| t | int | 否 | Query | 空 | 单源 type_id；非法或 ≤0 视为无 |

### 4.1 有 `cat`

逻辑：`unified.FetchListBySlug`。未知 slug → 404 `Category not found`。上游错误 → 502。

```json
{
  "cat": "movie",
  "label": "电影",
  "sourcesUsed": [33, 164],
  "sourcesFailed": [125],
  "code": 1,
  "msg": "ok",
  "page": 1,
  "pagecount": 10,
  "limit": "24",
  "total": 100,
  "list": []
}
```

`list[]` 为 `MergedVodItem`（见下方结构）。`limit` 为合并后条数字符串。`total` 为各源 `total` **相加**（非去重后条数）。

无映射源：200，`msg` 为 `no mapped sources`，空 list。

### 4.2 无 `cat`，有 `sourceId`

`category.FetchVodListByTypeMerged`。源不存在 404。上游错误时 **仍 200**，走 `emptyListResponse`（`code:1, pagecount:0, limit:"24", total:0, list:[]`，`msg` 为错误字符串）。

### 4.3 无 `cat` 无 `sourceId`

按 `Enabled()` 顺序尝试，直到某源返回非空 list。全空则用 Default 源返回空列表。无任何源 → 404 `No sources available`。

单源成功形状：

```json
{
  "source": { "id": 33, "name": "无忧" },
  "typeId": 1,
  "code": 1,
  "msg": "ok",
  "page": 1,
  "pagecount": 5,
  "limit": "20",
  "total": 100,
  "list": []
}
```

`typeId` 可为 JSON `null`。

```bash
curl -s "http://localhost:8080/api/v1/vod/list?cat=movie&pg=1"
curl -s "http://localhost:8080/api/v1/vod/list?sourceId=33&t=1&pg=1"
```

---

## 5. GET `/api/v1/vod/categories`

- **Handler：** `GetUnifiedCategories` → `unified.Public()`  

无参数。文件未加载时树可能为空（启动失败只 log）。

```json
{
  "version": 1,
  "defaultSlug": "movie",
  "tree": [
    {
      "slug": "movie",
      "label": "电影",
      "children": [{ "slug": "movie-action", "label": "动作片" }]
    }
  ]
}
```

不返回 `sources` 映射与 `aliases`。

---

## 6. GET `/api/v1/vod/types`

| 参数 | 类型 | 必填 | 来源 | 默认 | 说明 |
| --- | --- | --- | --- | --- | --- |
| sourceId | int | 否 | Query | Default 源 | 启用源 ID |

404：源不存在。502：拉 `class` 失败。

```json
{
  "source": { "id": 33, "name": "无忧" },
  "categories": [{ "typeId": 1, "label": "电影" }]
}
```

来自 `category.Cache.Get`（内存 TTL 5 分钟）。

---

## 7. GET `/api/v1/vod/search`

| 参数 | 类型 | 必填 | 来源 | 默认 | 说明 |
| --- | --- | --- | --- | --- | --- |
| wd | string | 是 | Query | — | 关键词 |
| pg | int | 否 | Query | 1 | |
| sourceId | int | 否 | Query | 全源 | 限定一站 |

缺 `wd` → 400。非法 sourceId → 404 `No sources available`。单源失败 skip。

```json
{
  "keyword": "鲨笼绝境",
  "merged": true,
  "total": 1,
  "list": [
    {
      "vod_id": "123",
      "vod_name": "鲨笼绝境",
      "vod_pic": "https://example.com/p.jpg",
      "variants": [
        { "sourceId": 164, "sourceName": "红牛", "vodId": "123" }
      ],
      "primarySourceId": 164
    }
  ]
}
```

`list[]` 还包含 `VodItem` 其它 omitempty 字段（`vod_year`、`vod_time` 等）。字段名以 `model.VodItem` / `MergedVodItem` 为准。

```bash
curl -s --max-time 120 "http://localhost:8080/api/v1/vod/search?wd=%E9%B2%A8%E7%AC%BC%E7%BB%9D%E5%A2%83"
```

---

## 8. GET `/api/v1/vod/detail`

| 参数 | 类型 | 必填 | 来源 | 说明 |
| --- | --- | --- | --- | --- |
| sourceId | int | 是 | Query | 主源 |
| ids | string | 是 | Query | 主源 vod_id |

缺参 400；源不存在 404；上游 502；无影片 404。

```json
{
  "source": { "id": 164, "name": "红牛" },
  "vod": {
    "vod_id": "123",
    "vod_name": "片名",
    "vod_pic": "https://...",
    "vod_blurb": "...",
    "vod_content": "..."
  },
  "playSources": [
    {
      "name": "红牛 · 高清",
      "key": "164:hnm3u8",
      "episodes": [{ "name": "第01集", "url": "https://cdn/index.m3u8" }],
      "sourceId": 164,
      "weight": 920,
      "mode": "direct",
      "playFrom": "hnm3u8",
      "providerId": "",
      "ticket": "",
      "requiresAuth": false
    }
  ],
  "variants": [{ "sourceId": 164, "sourceName": "红牛", "vodId": "123" }],
  "merged": true
}
```

`PlaySource` JSON 字段名是 **`name` 不是 `label`**（与部分设计文档不同）。ticket 线 `mode` 为 `"ticket"`，可含 `ticket` / `providerId` / `requiresAuth`。

bpz5 启用且匹配成功时，官方线插到数组前再 `SortPlaySources`。

---

## 9. GET `/api/v1/vod/pic`

| 参数 | 必填 | 来源 |
| --- | --- | --- |
| sourceId | 是 | Query |
| ids | 是 | Query |

成功：`{"url": "https://..."}` 或 `{"url": null}`。502：`{"error":"...","url":null}`。

---

## 10. GET `/api/v1/play/parse`

| 参数 | 必填 | 来源 |
| --- | --- | --- |
| sourceId | 是 | Query |
| url | 是 | Query |

成功体为 `ParseResult`：

```json
{
  "url": "https://cdn/index.m3u8",
  "parsed": true,
  "mode": "direct",
  "playFrom": null,
  "expiresAt": null
}
```

`expiresAt` 在结构体中始终序列化，代码路径未赋值时为 `null`。无 `jx_url` 时 `parsed: false`，`url` 为入参原值。

---

## 11. POST `/api/v1/play/resolve`

- **Handler：** `ResolvePlay`  
- **Content-Type：** `application/json`  
- **结构体：** `model.PlayResolveRequest`

| 参数 | 类型 | 必填 | 来源 | 默认 | 说明 |
| --- | --- | --- | --- | --- | --- |
| mode | string | 否 | Body | `direct` | `direct` / `ticket`；其它 400 `unsupported_mode` |
| sourceId | int | 视模式 | Body | 0 | direct + jx 时需要以解析 |
| url | string | direct 时是 | Body | | direct 缺则 400 |
| jx | bool | 否 | Body | true（nil 当 true） | false 则不解析 |
| ticket | string | ticket 时是 | Body | | 也可用 url 中的 ticket（`NormalizeTicket`） |
| providerId | string | 否 | Body | | **handler 未使用** |
| playFrom | string | 否 | Body | | 原样回写到响应 |

JSON 绑定失败：400 `invalid json body`。

### direct

`jx=false` 或 `sourceId==0`：原样返回 `parsed:false`。  
否则查源，`parser.ParsePlayAddress`。

```json
{
  "mode": "direct",
  "sourceId": 164,
  "url": "https://play.example/share",
  "jx": true,
  "playFrom": "hnm3u8"
}
```

### ticket

无 ticket → 400。BPZ5 未启用 → 501 `ticket_not_enabled`。上游失败 → 502。

```json
{
  "mode": "ticket",
  "ticket": "rpt1....",
  "playFrom": "cloudflare"
}
```

成功响应同 `ParseResult`，`mode` 为 `ticket` 或 `direct`。

```bash
curl -s -X POST http://localhost:8080/api/v1/play/resolve \
  -H 'Content-Type: application/json' \
  -d '{"mode":"direct","sourceId":164,"url":"https://example.com/a.m3u8","jx":false}'
```

---

## 12. POST `/api/v1/auth/register`

需 DB。Body：`email`（required,email）、`password`（required,min=6）。校验失败 400（gin binding 英文信息）。邮箱已存在 409 `email already registered`。随后立即 Login 失败则 500。

HTTP **201**：

```json
{
  "user": { "id": "uuid", "email": "a@b.c" },
  "tokens": {
    "access_token": "<JWT>",
    "refresh_token": "<hex>",
    "expires_in": 900
  }
}
```

---

## 13. POST `/api/v1/auth/login`

Body：`email`、`password`（required）。失败 401，`error` 为 `invalid credentials` 或其它。

HTTP 200，形状同注册（无 201）。

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@example.com","password":"<SECRET>"}'
```

---

## 14. POST `/api/v1/auth/refresh`

Body：`{"refresh_token":"..."}`。失败 401 `invalid refresh token`。

HTTP 200：**直接序列化 TokenPair**（无 `user` 包裹）：

```json
{
  "access_token": "<JWT>",
  "refresh_token": "<hex>",
  "expires_in": 900
}
```

---

## 15–17. `/api/v1/user/favorites`

均需 `Authorization: Bearer <access_token>`。

### GET

成功：`{"favorites":[ Favorite, ... ]}`，按 `created_at desc`。

Favorite 字段：`id, user_id, merge_key, vod_name, primary_source_id, primary_vod_id, poster, created_at`。

### POST

| 参数 | 必填 | 来源 |
| --- | --- | --- |
| merge_key | 是 | Body |
| vod_name | 是 | Body |
| primary_source_id | 是 | Body |
| primary_vod_id | 是 | Body |
| poster | 否 | Body |

已存在同一 merge_key：200 返回旧记录。新建：201 返回新记录。

### DELETE

Query `merge_key` 必填。成功 `{"ok":true}`（即使未匹配到行，GORM Delete 仍 200）。

---

## 18–19. `/api/v1/user/progress`

需用户 JWT。

### GET

Query `progress_key` 可选；有则过滤单条。成功 `{"progress":[ WatchProgress, ... ]}`。

WatchProgress：`id, user_id, progress_key, position_sec, duration_sec, updated_at`。

### PUT

Body：`progress_key` 必填；`position_sec`、`duration_sec` 可选（默认 0）。有则更新，无则创建。HTTP 200 返回该行对象。

---

## 20. POST `/api/v1/admin/login`

无需 JWT。Admin 未启用则路由不存在（Gin 404）。

Body：`username`、`password`。失败 401 `invalid credentials`。

```json
{
  "access_token": "<JWT>",
  "expires_in": 28800
}
```

无 refresh。TTL 8 小时。

---

## 21. GET `/api/v1/admin/sources`

需 Admin JWT。返回 `{"sources":[ Source, ... ]}`，含 flag≠0 与 vip_only。

Source：`id, name, url, flag, jx_url, json_parse, danmaku_api_url, vip_only`（空 omitempty 可能省略）。

---

## 22. POST `/api/v1/admin/sources`

Body 为完整 `Source`。`id` 必填且 ≠0，否则 400 `id is required`。ID 冲突 409。成功 201 回源对象。写入 JSON 文件。

---

## 23. PUT `/api/v1/admin/sources/:id`

Path `id`。不存在 404 `source not found`。Body 覆盖后强制 `ID=path`。200 回对象。

---

## 24. DELETE `/api/v1/admin/sources/:id`

成功 `{"ok":true}`。不存在：404，`error` 为 Store 返回字符串。

---

## 25. POST `/api/v1/admin/sources/:id/test`

调用 `maccms.FetchVodTypes`。**始终 HTTP 200**：

```json
{"ok": true, "latency": "123ms"}
```

失败：`{"ok":false,"latency":"...","error":"..."}`。

---

## 26. GET `/api/v1/admin/users`

Query `page` 默认 1；**pageSize 固定 20**（无参数）。无 DB → 503 `database not configured`。

```json
{
  "users": [
    {
      "id": "uuid",
      "email": "a@b.c",
      "created_at": "2026-01-01T00:00:00Z",
      "favorite_count": 3
    }
  ],
  "page": 1,
  "total": 1
}
```

---

## 27. GET `/api/v1/admin/users/stats`

```json
{
  "total_users": 0,
  "today_new_users": 0,
  "total_favorites": 0
}
```

`today` 为 `time.Now().Truncate(24h)`（服务器本地时区）。

---

## 28. DELETE `/api/v1/admin/users/:id`

Path UUID。非法 400 `invalid user id`。事务删除 favorites、watch_progress、refresh_tokens、user。成功 `{"ok":true}`。

---

## 29. GET `/api/v1/admin/system/status`

```json
{
  "uptime": "1h2m3s",
  "sources": 29,
  "sources_live": 29,
  "cache_items": 0,
  "db": "ok"
}
```

`db`：`ok` | `down` | `error` | `disabled`。`sources` 为全部条数，`sources_live` 为 Enabled 数。

---

## 30. POST `/api/v1/admin/system/cache/clear`

`category.Cache.Clear()`。`{"ok":true}`。

---

## 31. GET `/api/v1/admin/system/logs`

```json
{
  "logs": [
    {
      "time": "2026-09-04T00:00:00Z",
      "method": "GET",
      "path": "/health",
      "status": 200,
      "latency": "1ms"
    }
  ]
}
```

最多 200 条，进程重启丢失。

---

## 核心数据结构（响应嵌套）

`VodItem`：`vod_id, vod_name, vod_pic, vod_remarks, vod_year, vod_area, vod_class, vod_blurb, vod_content, vod_play_from, vod_play_url, vod_time, type_id, type_name`。

`MergedVodItem`：上述字段 + `variants` + `primarySourceId`。

---

## 业务逻辑通式（点播）

```text
请求
 ↓
Handler（Query/JSON 校验）
 ↓
SourceStore / unified / merge / parser / bpz5
 ↓
maccms HTTP（无 Repository）
 ↓
JSON（成功字段因接口而异，失败多为 {"error"}）
```

用户接口在 Handler 内 `h.DB` 直查。
