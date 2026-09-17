# 全项目代码逻辑与稳定性审计报告

**审计日期：** 2026-09-16  
**审计范围：** Apple 客户端（tvOS / iPadOS）+ Android 客户端（Pad `:app` / TV `:tv` + `:core`）  
**审计立场：** 上线后用户如何把客户端弄崩、弄白、弄卡死、弄成无法恢复  
**本轮约束：** 只审计，不修改业务代码

确定性标记：

- **确定性问题：** 现有代码路径在给定输入下必然走到该后果
- **理论风险：** 代码路径存在，但当前打包资源或解析器不变式下尚未证明一定触发

---

## 1. 审计范围

| 区域 | 覆盖 |
| --- | --- |
| Apple App | `clients/apple/MultiLiveTV/**/*.swift`（69 个）、`MultiLiveTVTopShelf` |
| Apple 配置 | `project.yml`、`Info-iOS.plist`、`Info-tvOS.plist`、entitlements、ATS、`Resources/*.json` |
| Apple 脚本 / 测试 | `clients/apple/scripts/run-logic-tests.sh`、`verify-client-logic.swift` |
| Android Pad | `clients/android/app/src/main/kotlin/**` |
| Android TV | `clients/android/tv/src/main/kotlin/**` |
| Android 共享业务 | `clients/android/core/src/main/kotlin/**` |
| Android 配置 | `AndroidManifest.xml`、`build.gradle.kts`、`core/src/main/resources/*.json` |
| Android 测试 | `core/src/test/kotlin/**`（15 个测试类，作为覆盖证据） |

**未作为本轮主审计对象（仅作依赖背景）：** Go API、Admin、冻结的 `web/`。两端客户端均 **直连第三方采集站 / M3U，不依赖 Go API**。

**本轮未执行：** Android `./gradlew :core:test`（审计环境无法写 Gradle wrapper lock / 下载发行包）。Apple `run-logic-tests.sh` 已执行并通过。

---

## 2. 项目架构

```text
用户操作（触控 / 遥控器 / Deep Link / Top Shelf）
        ↓
SwiftUI / Jetpack Compose UI
        ↓
VodService / LiveService / DownloadManager / WatchHistory
        ↓
SourceStore / LiveStore / CategoryListService / PlayParser
        ↓
HTTPS/HTTP 直连第三方
        ├── MacCMS 采集站（source-registry.json，当前 33 个源）
        ├── 各源 jx_url 解析站
        ├── lives.json → 远程或 bundle M3U
        └── CDN 媒体流（AVPlayer / TVVLCKit 或 Media3 ExoPlayer）
        ↓
JSON / M3U / 媒体字节
        ↓
合并、线路权重、探测、failover
        ↓
UI 状态（loading / error / empty / content）
```

### 2.1 技术栈

| 端 | 语言 / UI | 播放 | 网络 | 并发 |
| --- | --- | --- | --- | --- |
| Apple tvOS 17 + iPadOS 17 | Swift 5.9 + SwiftUI | 点播 AVPlayer；直播 AVPlayer + VLCKit | URLSession，请求超时 15s | Swift Concurrency / `@MainActor` |
| Android Pad + TV | Kotlin 2.0 + Compose | Media3 ExoPlayer 1.5.1 | OkHttp 4.12（connect 5s / read+call 8s）+ DoH | coroutines |

**代码中未发现：** Redis、数据库、消息队列、客户端登录 / Token、WebSocket。观看历史与 Apple 下载队列走本地 JSON 文件。

### 2.2 模块入口

```text
Apple
  MultiLiveTVApp
    → tvOS: AppLaunchSession.loadHomeLaunch → MainTabView
    → iPad: 直接 MainTabView，HomeView 自行 bootstrap
    → Tabs: Home / Live / Search / History / Downloads

Android Pad
  MainActivity + NavHost
    home / live / search / history / downloads / detail / player / livePlayer

Android TV
  MainActivity + 侧边栏焦点
    直播为单页集成播放器（LiveScreen + LiveSessionController）
    不走 Pad 的独立 livePlayer 路由
```

---

## 3. 核心业务流程

| 流程 | 数据流 |
| --- | --- |
| 首页 | `loadHomeLaunch` → 统一分类 fan-out（最多约 8 并发，单源超时）→ 合并 → 海报栅格 / 货架 |
| 分类 / 加载更多 | `fetchList(page, slug)` → `HomeFeed` 分页揭示 |
| 搜索 | 多源 `search` 并行 → `VodMergeService.merge` → 海报网格 |
| 详情 | 主源 detail + 跨源 enrich → `playSources` 选集 |
| 点播播放 | `VodPlaybackFailover.candidates`（最多 4 条）→ `parsePlay` → 媒体探测 → 播放器 → 失败换线 |
| 直播 | `lives.json` → 拉 M3U → 解析合并 → 选频道 → HLS/FLV 探测（Apple 可切 VLC） |
| 历史 | 本地 JSON → 拉详情匹配剧集 → `PlaybackRequest` |
| Apple 下载 | 单 worker 队列 → HLS/文件引擎；tvOS 为自研分片下载 |
| Deep Link | `multilivetv://vod/{sourceId}/{vodId}` → 详情 |

---

## 4. 风险总览

| 等级 | 数量 | 说明 |
| --- | --- | --- |
| P0 | 0 | 未发现「当前打包配置下必然无法启动 / 全量用户持续崩溃」的确定路径 |
| P1 | 2 | 搜索页永久骨架屏；点播播放错误后 failover 失效 |
| P2 | 9 | 直播错误无法恢复、下载 OOM/卡死、Top Shelf、深链、搜索竞态等 |
| P3 | 8 | 能力缺口、理论 NPE、静默空配置、监听泄漏等 |

