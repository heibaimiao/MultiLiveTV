# 核心代码链路

以下链路均来自当前源码。类名 / 函数名可跳转阅读。

---

## 1. 统一分类列表

```text
GET /api/v1/vod/list?cat=movie&pg=1
 ↓
handler.GetVodList（vod.go）
 ↓
unified.FetchListBySlug
 ↓
unified.Find(slug) → Node.sources 映射
 ↓
最多 8 worker：maccms.FetchVodList(src, page, typeID)
 ↓
merge.MergeVodItems
 ↓
merge.SortMergedByUpdatedDesc
 ↓
JSON：cat/label/list/sourcesUsed/sourcesFailed
```

- **核心类：** `unified.ListResult`、`model.MergedVodItem`
- **判断：** slug 不存在 → `ErrNotFound` → 404；无映射 → 空列表 `no mapped sources`
- **异常：** 单源失败计入 `sourcesFailed`，不中断其它源

Apple 平行路径：`VodService.fetchList` → `CategoryListService.fetchUnifiedList`（不经过 Gin）。

---

## 2. 单源列表（无 cat）

```text
GET /vod/list?sourceId=33&t=1
 ↓
GetVodList
 ↓
config.SourceStore.ByID（仅 Enabled）
 ↓
category.FetchVodListByTypeMerged
 ↓
maccms.FetchVodList
 ↓
若该 type 为空：FetchVodTypes → GetChildTypeIds → 子类列表拼接
 ↓
mergeListItems → MergeVodItems
 ↓
listResponse
```

- **判断：** 上游 error → **200** `emptyListResponse`（不是 502）
- **无 sourceId：** 顺序尝试各 Enabled 源直到 list 非空

---

## 3. 跨源搜索合并

```text
GET /vod/search?wd=
 ↓
SearchVod
 ↓
对 Enabled（或指定源）maccms.SearchVod（ac=list&wd）
 ↓
组装 MergeableVodItem
 ↓
merge.MergeVodItems
 ↓
{ keyword, merged:true, total, list }
```

- **合并键：** `NormalizeVodTitle`（小写、去空白与 `·・:：-—_`）
- **主条目：** 有海报 > `parser.SourceWeight` > 线路数 > sources.json 顺序
- **时间：** 组内最新 `vod_time`

---

## 4. 详情合并 + 官方线

```text
GET /vod/detail?sourceId=&ids=
 ↓
GetVodDetail
 ↓
merge.FetchMergedVodDetail
    ├── maccms.FetchVodDetail 主源
    ├── 其它源 SearchVod 按 mergeKey 匹配，最多 16 variants
    ├── 再 FetchVodDetail
    ├── parser.MergePlaySourcesFromVods
    └── pickBestVodMetadata（海报、简介长度）
 ↓
若 BPZ5.Enabled：bpz5.EnrichOfficialPlaySources（5s）
    ├── SearchCatalog
    ├── PickBestCard 分 ≥ 80
    └── 构造 mode=ticket 的 PlaySource 插到前面
 ↓
parser.SortPlaySources
 ↓
{ source, vod, playSources, variants, merged:true }
```

- **线路 key：** `{sourceId}:{playFrom}`
- **权重：** `WeightFor(providerId > playFrom > sourceId > default)`
- **异常：** enrich 失败静默，只保留 MacCMS 线

---

## 5. 取播 direct（jx_url）

```text
POST /play/resolve { mode:direct, sourceId, url, jx }
 ↓
ResolvePlay
 ↓
jx==false 或 sourceId==0 → 原 URL parsed=false
 ↓
parser.ParsePlayAddress
 ↓
GET source.JxURL + QueryEscape(url)
 ↓
JSON 顶层 string / url / data.url，或文本 http...
 ↓
失败一律回退原始 URL
```

GET `/play/parse` 是同一 `ParsePlayAddress` 的 query 包装。

Apple：`PlayParser` 本机请求 jx，并可从 HTML 抽 m3u8 / iframe。

---

## 6. 取播 ticket（bpz5）

```text
POST /play/resolve { mode:ticket, ticket }
 ↓
bpz5.NormalizeTicket
 ↓
未 Enabled → 501 ticket_not_enabled
 ↓
bpz5.Client.ResolveLine
    ├── HMAC 头（timestamp/nonce/signature/client-name）
    ├── 可能先 anonymous session
    └── POST /v1/playback/resolve-line {"ticket"}
 ↓
{ url, parsed:true, mode:ticket }
```

密钥不出客户端。Compose 默认不注入密钥，此链路在默认 Docker 中关闭。

---

## 7. 用户注册与登录

```text
POST /auth/register
 ↓
binding email + password min=6
 ↓
auth.Service.Register → bcrypt(12) → INSERT users
 ↓
auth.Service.Login → issueTokens
    ├── JWT HS256 15min（user_id, email, sub）
    └── refresh hex → SHA-256 存 refresh_tokens，7 天
 ↓
201 { user, tokens }
```

登录失败统一 `invalid credentials`（不区分用户是否存在）。

JWT 中间件：`middleware.JWT` → `c.Set("userID", claims.UserID)`。

---

## 8. 收藏

```text
POST /user/favorites + Bearer
 ↓
uuid.Parse(userID)
 ↓
按 user_id + merge_key First
 ↓
已存在 → 200 旧行
 ↓
否则 Create → 201
```

DELETE 仅按 query `merge_key` + user_id。`merge_key` 由调用方传入，服务端不从片名计算。

---

## 9. 观看进度

```text
PUT /user/progress
 ↓
Where user_id + progress_key
 ↓
有 → 改 position_sec / duration_sec Save
 ↓
无 → Create
```

`progress_key` 语义 **代码中未定义**（客户端约定）。

---

## 10. 管理员改源站

```text
POST /admin/login
 ↓
admin.Service.Login 明文比对环境变量
 ↓
JWT role=admin，8h，无 refresh
 ↓
POST/PUT/DELETE /admin/sources
 ↓
SourceStore.Upsert / Delete
 ↓
MarshalIndent 写回 sources.json
```

测源：`TestSource` → `maccms.FetchVodTypes`，HTTP 恒 200。

清缓存：只清 `category.Cache`，**不**清 SourceStore、不重启。

---

## 11. Apple 首页启动（tvOS）

```text
AppLaunchSession.load
 ↓
VodService.loadHomeLaunch
 ↓
HomeLaunch.load + CategoryListService 多 slug
 ↓
phase = ready(HomeLaunchPayload) → MainTabView
失败 → LaunchLoadingView 重试
```

iOS：无启动闸门，直接 `MainTabView`。

---

## 12. Apple 直播

```text
LiveView
 ↓
LiveService.reload
 ↓
LiveStore.enabled（lives.json flag=0）
 ↓
下载 M3U → M3UPlaylistParser
 ↓
LivePlaybackSession：HLS → AVPlayer；FLV → VLCLivePlayer
```

Go **无**对应 API。

---

## 异常处理共性

- 点播公开接口多数不 panic；http 错误转 `{"error"}` 或空列表。
- `ParsePlayAddress` 永不 502，解析失败当未解析。
- Admin 用户接口无 DB → 503。
- 请求日志不区分成功失败，一律入环缓。
