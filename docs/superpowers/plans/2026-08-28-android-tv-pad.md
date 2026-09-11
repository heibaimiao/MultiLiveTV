# Android TV / Android Pad 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 按现有 Apple TV + iPad 客户端的功能与架构，在 `clients/android` 重建 Android TV 与 Android Pad 原生 App：内嵌 MacCMS 多源聚合，不依赖 Go 后端。

**架构：** 一个 Gradle 工程、两套 UI、一份业务核心。`:core` 是纯 Kotlin JVM 模块，从 Apple 的 `Services/` 一对一移植（MacCMS、合并、解析、首页 Feed、直播 M3U、下载策略），用 JVM 单测锁行为。`:app` 是平板触控（对应 iPad），`:tv` 是 10-foot 遥控器（对应 tvOS）。播放走 Media3（HLS/MP4）+ LibVLC（HTTP-FLV / UDPXY），与 Apple 的 AVPlayer + VLCKit 分工一致。

**技术栈：** Kotlin 2.0、AGP 8.7、Jetpack Compose（Pad 用 Material3，TV 用 `androidx.tv:tv-material`）、OkHttp、kotlinx.serialization、Coil、Media3 ExoPlayer、libvlc-android、JUnit 5。

---

## 背景（工程师必读）

Apple 客户端在 `clients/apple/`：

- 单一 SwiftUI 源码树，两个 Xcode target：`MultiLiveTV-iOS`（`TARGETED_DEVICE_FAMILY: 2`，仅 iPad）与 `MultiLiveTV-tvOS`。
- **不调用** `localhost:8080` Go API。资源站写在打包进 App 的 `sources.json`，直播源在 `lives.json`。
- 业务逻辑可用无 UI 的 `swiftc` 脚本验证：`clients/apple/scripts/run-logic-tests.sh` → `verify-client-logic.swift`。这是 Android 移植的**行为契约**，不是参考实现。
- 现有 `clients/android/` 只有 3 个 Kotlin 文件，通过 Retrofit 打 Go API，是过期 MVP。本计划**整目录重写**，不要在旧 `MainActivity` 上打补丁。

平台对照：

| Apple | Android |
| --- | --- |
| iPad（触控、Tab：首页/直播/搜索/下载） | Android Pad `:app` |
| tvOS（焦点、启动闸门、货架首页、遥控器） | Android TV `:tv` |
| `com.heibaimiao.multilivetv` | 同包名 `:app` |
| `com.heibaimiao.multilivetv.tv` | 同包名 `:tv` |
| AVPlayer | Media3 ExoPlayer |
| VLCKit（FLV / UDPXY） | libvlc-android |
| iOS `AVAssetDownloadTask` | Pad：Media3 DownloadHelper |
| tvOS `HLSPlaylistDownloadEngine` | TV：自研 playlist 本地化（与 Apple TV 相同策略） |
| Top Shelf 扩展 | **v1 不做**（二期 Watch Next） |
| `multilivetv://vod/{sourceId}/{vodId}` | 同样 scheme |

明确不做（YAGNI，与当前 Apple App 对齐）：

- 登录 / JWT / 收藏（E2E.md 里的登录条目已过期，Apple 源码无 auth）
- 依赖 Go API
- 手机优先竖屏（Pad 以平板横竖屏为主，允许手机跑，但不为小屏单独设计）
- Top Shelf / Android TV 推荐频道
- Kotlin Multiplatform 与 Swift 共享（两端语言不同，收益为零）

---

## 方案选择（已锁定）

曾考虑三种做法：

1. **推荐：Compose 双模块 + 内嵌 MacCMS（本计划）**  
   与 Apple「一份逻辑、两套壳」一致。Pad/TV 可独立安装、独立上架。核心可在无模拟器的 JVM 上测。
2. **继续打 Go API**  
   现有 Android MVP 的路。要额外部署后端，和已上线的 Apple 行为分叉，解析/合并会漂。否决。
3. **单 APK + `uiMode` 自适应**  
   一套代码判断 TV/平板。Play 上架 TV 需要 `LEANBACK_LAUNCHER` 与无触控证明，和触控 Pad 挤在一个 APK 里会互相拖累。否决。

---

## 将创建或修改的文件

重写后的树（旧的 `MainActivity.kt` / `ApiConfig.kt` / `ApiModels.kt` 删除）：