| 类别 | 条数（本报告收录） |
| --- | --- |
| 白屏 / 永久 Loading | 2（P1 搜索卡死 + P2 Pad 直播假 ready） |
| Crash / 闪退 | 2（配置重复 id trap；Pad `streams.first()`，后者当前解析器下为理论） |
| 异常退出 | 1（tvOS 大 HLS 下载 Jetsam） |
| 溢出 | 1（多源 `total` Int 累加，P3） |
| 内存 | 3（tvOS 分片 `Data`、HttpClient 整包读取、图片 inflight） |
| 并发 | 3（搜索覆盖、failover 捕获过期 index、下载删除竞态） |
| 网络异常 | 多数路径有超时；问题在恢复与 failover，而非无限重试 |
| 数据异常 | MacCMS flex 解析较完整；配置 JSON 严格类型会静默空源 |

---

## 5. P0 问题

无。

当前 `source-registry.json` 33 个 `numericId` / `source_id` 均唯一；`lives.json` 1 条。冷启动不依赖 Go / Postgres。未发现 `fatalError` / `System.exit` / 主线程 `runBlocking` 业务路径。

---

## 6. P1 问题

### RISK-001

**等级：** P1  
**确定性：** 确定性问题（iPadOS；tvOS 若直接 `await search()` 同理）  
**模块：** Apple 搜索  
**文件：** `clients/apple/MultiLiveTV/Views/SearchView.swift`  
**位置：** 第 106–133 行  

**问题：** `search()` 在 Task 取消或 stale generation 提前 `return` 时，不把 `isSearching` 置回 `false`。

**触发条件：** iPad 搜索过程中下拉刷新（`.refreshable { await search() }`），SwiftUI 取消进行中的 refresh Task；或两次 `search()` 并发，先完成者 generation 已过期。

**执行路径：**

```text
用户搜索
 ↓
isSearching = true
 ↓
refreshable 取消 Task / shouldApply 失败
 ↓
catch 中 isCancellation → return
 ↓
isSearching 仍为 true，results 仍为空，errorMessage 仍为 nil
 ↓
resultsPane 永久 PosterSkeletonGrid，搜索按钮 disabled
```

**实际后果：** 搜索页无限骨架屏，无法再次点击搜索。需杀进程或离开再进（若状态未重建则仍卡死）。  
**影响范围：** iPad 搜索 Tab；tvOS 主路径走 `startSearch()`，风险较低但仍共享同一 `search()`。  
**为什么会发生：** 缺少 `defer { isSearching = false }`；`HomeView.fetchPage` 已有 generation + `defer`，搜索未对齐。  
**修复建议：** `defer` 在当前 generation 仍有效时清标志；refresh 统一走 `startSearch()`；cancellation 分支在没有更新一代在飞时清 `isSearching`。  
**验证方法：** iPad 进入搜索 → 输入关键词搜索 → 请求未返回时下拉刷新并松手 → 观察是否永久骨架屏。

---

### RISK-002

**等级：** P1  
**确定性：** 确定性问题  
**模块：** Android Pad + TV 点播播放器  
**文件：**

- `clients/android/app/src/main/kotlin/com/heibaimiao/multilivetv/player/PlayerScreen.kt` 第 88–98 行
- `clients/android/tv/src/main/kotlin/com/heibaimiao/multilivetv/player/PlayerScreen.kt` 第 122–132 行

**问题：** `DisposableEffect(player)` 里 `onPlayerError` 捕获了初始 `index`（恒为 0），未使用已声明的 `indexState`（`rememberUpdatedState`）。第二次及之后的 ExoPlayer 错误会用过期 index 计算下一线路。

**触发条件：** 多线路 VOD；第 1 条探测通过后在 ExoPlayer 播放阶段报错；候选 ≥ 2。

**执行路径：**

```text
详情选集 → PlayerScreen
 ↓
LaunchedEffect(index=0) 探测成功 → ready=true → ExoPlayer 播放
 ↓
onPlayerError → VodPlaybackFailover.nextIndex(0, size) → index=1
 ↓
LaunchedEffect(index=1) 加载第二条
 ↓
第二条再报错 → listener 仍用捕获的 index=0
 ↓
nextIndex(0, size) 再次得到 1
 ↓
index 不变，LaunchedEffect 不重跑
 ↓
卡在失败流
```

**实际后果：** 不必然闪退，但播放黑屏 / 卡死，无法自动切后续线路。用户只能返回。多线路场景下 **无法自动恢复**。  
**影响范围：** Pad + TV 全部点播。  
**为什么会发生：** `capture()` 已正确读 `indexState.value`，`onPlayerError` 遗漏；`DisposableEffect` 仅以 `player` 为 key。  
**修复建议：** `onPlayerError` 使用 `indexState.value`；或把 `index` 加入 `DisposableEffect` 依赖。  
**验证方法：** Mock 3 条候选，前两条探测通过但 ExoPlayer 连续 `onPlayerError`，确认第三条从未被尝试。

同文件 `while (true) { capture; delay(1000) }` 绑在 `LaunchedEffect(player, ready)` 上，随 composition 取消，**不是**无限重试风暴。

---

## 7. P2 问题

### RISK-003

**等级：** P2  
**确定性：** 确定性代码路径；**当前包内 `source-registry.json` 无重复 id，现网未触发**（理论风险）  
**模块：** Apple 启动 / 配置  
**文件：** `clients/apple/MultiLiveTV/Services/SourceStore.swift` 第 8–18 行；`VodService.swift` 第 8–11 行  

