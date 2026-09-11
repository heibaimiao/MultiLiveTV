# 产品逆向分析

> 依据当前代码与 README 反推。未在代码中出现的能力不写入「已实现」。  
> 多源聚合的目标规格见 [11-vod-aggregation-prd.md](11-vod-aggregation-prd.md)。

## 1. 产品概述

| 项 | 说明 | 依据 |
| --- | --- | --- |
| 产品名称 | MultiLiveTV | 根 README、Xcode 工程名、Go module |
| 产品定位 | MacCMS 多源聚合点播，附带 Apple TV / iPad 原生客户端与可选 Go 后端 | 根 README |
| 解决的问题 | 各采集站分类 ID 不互通、同一影片重复出现、线路质量参差；需要统一浏览、搜索、选线播放 | `unified-categories` 设计与 merge 实现 |
| 目标用户 | **待确认**（代码无用户画像）。从客户端可推断：电视 / 平板观看者；另有环境变量管理员 | Apple tvOS/iPad；Admin 后台 |
| 核心使用场景 | 打开 App 按电影 / 剧集等分类浏览；搜索片名；选线路与集数播放；电视上看直播；缓存下载。服务端可选：账号收藏与进度、后台维护源站 | Apple `MainTabView`、Go user/admin 路由 |

法律与使用声明（README）：仅供个人学习研究；第三方采集站需自行维护。

## 2. 产品功能地图

```text
MultiLiveTV
├── 点播聚合（Go API + Apple 本地）
│   ├── 启用源列表
│   ├── 统一分类树
│   ├── 跨源分类列表
│   ├── 单源分类列表（兼容）
│   ├── 跨源搜索合并
│   ├── 合并详情 + 多线路
│   ├── 海报 URL
│   └── 单源分类 type 列表
├── 播放
│   ├── 线路权重排序
│   ├── jx_url 直链解析（direct）
│   └── bpz5 ticket 解票（可选）
├── 用户账号（仅 Go API，需 Postgres）
│   ├── 注册 / 登录 / 刷新 Token
│   ├── 收藏
│   └── 观看进度
├── 管理后台（需 Admin 环境变量）
│   ├── 管理员登录
│   ├── 资源站 CRUD + 连通测试
│   ├── 用户列表 / 统计 / 删除
│   └── 系统状态 / 清缓存 / 请求日志
├── Apple 客户端（不调 Go API）
│   ├── 首页分类 Feed
│   ├── 搜索
│   ├── 详情与 AVPlayer / 解析
│   ├── 直播（M3U + HLS/FLV）
│   ├── 下载管理
│   ├── Top Shelf
│   └── Deep Link
├── Android 客户端（调 Go API）
│   ├── 分类 Tab + 列表 + 搜索
│   └── 详情弹窗（线路/集数，无播放器）
└── 网页端 web/（已冻结）
    └── 历史 Next.js 全栈点播站
```

## 3. 功能详细说明

### 3.1 启用源列表

- **目的：** 告知客户端当前可用的采集站。
- **角色：** 任意 API 调用方。
- **前置：** 进程已加载 `sources.json`。
- **输入：** 无。
- **处理：** `SourceStore.Enabled()`：`flag == 0` 且 `vip_only == false`。
- **输出：** `id / name / url / flag / vip_only`。
- **异常：** 文件加载失败则进程无法启动（`log.Fatalf`）。
- **权限：** 公开。
- **状态：** 已实现。

### 3.2 统一分类浏览

- **目的：** 用稳定 slug（如 `movie`）跨站拉列表，避免各站 `type_id` 冲突。
- **角色：** 终端用户（Apple 本地 / Android 经 API）。
- **前置：** `unified-categories.json` 加载成功；否则 Go 侧分类接口树为空（启动只打 log）。
- **输入：** slug、页码。
- **处理：** 按映射并发（最多 8 路）请求各源 `ac=list&t=typeId`，按规范化片名合并，再按 `vod_time` 倒序。
- **输出：** 合并后的影片列表 + `sourcesUsed` / `sourcesFailed`。
- **异常：** 未知 slug → 404；全部源失败则列表可能为空但仍 200。
- **权限：** 公开。
- **状态：** 已实现。

### 3.3 跨源搜索

- **目的：** 输入片名关键词，多源结果去重为一条。
- **角色：** 终端用户。
- **输入：** `wd`，可选 `sourceId`、`pg`。
- **处理：** 对启用源循环 `ac=list&wd=`，`MergeVodItems`。
- **输出：** `list` + `total` + `merged: true`。
- **异常：** 缺 `wd` → 400；单源失败则跳过。
- **权限：** 公开。
- **状态：** 已实现。Apple 有本地同等合并（`VodMergeService`）。

### 3.4 合并详情与线路

- **目的：** 一部片聚合多站播放线，并按权重排序。
- **角色：** 终端用户。
- **输入：** `sourceId` + `ids`（该站影片 ID）。
- **处理：** 主源 `ac=detail` → 用片名在其它源搜索最多 16 个变体 → 拉详情拆 `vod_play_from/url` → 可选 bpz5 按标题匹配（分 ≥ 80）插入 ticket 线。
- **输出：** `vod`、`playSources`、`variants`、`merged: true`。
- **异常：** 缺参 400；源不存在 404；上游失败 502；影片不存在 404。
- **权限：** 公开。
- **状态：** 已实现。bpz5 enrich 无密钥时跳过。