```
clients/android/
  settings.gradle.kts
  build.gradle.kts
  gradle.properties
  README.md
  core/                          # 纯 JVM，无 Android SDK
    src/main/kotlin/com/heibaimiao/multilivetv/...
    src/main/resources/sources.json   # 从 Apple 复制
    src/main/resources/lives.json
    src/test/kotlin/...
  playback/                      # Android library：播放 + 下载引擎
    src/main/kotlin/...
  app/                           # Android Pad
    src/main/AndroidManifest.xml
    src/main/res/
    src/main/kotlin/.../ui/
  tv/                            # Android TV
    src/main/AndroidManifest.xml
    src/main/res/
    src/main/kotlin/.../ui/
```

`:core` 文件与 Apple 对照（职责一一对应，不要发明第二套算法）：

| Android `:core` | Apple 源 |
| --- | --- |
| `model/Models.kt` | `Models/Models.swift` |
| `model/DownloadRecord.kt` | `Models/DownloadRecord.swift` |
| `source/SourceStore.kt` | `Services/SourceStore.swift` |
| `net/NetworkConfig.kt` | `Services/NetworkConfig.swift` |
| `maccms/MacCMSModels.kt` + `MacCMSClient.kt` + `MacCMSJsonParser.kt` | 同名 Swift |
| `merge/VodMergeService.kt` | `VodMergeService.swift` |
| `parser/PlayParser.kt` | `PlayParser.swift` |
| `home/HomeFeed.kt` + `HomeLaunch.kt` | 同名 |
| `category/CategoryTree.kt` + `CategoryMatch.kt` + `CategoryListService.kt` | 同名 |
| `vod/VodService.kt` | `VodService.swift` |
| `live/LiveModels.kt` + `LiveStore.kt` + `M3UPlaylistParser.kt` + `HLSPlaylistProbe.kt` | `Services/Live/` |
| `download/DownloadEnqueuePolicy.kt` + `DownloadStore.kt` | `Services/Download/` |
| `deeplink/AppDeepLink.kt` | `TopShelf/AppDeepLink.swift` |
| `display/VodDisplayFormatter.kt` | `VodDisplayFormatter.swift` |

`:playback`：`Media3VodPlayer.kt`、`VlcLivePlayer.kt`、`LivePlaybackSession.kt`、`FileDownloadEngine.kt`、`HlsDownloadEngine.kt`（Pad）、`HlsPlaylistDownloadEngine.kt`（TV）、`DownloadManager.kt`。

`:app` / `:tv` 只放 Compose UI 与 Application，禁止把 MacCMS 请求写进 Composable。

---

### 任务 1：Gradle 多模块脚手架

**文件：**
- 创建：`clients/android/settings.gradle.kts`
- 创建：`clients/android/build.gradle.kts`
- 创建：`clients/android/gradle.properties`
- 创建：`clients/android/core/build.gradle.kts`
- 删除：`clients/android/app/src/main/java/com/heibaimiao/multilivetv/MainActivity.kt`
- 删除：`clients/android/app/src/main/java/com/heibaimiao/multilivetv/ApiConfig.kt`
- 删除：`clients/android/app/src/main/java/com/heibaimiao/multilivetv/ApiModels.kt`

- [ ] **步骤 1：写失败的模块存在性检查**

在 `clients/android/core/src/test/kotlin/com/heibaimiao/multilivetv/SmokeTest.kt`：

```kotlin
package com.heibaimiao.multilivetv

import kotlin.test.Test
import kotlin.test.assertEquals

class SmokeTest {
    @Test
    fun coreModuleCompiles() {
        assertEquals("MultiLiveTV", "MultiLiveTV")
    }
}
```

- [ ] **步骤 2：写 Gradle 文件**