**问题：** `Dictionary(uniqueKeysWithValues:)` 遇到重复 key 会 **运行时 trap**，`try?` **捕获不到**。

**触发条件：** 同步 / 编辑 `source-registry.json` 时出现重复 `numericId` 或 `source_id`。

**执行路径：** App `init` → `VodService()` → `SourceStore()` → trap → 进程退出。

**实际后果：** 冷启动即闪退，无法进入任何页面。  
**对比：** Android `associateBy` 重复 key 静默保留后者，不会崩，但会丢源。  
**修复建议：** `Dictionary(_:uniquingKeysWith:)` + 日志；或 init 抛可捕获错误并走空源 + 错误页。  
**验证方法：** 在 registry 插入重复 `numericId` 后冷启动。

---

### RISK-004

**等级：** P2  
**确定性：** Pad 直播错误 UI 为确定性问题；`streams.first()` 闪退为理论风险（当前 M3U 解析器跳过无 URL 行）  
**模块：** Android Pad 直播  
**文件：**

- `clients/android/app/src/main/kotlin/com/heibaimiao/multilivetv/ui/LiveScreen.kt` 第 55–68 行
- `clients/android/app/src/main/kotlin/com/heibaimiao/multilivetv/MainActivity.kt` 第 202–208 行
- `clients/android/app/src/main/kotlin/com/heibaimiao/multilivetv/player/PlayerScreen.kt` `LivePlayerScreen` 第 201–223 行

**问题：**

1. Pad 列表未走 `LiveCatalog.visibleGroups()`，TV 已过滤不可播放频道。
2. `channel.streams.first()` 无空守卫。模型与测试允许 `streams = emptyList()`（`LiveCatalogTest`）。
3. `LivePlayerScreen` 把 `ready = true` 写死，**没有** `onPlayerError`。播放失败仍显示完整播放壳，无错误文案、无重试。

**触发条件：** 直播流 404 / 超时 / 非媒体；或未来数据出现空 `streams`。

**实际后果：** 黑屏假播放，只能返回；空 streams 时 `NoSuchElementException` 闪退。  
**影响范围：** 仅 Pad。TV 使用 `getOrNull` + `LiveSessionController` failover + OSD「无法播放」。  
**修复建议：** Pad 对齐 `visibleGroups()`；`firstOrNull()`；为 Pad 直播注册错误监听并提供返回 / 换台。

---

### RISK-005

**等级：** P2  
**确定性：** 确定性问题  
**模块：** Apple tvOS Top Shelf  
**文件：** `TopShelfStore.swift`（`appGroupId`）；`MultiLiveTV-tvOS.entitlements` 与 `MultiLiveTVTopShelf.entitlements` 均为空 `<dict/>`  

**问题：** 代码写 App Group `group.com.heibaimiao.multilivetv`，entitlements **未声明** Application Groups。`containerURL` 返回 nil，保存失败。

**实际后果：** Apple TV 主屏 Top Shelf 永远空白。不 crash。Deep Link scheme 在 tvOS Info.plist 仍存在。  
**修复建议：** 主 App 与 Extension 声明同一 App Group。

---

### RISK-006

**等级：** P2  
**确定性：** 理论风险（大体积 HLS）  
**模块：** Apple tvOS 下载  
**文件：** `clients/apple/MultiLiveTV/Services/Download/HLSPlaylistDownloadEngine.swift` 第 53–57、85–97 行  

**问题：** 每个 TS 分片 `session.data` 整段进内存再 `data.write`。无流式落盘。

**触发条件：** 长剧集 / 高码率 m3u8，单片体积大。  
**实际后果：** 内存峰值过高 → tvOS Jetsam 杀进程（表现为闪退）。  
**修复建议：** `URLSession.download` 流式落盘；限制并发分片。

---

### RISK-007

**等级：** P2  
**确定性：** 确定性问题  
**模块：** Apple iPad Deep Link  
**文件：** `Info-iOS.plist` 无 `CFBundleURLTypes`；`Info-tvOS.plist` 第 37–48 行已注册 `multilivetv`  

**问题：** iPad 未注册 URL Scheme，系统不能把 `multilivetv://vod/...` 交给 App。Android Pad Manifest 已注册。  
**实际后果：** iPad 外链无法进详情。应用内 `pendingVod` 不受影响。

---

### RISK-008

**等级：** P2  
**确定性：** 确定性问题  
**模块：** Apple tvOS 下载续传  
**文件：** `HLSPlaylistDownloadEngine.swift` 第 72–78 行 `adoptExistingTasks()` / `waitForTask` 空实现或直接抛错  

**问题：** 切后台 / 杀进程后不能续传，restore 把 inflight 标回 queued 后 **全量重下**。与 RISK-006 叠加会反复 OOM。

---

### RISK-009

**等级：** P2  
**确定性：** 确定性问题  
**模块：** Apple 下载队列  
**文件：** `DownloadManager.swift` 第 289–296 行  

**问题：** `status = .resolving` 后，若 `parsePlay` 完成前用户删除任务，`deleteRequested` 分支 `return`，记录可能停在「解析中」，worker 不再处理该条。  
**实际后果：** 单条任务永久 resolving，需手动再删。不 crash。

---

### RISK-010

**等级：** P2  
**确定性：** 确定性问题  
**模块：** Android Pad + TV 搜索  
**文件：**

- `clients/android/app/src/main/kotlin/com/heibaimiao/multilivetv/ui/SearchScreen.kt` 第 48–64 行
- `clients/android/tv/src/main/kotlin/com/heibaimiao/multilivetv/ui/SearchScreen.kt` 第 59–74 行