### 3.5 取播解析

- **目的：** 把选中的线路变成播放器可用的 URL。
- **角色：** 终端用户 / 调用方。
- **输入：** `mode=direct` 时 `url` + 可选 `sourceId`/`jx`；`mode=ticket` 时 `ticket`。
- **处理：** direct 走 `jx_url` GET；ticket 服务端 HMAC 调 bpz5 `resolve-line`。
- **输出：** `{ url, parsed, mode, playFrom, expiresAt }`。
- **异常：** 见 [02-api.md](02-api.md)。ticket 未启用 → 501。
- **权限：** 公开（无用户 JWT）。
- **状态：** 已实现。Apple 在本机做 jx 解析，不调用此接口。

### 3.6 用户注册 / 登录 / 收藏 / 进度

- **目的：** 跨设备记住收藏与观看位置。
- **角色：** 注册用户。
- **前置：** Postgres。
- **输入 / 输出：** 见 API 文档。
- **权限：** 收藏与进度需要用户 Bearer JWT。
- **状态：** **API 已实现**。Apple / Android / Admin 前端 **均无** 普通用户登录页（Admin 是另一套账号）。产品层属于 **部分实现**。

### 3.7 管理后台

- **目的：** 维护采集站、查看用户规模、清分类缓存、看最近请求日志。
- **角色：** 环境变量管理员（非数据库用户）。
- **页面：** `/login`、`/` 仪表盘、`/sources`、`/users`、`/logs`。
- **状态：** 已实现。

### 3.8 Apple 直播

- **目的：** 播放 M3U 频道列表（与点播采集站分离）。
- **前置：** `Resources/lives.json` 中 `flag=0` 的源。当前仓库有 1 条：`id=1 name=ZB`。
- **处理：** 下载 M3U → 分组 → HLS 用 AVPlayer，HTTP-FLV 用 VLCKit。
- **状态：** 已实现。Go API **代码中未发现** 直播接口。

### 3.9 Apple 下载

- **目的：** 将点播媒体缓存到本地离线播放。
- **处理：** `DownloadManager` + File / HLS 引擎 + 后台 URLSession。
- **状态：** 已实现（仅 Apple）。

### 3.10 Android 浏览

- **目的：** 电视 / 平板上浏览聚合目录。
- **限制：** 无播放器、无直播、无下载、无登录；无 Gradle 工程文件。
- **状态：** 部分实现。

### 3.11 网页端

- **状态：** 已冻结（`web/ARCHIVED.md`）。仍可用 `npm run dev` 作历史参考。

## 4. 用户角色

代码中真实存在的身份：

| 角色 | 如何产生 | 权限 |
| --- | --- | --- |
| 匿名 API 调用方 | 无 Token | 全部公开点播 / 播放接口 |
| 注册用户 | `POST /auth/register`，邮箱 + 密码 | JWT 后访问 `/user/favorites`、`/user/progress` |
| 管理员 | 环境变量 `ADMIN_USERNAME` / `ADMIN_PASSWORD`，**不是** `users` 表 | Admin JWT 后访问 `/admin/*`（除 login） |
| Apple 终端用户 | 无账号体系 | 本地直连采集站；能力由 App 代码决定 |
| Android 终端用户 | 无账号 | 调用公开 Go API |

**代码中未发现：** RBAC 角色表、操作员、VIP 用户落地逻辑（`vip_only` 源只是从公开 `Enabled()` 中排除，无 VIP 鉴权接口）。

管理员与注册用户 **两套 JWT**（不同 claims、不同密钥配置项、不能混用）。

## 5. 核心业务流程

### 5.1 点播浏览（Go API）

```text
客户端
 ↓
GET /api/v1/vod/categories
 ↓
GET /api/v1/vod/list?cat=movie&pg=1
 ↓
unified.FetchListBySlug（最多 8 路 MacCMS）
 ↓
merge.MergeVodItems + 按更新时间排序
 ↓
返回合并列表
 ↓
GET /api/v1/vod/detail?sourceId=&ids=
 ↓
merge.FetchMergedVodDetail
 ↓
可选 bpz5.EnrichOfficialPlaySources
 ↓
parser.SortPlaySources
 ↓
返回 playSources
 ↓
POST /api/v1/play/resolve
 ↓
播放器播放 url
```

### 5.2 Apple 点播（不经过 Go）

```text
App 启动
 ↓
SourceStore 读包内 sources.json
 ↓
HomeLaunch / CategoryListService 按 slug 打采集站
 ↓
VodMergeService 合并
 ↓
详情 PlayParser 拆线路
 ↓
本机请求 jx_url 或直链
 ↓
AVPlayer / VLC
```

### 5.3 用户收藏（仅 API）

```text
POST /auth/login
 ↓
返回 access_token（15 分钟）+ refresh_token（7 天）
 ↓
Authorization: Bearer access_token
 ↓
POST /user/favorites
 ↓
Postgres favorites 表
```

### 5.4 管理员维护源

```text
POST /admin/login（明文比对环境变量）
 ↓
access_token（8 小时，无 refresh）
 ↓
CRUD /admin/sources → 写回 sources.json 文件
 ↓
POST /admin/sources/:id/test → maccms.FetchVodTypes
```

**代码中未发现：** 支付、订单、商品、消息推送、审核流、内容上传。