`settings.gradle.kts`：

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "MultiLiveTV"
include(":core")
```

根 `build.gradle.kts`：

```kotlin
plugins {
    kotlin("jvm") version "2.0.21" apply false
    kotlin("plugin.serialization") version "2.0.21" apply false
}
```

`gradle.properties`：

```
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
kotlin.code.style=official
```

`core/build.gradle.kts`：

```kotlin
plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}
java {
    toolchain { languageVersion.set(JavaLanguageVersion.of(17)) }
}
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation(kotlin("test"))
}
tasks.test { useJUnitPlatform() }
```

先**不要**加 `:app` / `:tv` / `:playback`。先让 JVM 核心可测。

- [ ] **步骤 3：运行测试确认通过**

```bash
cd clients/android && ./gradlew :core:test --tests com.heibaimiao.multilivetv.SmokeTest
```

预期：PASS。若没有 wrapper，用 Android Studio 打开 `clients/android` 生成，或 `gradle wrapper --gradle-version 8.11.1`。

- [ ] **步骤 4：Commit**

```bash
git add clients/android
git commit -m "$(cat <<'EOF'
chore(android): 重建 Gradle 多模块脚手架，去掉过期 Go API MVP

EOF
)"
```

---

### 任务 2：SourceStore + 资源 JSON

**文件：**
- 创建：`clients/android/core/src/main/kotlin/com/heibaimiao/multilivetv/model/Source.kt`
- 创建：`clients/android/core/src/main/kotlin/com/heibaimiao/multilivetv/source/SourceStore.kt`
- 创建：`clients/android/core/src/main/resources/sources.json`（从 `clients/apple/MultiLiveTV/Resources/sources.json` 原样复制）
- 测试：`clients/android/core/src/test/kotlin/com/heibaimiao/multilivetv/source/SourceStoreTest.kt`

对照 `clients/apple/MultiLiveTV/Services/SourceStore.swift`。JSON 字段是 snake_case：`jx_url`、`vip_only`。

- [ ] **步骤 1：编写失败的测试**

```kotlin
@Test
fun enabledDropsFlagAndVip() {
    val store = SourceStore(
        listOf(
            Source(1, "A", "https://a/", flag = 0, jxUrl = null, vipOnly = false),
            Source(2, "B", "https://b/", flag = 1, jxUrl = null, vipOnly = false),
            Source(3, "C", "https://c/", flag = 0, jxUrl = null, vipOnly = true),
        )
    )
    assertEquals(listOf(1), store.enabled().map { it.id })
    assertEquals(1, store.default()?.id)
    assertEquals(null, store.byId(2))
}
```

- [ ] **步骤 2：运行确认失败**

```bash
./gradlew :core:test --tests com.heibaimiao.multilivetv.source.SourceStoreTest
```

预期：FAIL，`SourceStore` 未定义。

- [ ] **步骤 3：最少实现**

```kotlin
@Serializable
data class Source(
    val id: Int,
    val name: String,
    val url: String,
    val flag: Int = 0,
    @SerialName("jx_url") val jxUrl: String? = null,
    @SerialName("vip_only") val vipOnly: Boolean? = false,
)

class SourceStore(private val sources: List<Source>) {
    fun all(): List<Source> = sources
    fun enabled(): List<Source> = sources.filter { it.flag == 0 && it.vipOnly != true }
    fun byId(id: Int): Source? = enabled().firstOrNull { it.id == id }
    fun default(): Source? = enabled().firstOrNull()

    companion object {
        fun fromJson(text: String): SourceStore {
            val json = Json { ignoreUnknownKeys = true }
            return SourceStore(json.decodeFromString(text))
        }
    }
}
```

classpath 加载：`SourceStore.fromJson(checkNotNull(this::class.java.classLoader.getResource("sources.json")).readText())`。

- [ ] **步骤 4：测试通过后 Commit**

```bash
git add clients/android/core
git commit -m "$(cat <<'EOF'
feat(android): 移植 SourceStore 与 sources.json

EOF
)"
```

---

### 任务 3：PlayParser（线路 / 选集 / jx_url）

**文件：**
- 创建：`clients/android/core/src/main/kotlin/com/heibaimiao/multilivetv/parser/PlayParser.kt`
- 测试：`PlayParserTest.kt`

对照 `clients/apple/MultiLiveTV/Services/PlayParser.swift`。**逐条翻译** `verify-client-logic.swift` 里所有 `testParse*` / `testPlaySource*`，不要凭记忆重写规则。关键行为：

- `vodPlayFrom` 按 `$$$` 或 `,` 切线路名
- `vodPlayURL` 按 `$$$` 切线路，`#` 切集，`$` 切「集名$url」
- 线路显示名走 `playSourceNames` / 前缀表（无尽、猫眼、虎牙…）
- `mergePlaySources` 跨源去重
- `parsePlay`：直链 `.m3u8/.mp4/.mkv/.flv/.mov` 不走解析器；否则拼 `jx_url`