**问题：** 连续点击「搜索」会启动多个 coroutine，无 generation、无 cancel。后发出的请求若先返回，先发出的慢请求会覆盖新结果。

**输入示例：** 先搜「流浪地球」再立刻搜「你好李焕英」，前者后返回则列表显示错误影片。  
**对比：** 首页 `HomeViewModel.loadGeneration` 会丢弃过期响应。

---

### RISK-011

**等级：** P2  
**确定性：** 理论风险  
**模块：** Android `:core` 网络  
**文件：** `clients/android/core/src/main/kotlin/com/heibaimiao/multilivetv/net/HttpClient.kt` 第 39–40 行  

**问题：** `response.body?.bytes()` 一次性读入内存。直播 `LiveService.fetchPlaylist` 走同一路径。超大 M3U 可能导致低内存设备 OOM。当前 `lives.json` 仅 1 条源。  
**修复建议：** 文本响应大小上限（如 5 MB）+ 超限报错并回退 bundle。

---

## 8. P3 问题

### RISK-012

**等级：** P3  
**确定性：** 确定性问题（能力缺口）  
**模块：** Apple 点播  
**文件：** `PlayerView.swift`（仅 AVPlayer）；直播才有 `VLCLivePlayer`  

探测把 `.flv` / MPEG-TS 视为可播，点播仍用 AVPlayer，失败后再 failover。直播有 VLC。最坏情况是 4 条线 × 15s 起播超时。最终有 `AppErrorView` 可重试。

---

### RISK-013

**等级：** P3  
**确定性：** 理论风险  
**模块：** Apple 点播  
**文件：** `PlayerView.swift` 第 177–189 行  

`parsePlay` 抛错时静默回退 `episode.url`（可能是网页）。多一轮无效探测。最终可 failover。Android 同类：`parsed?.url ?: candidate.episode.url`。

---

### RISK-014

**等级：** P3  
**确定性：** 确定性问题（配置错误时的降级策略）  
**模块：** 两端配置加载  

`VodService` / `LiveService` 对 Store 构造使用 `try?` / `runCatching` → 空列表。JSON 类型不符（例如 `numericId` 变成字符串）时 **不 crash**，首页 / 直播变成「资源站不可用 / 暂无内容」，用户易误判为网络问题。MacCMS **响应体** 已有 `flexInt` / `flexString`，配置文件没有同等容错。

---

### RISK-015

**等级：** P3  
**确定性：** 理论风险  
**模块：** Android `HomeFeed.kt` 第 159–161 行  

`map[bare]!!` 在 `map[bare] != null` 分支内。单线程当前逻辑安全。若合并键不变式被破坏可能 NPE。建议改为 `?: continue`。

---

### RISK-016

**等级：** P3  
**确定性：** 死代码路径  
**模块：** Android TV `player/PlayerScreen.kt` `LivePlayerScreen` 第 243 行  

`current.streams.first()` 无守卫。TV `MainActivity` **未导航到此 composable**（直播走 `ui/LiveScreen.kt`）。若未来复用会复现 RISK-004。

---

### RISK-017

**等级：** P3  
**确定性：** 确定性问题（产品缺口）  
**模块：** Android `DownloadsScreen.kt`  

仅文案「离线下载将在后续版本提供」。不是 crash。Apple 有完整下载。两端能力不一致。

---

### RISK-018

**等级：** P3  
**确定性：** 理论风险  
**模块：** Apple `RemoteImageLoader.swift` 第 67–74 行  

`await task.value` 若因调用方取消抛 `CancellationError`，不清理 `inflight[url]`。首页快速滑动时，未完成的 unstructured `Task` 可能残留在 map 中直到再次请求同一 URL。NSCache 有 40 MB 上限，inflight 没有。不构成启动崩溃。

`AsyncGate.enter()` 使用无 cancellation handler 的 `withCheckedContinuation`。滑动取消等待中的图片加载时，continuation 依赖后续 `leave()` 才恢复。当前 `download` 的 `catch` 会 `leave()`，更可能造成多余网络，而不是永久死锁。仍建议改成 `withTaskCancellationHandler`。

---

### RISK-019

**等级：** P3  
**确定性：** 确定性问题（重复触发）  
**模块：** Apple `LiveView.swift` 第 48–56 行  

`.task` 与 `.onAppear` 都会 `startCurrentChannel()`。切 Tab 回来可能重复起播。有 generation 防护，主要是多余探测 / 闪一下。

---

### RISK-020

**等级：** P3  
**确定性：** 确定性问题（恢复弱）  
**模块：** Android 搜索错误态  

`error != null` 只显示文案，没有「重试」按钮。用户可再点搜索，**能恢复**，但不如首页 / 详情明确。Apple 搜索错误页有 `AppErrorView` 重试（同时踩 RISK-001 的 refreshable）。

---

## 9. 白屏专项

| 页面 | 触发 | 原因 | 位置 | 恢复 |
| --- | --- | --- | --- | --- |
| Apple 搜索 | 下拉刷新取消 | `isSearching` 不复位 | SearchView 106–133 | 差：需杀进程 / 重建 View |
| Android Pad 直播播放 | 流失败 | `ready=true` 无 error | LivePlayerScreen 215–223 | 差：只能返回 |
| Apple / Android 首页 | 全源失败 | 有 ErrorView + 重试 | HomeView / HomeViewModel | 好 |
| Apple tvOS 启动 | 首页失败 | `LaunchLoadingView` 重试 | MultiLiveTVApp 110–117 | 好 |
| 配置损坏 | JSON 解码失败 | 静默空源，像「没内容」 | VodService init | 中：有文案但易误判 |
| Top Shelf | App Group 缺失 | 主屏空白，非 App 内白屏 | entitlements | 不适用 |