- [ ] **步骤 1：先抄一条契约测试**

从 `verify-client-logic.swift` 找 `testParsePlayURL` 一类断言，写成 Kotlin。例如「`$$$` 两条线路、`#` 两集」。

- [ ] **步骤 2：运行失败 → 按 Swift 实现 Kotlin → 再跑全套 parser 测试**

```bash
./gradlew :core:test --tests com.heibaimiao.multilivetv.parser.PlayParserTest
```

预期：全部 PASS，条数应覆盖 Swift 脚本中 parser 相关用例。

- [ ] **步骤 3：Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(android): 移植 PlayParser 线路解析与 jx_url 规则

EOF
)"
```

---

### 任务 4：HomeFeed + VodMerge + CategoryTree

**文件：**
- 创建：`home/HomeFeed.kt`、`home/HomeLaunch.kt`
- 创建：`merge/VodMergeService.kt`
- 创建：`category/CategoryTree.kt`、`category/CategoryMatch.kt`
- 测试：从 `verify-client-logic.swift` 移植：
  - `testMergeIntoPool PreservesIncomingOrder`
  - 同名不同年不合并、同年合并
  - `normalizeYear("2009年") == 2009`
  - `initialDisplay = 30`、`fetchSize = 50`、`scrollLoadSize = 20`
  - TV 首页 `hotSize/recentSize/allRowSize = 6`
  - `HomeLaunch.shouldEnterMain(didSucceed: true)` 即使列表为空也进主界面
  - `firstSuccess`：前面源失败则用后面的；全失败抛错；更快的源优先

常量必须与 Swift 一致：

```kotlin
object HomeFeed {
    const val FETCH_SIZE = 50
    const val INITIAL_DISPLAY = 30
    const val SCROLL_LOAD_SIZE = 20
    const val HOT_SIZE = 6
    const val RECENT_SIZE = 6
    const val ALL_ROW_SIZE = 6
}
```

`mergeKey`：标题去空白、小写、去掉 `·・:：-—_`，年份取第一个 `\d{4}`。

- [ ] **步骤 1–4：** 每张表先写失败测试，再移植 Swift，跑 `:core:test`，按主题分别 commit（`feat(android): 移植 HomeFeed 分页与去重` / `feat(android): 移植跨源 VodMerge` / `feat(android): 移植分类树`）。

---

### 任务 5：MacCMSClient + VodService 门面

**文件：**
- 创建：`maccms/MacCMSClient.kt`、`maccms/MacCMSJsonParser.kt`、`maccms/MacCMSModels.kt`
- 创建：`category/CategoryListService.kt`
- 创建：`vod/VodService.kt`
- 测试：JSON 解析用录制的最小 payload（不要打真实站点做单测）。网络用 OkHttp `MockWebServer`。

对照 `MacCMSClient.swift`：

- UA：`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`
- 超时 15s
- `ac=list` 取分类，`ac=detail&pg=&t=` 取列表，`ac=detail&ids=` 取详情，`ac=detail&wd=` 搜索
- 列表失败时按 `SourceStore.enabled()` 顺序换源；首页启动用 `HomeLaunch.firstSuccess`

`RequestFailure.userFacingMessage` 必须输出与 Swift 相同的中文（超时 / 离线 / DNS / TLS）。把 `verify-client-logic.swift` 里 `testRequestFailureMaps*` 全部移植。

- [ ] **步骤 1：** MockWebServer 返回一段 MacCMS list JSON，断言 `fetchTypes` 解析出分类。
- [ ] **步骤 2：** 实现 client + parser。
- [ ] **步骤 3：** `./gradlew :core:test` PASS。
- [ ] **步骤 4：** Commit `feat(android): 移植 MacCMSClient 与 VodService`。

---

### 任务 6：直播 M3U / TXT 解析 + LiveStore

**文件：**
- 创建：`live/LiveModels.kt`、`live/LiveStore.kt`、`live/M3UPlaylistParser.kt`
- 创建：`src/main/resources/lives.json`（从 Apple 复制）
- 测试：移植 `verify-client-logic.swift` 全部 `testM3U*` / `testTxtPlaylist*` / `testLiveStore*` / `testLivePlayback*` 中不依赖 AVFoundation 的部分。

必须对齐的行为（不要简化）：

- `#EXTINF` 的 `group-title` 支持无引号 / 单引号 / 双引号
- 同频道多 URL 作为 backup streams
- 去掉 TVBox `$源名` 尾巴，但保留 query 里的 `$`
- 丢掉非 http(s) 播放地址
- 去 UTF-8 BOM
- TXT 格式：`genre,` 分组、`频道,url#backup`
- `LivePlayback.prefersVLC`：URL 含 `/udp/` 或 `/rtp/`
- 频道 zap 只在组内循环，不跨组
- `LiveWatchMemory` 记住上次频道 id

- [ ] 测试失败 → 移植 → `:core:test` → commit `feat(android): 移植直播 M3U 解析与换台规则`

---

### 任务 7：HLSPlaylistProbe + 播放路由决策

**文件：**
- 创建：`live/HLSPlaylistProbe.kt`、`live/LivePlayback.kt`
- 测试：移植 probe 相关用例（FLV magic `FLV`、`application/octet-stream`+TS sync `0x47`、HTML 错误页 reject、非 2xx reject、Set-Cookie 合并进 player headers、pending 超过次数 reject）。

决策枚举与 Swift 一致：`playable | flv | mpegts | retry | reject`。

VOD 侧 `PlaybackSupport.isDirectMediaURL` 与 `userFacingError` 也在本任务移植（网页链接提示换 m3u8 线路）。

- [ ] commit `feat(android): 移植 HLS probe 与播放失败文案`

---

### 任务 8：下载策略与本地存储（纯逻辑）

**文件：**
- 创建：`download/DownloadEnqueuePolicy.kt`、`download/DownloadStore.kt`、`model/DownloadRecord.kt`
- 测试：对照 `clients/apple/scripts/verify-downloads.swift`

策略常量：`minimumFreeBytes = 1_000_000_000`。结果枚举：`queued / alreadyCompleted / resetToQueued / insufficientDisk / alreadyInQueue`。完成时若用户已删则 `discard`，否则 `complete`。

本任务**不**写 Media3 / URLSession。引擎在 `:playback`。

- [ ] commit `feat(android): 移植下载入队策略与本地元数据`

---

### 任务 9：DeepLink

**文件：**
- 创建：`deeplink/AppDeepLink.kt`
- 测试：

```kotlin
@Test
fun roundTrip() {
    val url = AppDeepLink.vodUrl(33, "12345")
    assertEquals("multilivetv://vod/33/12345", url)
    assertEquals(AppDeepLink.VodTarget(33, "12345"), AppDeepLink.parse(url))
}

@Test
fun rejectsWrongScheme() {
    assertEquals(null, AppDeepLink.parse("https://example/vod/1/2"))
}
```

scheme / host 与 Swift 完全相同：`multilivetv` / `vod`。

- [ ] commit `feat(android): 移植 multilivetv deep link`

此时 `:core` 应能单独 `./gradlew :core:test` 全绿，覆盖 Apple `verify-client-logic.swift` 中所有非 UIKit 用例。在 README 写下对照命令。

---

### 任务 10：`:playback` Media3 + LibVLC

**文件：**
- 创建：`clients/android/playback/build.gradle.kts`（`com.android.library`）
- 创建：`playback/src/main/kotlin/.../player/PlaybackRouter.kt`
- 创建：`VlcLivePlayer.kt`、`Media3VodPlayer.kt`、`LivePlaybackSession.kt`

依赖：

```kotlin
implementation("androidx.media3:media3-exoplayer:1.5.1")
implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
implementation("androidx.media3:media3-ui:1.5.1")
implementation("org.videolan.android:libvlc-all:3.6.0")
implementation(project(":core"))
```

路由（对齐 `LivePlaybackSession.swift`）：

1. `prefersVLC(url)` → 直接 LibVLC
2. 否则 probe playlist
3. `playable` → Media3
4. `flv` / `mpegts` → LibVLC
5. 失败则 backup URL failover（只前进，不循环）；用户手动切源才 wrap

HTTP headers：UA + Referer（源站 host）+ Origin，VLC 用 `--http-user-agent` 等 option，对照 `LivePlayback.vlcHTTPOptions`。