Compose / SwiftUI 列表普遍使用空数组默认值，未发现 `data.list.map` 在 `list == null` 时的典型白屏。详情页 `detail!!` 均在 `detail != null` 分支内。

---

## 10. Crash 专项

| 模块 | 异常 | 触发 | 位置 | 确定性 |
| --- | --- | --- | --- | --- |
| Apple SourceStore | Swift uniqueKeys trap | 重复 numericId / source_id | SourceStore.swift 11–12 | 代码确定，当前 JSON 未触发 |
| Android Pad livePlayer | NoSuchElementException | `streams` 为空 | MainActivity.kt 207 | 理论：当前解析器不生成空 streams |
| Android TV 死代码 LivePlayerScreen | 同上 | 若将来导航到该 composable | PlayerScreen.kt 243 | 当前未引用 |
| 强制解包 `!!` / `as!` | — | UI 层均有前置守卫；`try!` 仅静态正则 | 多处 | 未报 P1 |
| `PlaybackRequest` 空 candidates | 插入空 URL 占位 | 无线路 | Apple PlayerView.swift 23–25 | 走进 failover / 错误页，不崩 |

---

## 11. 异常退出专项

| 场景 | 机制 | 等级 |
| --- | --- | --- |
| tvOS 大 HLS 下载 | Jetsam（内存） | P2 RISK-006 |
| Android 超大 M3U | OOM | P2 RISK-011 |
| 未发现 | `fatalError` / `abort` / `System.exit` / `Process.kill` 业务调用 | — |

Apple 无 `fatalError` / `precondition` 于 App 主工程。`try!` 仅用于编译期确定合法的 `NSRegularExpression`。

---

## 12. 溢出专项

| 点 | 结论 |
| --- | --- |
| 进度条 `position / duration` | Android `VodPlayerHud` / Overlay 在 `durationMs > 0` 时才除；Apple `CMTime` 检查 `isFinite` |
| `flexInt` Double → Int | Kotlin `toInt()` 饱和，不抛 |
| `CategoryListService` `sumOf { total }` | 多源夸张 `total` 可使 Int 回绕为负，影响分页感知。**P3**，未单列 ID |
| 分页 page 参数 | 来自内部递增，有 `pageCount` 上限意识；未见 `page * pageSize` 无界 int |

---

## 13. 内存专项

| 资源 | 上限 | 增长条件 | 超限行为 |
| --- | --- | --- | --- |
| Apple RemoteImage NSCache | count 300 / 40 MB | 海报 | 系统逐出 |
| Apple URLCache（图片） | 内存 20 MB / 磁盘 80 MB | HTTP 缓存 | 系统逐出 |
| Apple inflight 图片 Task | 无 | 快速滑动取消 | RISK-018 |
| tvOS HLS 分片 `Data` | 无 | 大分片 | RISK-006 Jetsam |
| OkHttp 响应 body | 无 | 大 M3U / 异常 HTML | RISK-011 |
| WatchHistory JSON | Apple `prefix(maxSize)` | 播放 | 有裁剪 |
| ExoPlayer / AVPlayer | 页销毁 release / teardown | 正常 | Pad/TV VOD `onDispose` 有 `release()` |

---

## 14. CPU 专项

未发现无界 `while true` 热循环。

| 循环 | 退出 |
| --- | --- |
| Apple `LivePlaybackSession.runProbeLoop` | HTTP 202 最多 5 次；其它 decision 立即 return |
| Android / Apple HUD `while(true)` + `delay` | 随 `LaunchedEffect` / Task 取消 |
| `CategoryListService` `while (jobs.any { isActive })` | `FIRST_PAINT_MS` / `PER_CALL_TIMEOUT_MS` + `finally` cancel |
| RemoteImage 重试 | 最多 3 次 |

首页多源 fan-out 有 semaphore 与超时，**不是**重试风暴。采集站持续失败时表现为超时后错误页，而不是打爆 CPU。

---

## 15. 并发专项

| 问题 | 等级 |
| --- | --- |
| Android 点播 `onPlayerError` 捕获过期 index | P1 RISK-002 |
| Android 搜索无 generation | P2 RISK-010 |
| Apple 搜索取消不清 loading | P1 RISK-001 |
| Apple 下载删除 vs resolving | P2 RISK-009 |
| Android `HomeViewModel.loadGeneration` | 正确丢弃过期首页响应 |
| Apple `HomeView.fetchPage` generation + defer | 正确 |
| TV 直播 `DisposableEffect(player)` 捕获 `groups` | 列表刷新后 listener 可能找不到频道 → OSD 错误。P3，弱于 RISK-002 |

未发现典型双锁死锁。共享 OkHttp / URLSession 单例合理。

---

## 16. 网络异常专项

| 依赖 | 超时 | 重试 | 失败表现 |
| --- | --- | --- | --- |
| Apple MacCMS URLSession | 15s | 无自动重试 | 多源并行，部分失败仍可出列表 |
| Android OkHttp | connect 5s，read/call 8s | 无 | 全失败 → 中文错误 + 重试（首页/详情） |
| Android ResilientDns | DoH 5s | 系统 DNS 失败才 DoH（阿里） | UnknownHost → 用户文案 |
| 分类 fan-out | 单源 5s，首屏约 4s | 无 | 部分成功即展示 |
| 图片 Apple | 15s × 最多 3 次（408/429/5xx/网络） | 有界 | 占位失败态 |
| jx 解析 | 随请求超时 | 失败回退原始 URL | RISK-013 |
| 直播 M3U | 同上 HTTP | 多源 merge | 空列表 + 重试 |

**无限重试：** 未发现业务层对 MacCMS 的 while-retry。  
**502/HTML：** `parseToJsonElement` / `JSONSerialization` 失败后向上抛，被列表/搜索的 `runCatching` 或 UI `catch` 吃掉，不会崩。  
**HTTP 明文：** 两端允许 cleartext / `NSAllowsArbitraryLoads`（无冲突 key）。采集站常用 HTTP，属于产品选择，不是 crash。Apple 逻辑测试含 ATS 校验并通过。

---

## 17. 数据异常专项

MacCMS 列表 / 详情（Android `MacCMSJsonParser`，Apple `MacCMSJSONParser`）：

| 输入 | 行为 |
| --- | --- |
| `{}` | 空 list，不崩 |
| `data: null` / 无 list | 空列表 |
| `code` 为 `"200"` 或缺省 | flex 解析 |
| 非法 JSON / HTML | 抛错 → UI 错误或该源跳过 |
| `vod_name` 缺失 | 该条 skip |
| 超长字符串 | 原样展示，未见 substring(0,10) 硬切 |

配置 JSON（registry / lives）**没有** flex 类型。字段类型变化 → 整表加载失败 → 空源（RISK-014）。

---

## 18. 数据库专项

客户端无 SQLite/Room/Core Data 业务库。观看历史为 JSON 文件。解码失败 → 空历史（Android `WatchHistoryStore` `runCatching`；Apple 同类）。**无连接池耗尽问题。**

---

## 19. Redis 专项

未使用。

---

## 20. 文件 IO 专项

| 路径 | 风险 |
| --- | --- |
| Apple 下载 HLS 分片整包 `Data` | RISK-006 |
| Apple `FileDownloadEngine` background session | iOS 较完整；tvOS HLS 引擎无续传 RISK-008 |
| 历史 / 下载清单 JSON | 小文件；损坏则空或跳过 |
| Android `HttpClient` 整包 bytes | RISK-011 |
| 临时文件 | tvOS 删除任务会 `removeItem`；resolving 中途 return 可能留下半成品目录（并入 RISK-009） |

---

## 21. UI 专项

| 端 | 空态 / 错误 / 重试 |
| --- | --- |
| Apple 首页 | skeleton / AppErrorView / 空态 |
| Apple 详情 | 有错误重试；`onPrimary` 可先出部分详情 |
| Apple 搜索 | 错误可重试，但 refresh 踩 RISK-001 |
| Apple 直播 | 配置错误 / 空 / loading / 播放 overlay |
| Android 首页 | loading / error 重试 / pull-to-refresh（Pad）；TV 无下拉刷新（体验 P3） |
| Android 详情 | loading / 重试 |
| Android 搜索 | 错误无重试按钮 RISK-020 |
| Android Pad 直播播放 | 无错误态 RISK-004 |
| Android 下载 Tab | 占位文案 RISK-017 |

焦点：TV `HomeFocusPolicy` 有单测。Pad 直播是普通列表，无焦点卡死面。

---

## 22. 生命周期专项

| 点 | 结论 |
| --- | --- |
| Apple PlayerView `onDisappear` | `playbackGeneration++`、写历史、`teardownPlayer` |
| Android VOD Player | `onDispose` `release()` |
| Android TV 直播 | `removeListener`；player 由 LiveScreen 持有 |
| Apple LiveView `onDisappear` | `session.deactivate()` |
| 图片 `.task(id: url)` | 视图消失取消 await；fetch Task 可能继续（RISK-018） |
| 搜索 refreshable | 取消不清 flag（RISK-001） |
| iPad `UIApplicationSupportsMultipleScenes = true` | 多窗口共享 App 级 `StateObject`。未做双窗口播放隔离。P3 体验 |

---

## 23. 第三方依赖专项

| 服务 | 位置 | 超时 | 失败能否继续 | 类型 |
| --- | --- | --- | --- | --- |
| MacCMS 采集站 | 首页 / 搜索 / 详情 | 8–15s | 多源部分成功可继续；全挂则错误页 | **核心**，可部分降级 |
| jx_url 解析站 | 取播 | 同 HTTP | 回退原始 URL | 非核心，可降级 |
| M3U 直播源 | 直播 Tab | 同 HTTP | 直播不可用，点播不受影响 | 直播核心，点播可降级 |
| 阿里 DoH | Android DNS | 5s | 系统 DNS 成功则不用 | 非核心 |
| VLCKit | Apple 直播 FLV/TS | — | 中文错误 + 重试 | 直播部分格式核心 |
| Media3 / AVPlayer | 点播 | 起播超时 15s（Apple） | failover / 错误页 | **核心** |
| Coil | Android 海报 | 共用 OkHttp | 占位图 | 非核心 |
| bpz5 / Go API | 客户端 **不调用** | — | — | 不适用 |

**若全部采集站挂掉：** 两端点播不能浏览，但 App 能启动并显示错误 / 重试。  
**若仅直播 M3U 挂掉：** 点播仍可用。

---

## 24. 配置专项

| 文件 | 现状 |
| --- | --- |
| `source-registry.json` | 33 源，id 唯一，全部 `enabled: true` |
| `lives.json` | 1 条 |
| `unified-categories.json` / `play-line-weights.json` | 两端内嵌；解码失败走默认 / 空树 |
| Apple ATS | 仅 `NSAllowsArbitraryLoads=true`，无冲突 key（脚本已测过） |
| Android `usesCleartextTraffic=true` | 明文 HTTP 可播 |
| Apple Top Shelf entitlements | 空，与代码 App Group 不一致 RISK-005 |
| iPad URL Scheme | 未注册 RISK-007 |
| Android minSdk 23 + Conscrypt | TLS 旧设备有补丁 |