VOD：`PlayParser.parsePlay` 得到最终 URL 后同样走 Media3；直链 FLV 走 VLC。已下载本地文件优先（`DownloadManager.playbackURL`）。

- [ ] 用 Robolectric 或 instrumented 测试只测 router 决策（给定 probe 结果返回哪条引擎），不要在 CI 里真播。
- [ ] commit `feat(android): 接入 Media3 与 LibVLC 播放路由`

---

### 任务 11：`:playback` 下载引擎

**文件：**
- `download/FileDownloadEngine.kt` — OkHttp 写文件，进度回调
- `download/HlsDownloadEngine.kt` — **仅 Pad** 用 Media3 `DownloadHelper` / `CacheDataSource`（对应 iOS AVAssetDownload）
- `download/HlsPlaylistDownloadEngine.kt` — **TV 与 Pad 共用兜底**，对照 `HLSPlaylistDownloadEngine.swift` + `HLSPlaylistLocalizer.swift`：拉 master/media playlist，改写相对 URI，下 ts/fmp4
- `download/DownloadManager.kt` — 对照 Swift：单 worker 队列、pause/delete 集合、进度节流写盘、恢复时 `reconcileEvicted`

Android 特性：

- Pad：`FOREGROUND_SERVICE_DATA_SYNC` + 通知，对应 iOS background URLSession
- TV：不依赖后台保活，进程在就下，被杀则 queued 待下次打开恢复（与 tvOS 现实一致）

- [ ] 文件下载用 MockWebServer 测进度与完成路径。
- [ ] commit `feat(android): 实现点播下载引擎`

---

### 任务 12：Pad Application 壳 + 主题

**文件：**
- 创建：`app/build.gradle.kts`、`AndroidManifest.xml`、`network_security_config.xml`
- 创建：`ui/theme/AppTheme.kt`（对照 `AppTheme.swift` / `CinemaChrome.swift`：深色、强调色、海报圆角、屏幕边距）
- 创建：`MultiLiveTVApp.kt`、`ui/MainTabScreen.kt`
- 创建：`ui/components/StateViews.kt`（loading / error 重试 / 空态，文案与 Apple 一致）

Manifest：

- `INTERNET`、`ACCESS_NETWORK_STATE`
- `usesCleartextTraffic` + `network_security_config` 允许 HTTP（对齐 ATS `NSAllowsArbitraryLoads`）
- `android:icon` 先用 Apple 导出的 `AppIcon.png` 转 mipmap（`clients/apple/scripts/export-brand-assets.py` 的产物可复用）
- 方向：`sensorLandscape` **不要**锁死；平板允许竖屏（iPad 也允许）
- `defaultToDeviceProtectedStorage` 不必

Tab 四项，顺序与 Apple `MainTabView` 相同：首页、直播、搜索、下载。

- [ ] 先跑起来能看到四个空 Tab + 深色背景。
- [ ] commit `feat(android): Pad 应用壳与影院风主题`

---

### 任务 13：Pad 首页 / 搜索 / 详情

**文件：**
- `ui/home/HomeScreen.kt`、`CategoryTabs.kt`、`VodCard.kt`、`HeroBanner.kt`
- `ui/search/SearchScreen.kt`
- `ui/detail/DetailScreen.kt`
- `ui/components/RemoteImage.kt`（Coil）

行为对齐 `HomeView.swift`（iOS 分支）：

- 启动直接进 Tab，无 tvOS 那种全屏 LaunchLoading 闸门
- 一级 + 二级分类；切分类用 `HomeFeedCache`，已看过的 typeId 不重打网络
- 列表：先展示 `min(30, pool)`，滚动再 `+20`，池不够再请求下一页 `pg`
- 搜索：`VodService.search`，跨源合并；空态「未找到相关影片」
- 详情：海报、简介（`VodDisplayFormatter.displayBlurb` 去 HTML）、线路 Tab、选集；点集全屏 `PlayerScreen`
- 下载按钮打开选集 picker（对照 `DownloadEpisodePicker`）

分页数字写在 `HomeFeed`，UI 不得 hardcode 30/20/50。

- [ ] 用 fake `VodService`（内存源）做 Compose UI 测试：切分类会换列表、搜索展示合并条数。
- [ ] commit `feat(android): Pad 首页搜索详情`

---

### 任务 14：Pad 播放器界面

**文件：**
- `ui/player/PlayerScreen.kt`