重复 id：Apple trap（RISK-003），Android 静默覆盖。

---

## 25. 日志专项

客户端几乎无持久化日志框架。用户可见错误走 `RequestFailure` 中文文案。未发现 `while` + `print` 刷盘。敏感 Token：客户端无登录，无 JWT。下载 / 播放 URL 可能进历史 JSON（本地）。

---

## 26. 异常恢复能力

| 场景 | 失败后 | 能否点侧重试恢复 |
| --- | --- | --- |
| 首页加载 | 错误页 | 是 |
| 分类切换 | 缓存 + 软刷新 / 错误 | 是 |
| Apple 搜索取消 | 永久骨架 | **否（RISK-001）** |
| Android 搜索错误 | 文案 | 是（再点搜索） |
| Android 搜索竞态 | 错数据 | 是（再搜一次） |
| 详情 | 重试按钮 | 是 |
| Android 点播 ExoPlayer 错 | 停在坏线 | **否自动恢复（RISK-002）**，返回重进可以 |
| Apple 点播 | 错误页重试从 index 0 | 是 |
| Pad 直播播放失败 | 假 ready 黑屏 | **否（RISK-004）**，返回可以 |
| TV 直播 | OSD「无法播放」+ 换台 / 换流 | 是 |
| Apple 下载 resolving 卡住 | 单条任务 | 弱（需删除） |

---

## 27. 数据一致性

| 场景 | 结论 |
| --- | --- |
| 历史进度 | 播放中定时写入；退出 force 写。旧请求覆盖新请求主要在搜索（RISK-010），首页有 generation |
| 多窗口 iPad | 共享 DownloadManager / History |
| 配置 vs 运行时 | 源健康分 `SourceHealthStore` 内存态，杀进程重置 |
| 无服务端收藏 | 不存在前后端字段登录态不一致 |

---

## 28. 幂等性

无支付 / 无账号写操作。搜索连点：Android 重复请求（RISK-010）；Apple `startSearch` 会 cancel 上一次。下载入队有 `DownloadEnqueuePolicy` 去重（脚本 `verify-downloads.swift`）。历史 `save` 按 videoId 覆盖，连点播放不会复制多条核心记录（以 Store 实现为准）。

---

## 29. 异常路径覆盖表

| 场景 | 正常 | 空数据 | 网络失败 | 超时 | 服务器异常 | 恢复 |
| --- | --- | --- | --- | --- | --- | --- |
| Apple/Android 首页加载 | ✓ | ✓ 空态 | ✓ 错误+重试 | ✓ | ✓ 单源跳过 | ✓ |
| Apple tvOS 启动页 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Apple 搜索 | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ 取消后卡骨架 |
| Android 搜索 | ✓ | ✓ | ✓ 文案 | ✓ | ✓ | ? 无重试按钮，可再搜；竞态 ✗ |
| 详情 | ✓ | ✓ 无线路文案 | ✓ | ✓ | ✓ | ✓ |
| Apple 点播 | ✓ | 占位空 URL→错误 | failover | 15s 起播 | failover | ✓ 错误页 |
| Android 点播 | ✓ | ✓ | 探测换线 | call 8s | Exo 错误 | ✗ RISK-002 |
| Apple 直播 | ✓ | ✓ | ✓ | ✓ | VLC/换 URL | ✓ |
| Android TV 直播 | ✓ | ✓ 过滤 | OSD | ✓ | 换流 | ✓ |
| Android Pad 直播 | ✓ 列表 | ? 不过滤 | 列表可重试 | ✓ | 播放无 UI | ✗ 播放失败 |
| 历史恢复 | ✓ | ✓ | catch 文案 | ✓ | ✓ | ✓ |
| Apple 下载 | ✓ | 拒绝入队 | failed | 30s/分片 | failed | 弱（tvOS 重下） |
| Android 下载 | — | — | — | — | — | 未实现 |
| Deep Link iPad | — | — | — | — | — | ✗ 系统不唤起 |
| Top Shelf | — | 空白 | — | — | — | ✗ |

图例：✓ 代码能证明已处理；✗ 明确问题；? 无法从 UI 代码完全证明。

---

## 30. 故障场景表