对照 `PlayerView.swift` iOS 分支：全屏 `VideoPlayer`、失败可重试、本地已下载优先、退出释放播放器。用 Media3 `PlayerView` 或 `androidx.media3:media3-ui-compose`。FLV 走 `AndroidView` 包 LibVLC `TextureView`。

- [ ] commit `feat(android): Pad 点播播放页`

---

### 任务 15：Pad 直播页

**文件：**
- `ui/live/LiveScreen.kt`、`LiveGuideOverlay.kt`、`LiveChannelCard.kt`

对照 `LiveView.swift`：宽 < 900 为 compact（导视叠加），否则导视可侧栏。触控：点频道切换、点画面显隐导视。记住上次频道。多线路 cycle。错误/未配置 `lives.json` 的空态文案与 Apple 相同。

- [ ] commit `feat(android): Pad 直播页`

---

### 任务 16：Pad 下载页

**文件：**
- `ui/downloads/DownloadsScreen.kt`

对照 `DownloadsView.swift` iOS：列表、进度、暂停/继续/删除、点已完成进播放器。存储不足文案：「存储空间不足，请清理后再下载」。

- [ ] commit `feat(android): Pad 下载页`

---

### 任务 17：Android TV 壳 + Leanback 入口

**文件：**
- 创建：`tv/build.gradle.kts`、`AndroidManifest.xml`、banner 资源
- 创建：`tv/src/main/kotlin/.../TvApp.kt`、`ui/TvMainScreen.kt`

Manifest 要点（否则桌面启动器不认 TV App）：

```xml
<uses-feature android:name="android.software.leanback" android:required="true" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<application android:banner="@drawable/tv_banner">
  <activity android:name=".TvActivity">
    <intent-filter>
      <action android:name="android.intent.action.MAIN" />
      <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
    </intent-filter>
  </activity>
</application>
```

Banner 320×180，可用 Apple `TopShelf.png` 裁切。依赖 `androidx.tv:tv-material` 与 `androidx.tv:tv-foundation`。

导航：`NavigationDrawer` 四项（对应 tvOS 18 `sidebarAdaptable` Tab），不要用手机 BottomBar。

- [ ] 在 Android TV 模拟器出现在行推荐/应用行里。
- [ ] commit `feat(android): Android TV Leanback 壳`

---

### 任务 18：TV 启动闸门 + 货架首页

**文件：**
- `ui/launch/LaunchLoadingScreen.kt`
- `ui/home/TvHomeScreen.kt`、`VodShelf.kt`

对照 `MultiLiveTVApp.swift` tvOS：`AppLaunchSession` 在进主界面前必须 `loadHomeLaunch(tvDisplay: true)` 成功；失败全屏错误+重试。`HomeLaunch.shouldEnterMain` 成功即可进，哪怕第一页为空。

首页对照 tvOS `HomeView`：分类条 + Hero + 热门/最近/全部货架（每行 6）。焦点：

- 卡片 focus 放大 1.10（`TVDesign.focusScale`）
- 返回键：焦点在影片上时先回到分类，而不是退出 App（对照 `onExitCommand` + `jumpFocusToCategories`）
- 分类条可打开搜索（`tvOpenSearch`）

`tvDisplay: true` 时 `displayCount` 用 `initialAllDisplayCount`，不要用 Pad 的 30。

- [ ] commit `feat(android): TV 启动闸门与货架首页`

---

### 任务 19：TV 搜索 / 详情 / 播放 / 下载

复用 `:core` 与 `:playback`。UI 用 TV Material 的焦点组件，触控点击不要作为唯一入口。

对照：

- `SearchView.swift` tvOS：焦点在搜索框与结果网格间移动
- `DetailView.swift` tvOS：线路与选集都要能 D-pad 选中；播放 `fullScreenCover`
- `PlayerView.swift` tvOS：系统播放器风格；无播放器时 Back 关闭
- `DownloadsView.swift` tvOS：焦点列表

- [ ] commit `feat(android): TV 搜索详情播放下载`

---

### 任务 20：TV 直播（遥控器）

**文件：**
- `ui/live/TvLiveScreen.kt`

对照 `LiveRemoteRouter`（`verify-client-logic.swift` 里 `testLiveRemoteRouter*`）：