| ID | 风险 | 等级 | 触发条件 | 后果 | 文件 | 行号 |
| --- | --- | --- | --- | --- | --- | --- |
| RISK-001 | 永久 Loading | P1 | iPad 搜索中下拉刷新取消 | 骨架屏卡死 | SearchView.swift | 106–133 |
| RISK-002 | failover 失效 | P1 | 多线路 ExoPlayer 连续报错 | 播放卡死，不自动换线 | app/tv PlayerScreen.kt | 88–98 / 122–132 |
| RISK-003 | 启动 trap | P2 | registry 重复 id | 闪退 | SourceStore.swift | 11–12 |
| RISK-004 | 直播无错误态 / first() | P2 | 流失败或空 streams | 黑屏或理论闪退 | MainActivity.kt / LivePlayerScreen | 207 / 201–223 |
| RISK-005 | App Group 缺失 | P2 | 任意 tvOS 构建 | Top Shelf 空白 | entitlements | 空 dict |
| RISK-006 | 整包分片内存 | P2 | 大 HLS 下载 | Jetsam 退出 | HLSPlaylistDownloadEngine.swift | 53–57 |
| RISK-007 | 无 URL Scheme | P2 | iPad 打开 multilivetv:// | 无法进 App | Info-iOS.plist | 无 CFBundleURLTypes |
| RISK-008 | 无续传 | P2 | tvOS 下载中切后台 | 全量重下 | HLSPlaylistDownloadEngine.swift | 72–78 |
| RISK-009 | 状态机提前 return | P2 | 解析中删除下载 | 永久 resolving | DownloadManager.swift | 291–296 |
| RISK-010 | 旧请求覆盖 | P2 | 连续搜索 | 结果错乱 | SearchScreen.kt | 48–64 / 59–74 |
| RISK-011 | 整包 HTTP body | P2 | 超大 M3U | OOM | HttpClient.kt | 39–40 |
| RISK-012 | 点播无 VLC | P3 | FLV 直链 | 长时间失败后错误页 | PlayerView.swift | 216+ |
| RISK-013 | 解析失败回退网页 URL | P3 | jx 超时 | 额外超时 | PlayerView.swift | 177–189 |
| RISK-014 | 配置静默空源 | P3 | JSON 类型错误 | 像没内容 | VodService init | — |
| RISK-015 | `!!` | P3 | 合并键不变式破坏 | 理论 NPE | HomeFeed.kt | 161 |
| RISK-016 | 死代码 first() | P3 | 将来复用 TV LivePlayerScreen | 闪退 | tv PlayerScreen.kt | 243 |
| RISK-017 | 下载未做 | P3 | 打开 Android 下载 Tab | 占位 | DownloadsScreen.kt | 7–10 |
| RISK-018 | inflight 泄漏 | P3 | 快速滑动海报 | 内存缓增 | RemoteImageLoader.swift | 67–74 |
| RISK-019 | 重复起播 | P3 | 直播 Tab 反复出现 | 多余探测 | LiveView.swift | 48–56 |
| RISK-020 | 搜索错误无按钮 | P3 | 搜索失败 | 体验差，可再搜 | SearchScreen.kt | 68 / 79 |

---

## 31. 修复优先级建议

1. **上线前建议修：** RISK-001（Apple 搜索卡死）、RISK-002（Android 点播 failover）。
2. **直播 / 下载体验：** RISK-004（Pad 直播错误与守卫）、RISK-006 / RISK-008 / RISK-009（tvOS 下载）。
3. **配置与分发：** RISK-003（重复 id 防 trap）、RISK-005（Top Shelf）、RISK-007（iPad scheme）。
4. **可迭代：** 搜索 generation（RISK-010）、HTTP 体积上限、点播 VLC、Android 下载、图片 gate 取消。

---

## 32. 最终审计结论

两端都是「内嵌源、直连采集站」的离线可启动客户端。首页 / 详情 / Apple 直播 / Android TV 直播在网络失败、空列表、超时上 **大多有错误页和重试**。MacCMS JSON 对 int/string 混用做了 flex 解析。网络层有明确超时，没有对采集站的无限重试。

真正会把用户卡死、且代码路径已经闭合的，是：

1. **iPad 搜索刷新取消后永久骨架屏**（局部功能不可用，只能杀进程）。
2. **Android 点播第二条起 ExoPlayer 报错后 failover 算错 index**（多线路自动换线失效）。

其次是 Pad 直播播放失败没有错误态、tvOS 下载内存与续传、以及配置重复 id 会让 Apple **整 App 起不来**（当前包内未触发）。

未根据主观感觉打分。以上均来自源码路径；理论项已标明。

---

## 附录 A. 扫描规模

| 项 | 数量 |
| --- | --- |
| Apple Swift（App + TopShelf） | 70 文件 / 11,755 行 |
| Apple 逻辑测试脚本 | 3 文件 / 3,143 行 |
| Android Kotlin（app + tv + core 含单测） | 82 文件 / 10,894 行 |
| 合计（上述源码） | **约 25,792 行** |
| 另读 | Manifest、plist、entitlements、`source-registry.json`、`lives.json`、Gradle / XcodeGen |

检索模式包括：`fatalError` / `try!` / `as!` / `!!` / `requireNotNull` / `while true` / `.first()` / `[0]` / `bytes()` / `uniqueKeysWithValues` / refreshable / ExoPlayer `onPlayerError`。

---

## 附录 B. 已运行验证

| 命令 | 结果 |
| --- | --- |
| `clients/apple/scripts/run-logic-tests.sh` | `ATS plist check passed`；`VERIFY CLIENT LOGIC PASSED` |
| `clients/android ./gradlew :core:test` | **本环境未跑通**（sandbox 无法写 wrapper lock / 拉 Gradle 发行包）。仓库内已有 15 个 `:core` 测试类，覆盖分类超时、DNS、LiveCatalog 空 streams、历史损坏 JSON、播放 HUD 等。 |

---

## 附录 C. 统计（汇报用）

```text
扫描文件：
Apple Swift 70 + 脚本 3 + Android Kotlin 82 + 配置 / Manifest / plist（只读抽查）

扫描代码行：
约 25,792（客户端源码 + Android 单测 + Apple 逻辑脚本）

发现风险：
P0：0
P1：2
P2：9
P3：8

白屏风险：2（永久 Loading / 假 ready）
Crash风险：2（重复 id trap；空 streams first()）
异常退出风险：1（Jetsam）
溢出风险：1（Int total 累加，P3）
内存风险：3
并发风险：3
网络异常风险：以恢复/failover 缺陷为主，无无限重试
数据异常风险：配置严格解码静默空源；业务 JSON 有 flex
```

**最需要关注：** RISK-001、RISK-002，其次 RISK-004 与 tvOS 下载（RISK-006 / RISK-008）。