| 按键 | 导视打开时 | 沉浸播放时 |
| --- | --- | --- |
| Back / Menu | 隐藏导视 | 退出直播 Tab 由系统处理；Menu 打开导视 |
| 上/下 | 频道列表 | zap 组内上/下频道 |
| 左/右 | 分组 | 右可打开导视 |
| 中键 | 选频道 | 暂停/继续 |
| 彩色键或长按（若有） | — | `cycleStream` 切备用 URL |

实现放在 `:core` 的 `LiveRemoteRouter`（Swift 已有纯逻辑），TV UI 只把 `KeyEvent` 映射过去。

- [ ] 先把 router 单测从 Swift 搬完，再接线。
- [ ] commit `feat(android): TV 直播遥控器交互`

---

### 任务 21：Deep link Manifest + Pad/TV 接线

**文件：**
- 修改两个 `AndroidManifest.xml` 加 `intent-filter`：`multilivetv://vod/...`
- `DeepLinkRouter`：切到首页 Tab 并打开对应详情（对照 `DeepLinkRouter.swift`）

- [ ] 用 `adb shell am start -a android.intent.action.VIEW -d "multilivetv://vod/33/123"` 分别测 Pad 与 TV。
- [ ] commit `feat(android): 接入 multilivetv deep link`

---

### 任务 22：文档与仓库入口

**文件：**
- 重写：`clients/android/README.md`
- 修改：仓库根 `README.md` 架构段，加上 `clients/android/`
- 修改：`docs/E2E.md` 增加 Android 验收（去掉过期的「登录收藏」或标明仅 Go/Admin）

README 必须包含：

```bash
cd clients/android
./gradlew :core:test
./gradlew :app:installDebug
./gradlew :tv:installDebug
```

说明：App **不依赖** Go API；改源只需改 `core/src/main/resources/sources.json` 与 `lives.json`（与 Apple 同步复制）。打开 **Android TV 模拟器** 时安装 `:tv`，平板模拟器安装 `:app`。

- [ ] commit `docs: 补充 Android TV/Pad 构建与验收`

---

## 验收清单（对齐 Apple E2E，无登录）

Pad（平板模拟器或真机）：

1. 首页分类切换，海报列表出现
2. 搜索「鲨笼绝境」→ 合并为 1 条
3. 详情可见多线路，选集后能播
4. 直播能列出 M3U 分组并出画（HLS 走 Media3，FLV 走 VLC）
5. 下载一集 mp4/m3u8，进度可见，完成后离线播放

TV（Android TV 模拟器）：

1. 启动有加载全屏，失败可重试，成功进主界面
2. D-pad 在分类与货架间移动，焦点放大
3. Back 从影片焦点回到分类
4. 搜索、详情、播放同上
5. 直播：导视开关、组内上下换台、备用 URL
6. 应用出现在 TV 启动器，无需触控

逻辑回归（无设备）：

```bash
cd clients/android && ./gradlew :core:test
```

必须覆盖 Apple `run-logic-tests.sh` 中的合并、分类、解析、直播、下载策略、deep link、错误文案。

---

## 实现顺序与依赖

```
任务1 脚手架
  → 2 SourceStore
  → 3 PlayParser
  → 4 HomeFeed/Merge/Category
  → 5 MacCMS/VodService
  → 6 Live parse
  → 7 Probe
  → 8 Download policy
  → 9 Deep link
      → 10 playback 引擎
      → 11 下载引擎
          → 12–16 Pad（可先交付可玩的平板）
          → 17–21 TV
      → 22 文档
```

Pad 与 TV **共享 core/playback**，禁止复制一份 MacCMS 到 `tv/`。若只做其中一个外形，仍必须先完成任务 1–11，否则 UI 会重新发明协议。

---

## 自检

1. **规格覆盖：** Apple README 功能（分类 Feed、跨源搜索、详情线路、jx 解析播放、loading/错误/空态、tv 焦点）均有任务。直播、下载、deep link、启动闸门有任务。Top Shelf / 登录明确排除。
2. **占位符：** 无 TODO/待定。二期 Watch Next 写在「明确不做」。
3. **类型名：** `Source`、`HomeLaunchPayload`、`DownloadEnqueueOutcome`、`AppDeepLink.VodTarget` 在任务间保持一致。
4. **旧 Android MVP：** 任务 1 删除，避免工程师继续打 Go API。
