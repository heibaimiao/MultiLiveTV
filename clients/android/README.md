# MultiLiveTV Android

内嵌 MacCMS 多源聚合，**不依赖 Go 后端**。一个 Gradle 工程、两套 UI、一份 `:core`。

| 模块 | 形态 | 包名 |
|------|------|------|
| `:core` | Kotlin JVM 业务库 + 单测 | — |
| `:app` | 平板（对标 iPad） | `com.heibaimiao.multilivetv` |
| `:tv` | 电视 / 盒子（对标 tvOS） | `com.heibaimiao.multilivetv.tv` |

点播直连采集站；直播读 `lives.json`。改源后与 `clients/apple/MultiLiveTV/Resources/` 保持同步。

---

## 命令速查

```bash
cd clients/android

./gradlew :core:test
./gradlew :app:installDebug
./gradlew :tv:installDebug
./gradlew :app:assembleDebug
./gradlew :tv:assembleDebug

adb shell am start -n com.heibaimiao.multilivetv/.MainActivity
adb shell am start -n com.heibaimiao.multilivetv.tv/com.heibaimiao.multilivetv.MainActivity
adb shell am force-stop com.heibaimiao.multilivetv
adb shell am force-stop com.heibaimiao.multilivetv.tv
```

没有独立的测试/生产 flavor，也没有 Docker。侧载只需要对应 APK。

---

## 1. 编程语言

| 语言 | 用途 | 依据 |
|------|------|------|
| Kotlin | 业务与 UI | `*.kt`，Kotlin Android / JVM 插件 |
| XML | Manifest、主题、布局、图标 | `AndroidManifest.xml`、`res/` |
| JSON | 内嵌源站 / 分类 / 直播 | `core/src/main/resources/` |
| POSIX Shell | Gradle Wrapper | `gradlew` |

本目录没有 Node / Python / Go 工程。不写业务 Java 源码；Kotlin 编译目标是 JVM 17 字节码。

## 2. 语言与 JDK 版本

```text
Kotlin：2.0.21（android / jvm / compose / serialization）
  依据：build.gradle.kts

Java / JDK：
  开发 JDK：17（本 README；:core toolchain 17）
  编译 JDK：17（sourceCompatibility / targetCompatibility / jvmTarget）
  运行时：设备 ART，不是桌面 JRE
  minSdk 23（Android 6.0）～ targetSdk 35（Android 15）
  API 23–25 的 java.time 靠 desugar_jdk_libs 2.1.4

compileSdk：35
```

## 3. 框架 / 运行时

- UI：Jetpack Compose。Pad 用 Material3；TV 另加 `androidx.tv:tv-material:1.0.0`
- 播放：Media3 ExoPlayer 1.5.1（HLS + OkHttp DataSource）。**未引入 LibVLC**
- 网络：OkHttp 4.12.0 + DoH + `ResilientDns`
- 图片：Coil 2.7.0
- 并发：kotlinx-coroutines 1.9.0
- 序列化：kotlinx-serialization-json 1.7.3
- 导航 / 生命周期：Navigation Compose 2.8.5、Lifecycle 2.8.7、Activity Compose 1.9.3
- API < 26 TLS：Conscrypt 2.5.2

## 4. 依赖管理

Gradle Kotlin DSL。仓库：`google()` + `mavenCentral()`。`FAIL_ON_PROJECT_REPOS`。无 Maven / npm / version catalog。

## 5. 构建工具版本

```text
Gradle Wrapper：8.13
  gradle/wrapper/gradle-wrapper.properties → gradle-8.13-bin.zip
Android Gradle Plugin：8.7.3
Kotlin Gradle Plugin：2.0.21
Compose BOM：2024.12.01
desugar_jdk_libs：2.1.4
Android SDK：compileSdk / targetSdk 35；路径为 local.properties 的 sdk.dir（已 gitignore）
```

## 6. 构建命令

工作目录必须是 `clients/android`。

推荐：

```bash
./gradlew :core:test
./gradlew :app:assembleDebug
./gradlew :tv:assembleDebug
```

备用：`./gradlew :app:assembleRelease` / `:tv:assembleRelease` / `build`。Release 开了 `proguardFiles` 但 `isMinifyEnabled = false`，且没有 `signingConfigs`。

## 7. 打包命令

```bash
./gradlew :app:assembleDebug
./gradlew :tv:assembleDebug
./gradlew :app:assembleRelease
./gradlew :tv:assembleRelease
```

没有 AAB / `bundleRelease` 配置。

## 8. 启动命令

不能在宿主机 `java -jar`。开发安装后拉起：

```bash
./gradlew :app:installDebug
./gradlew :tv:installDebug
adb shell am start -n com.heibaimiao.multilivetv/.MainActivity
adb shell am start -n com.heibaimiao.multilivetv.tv/com.heibaimiao.multilivetv.MainActivity
```

也可用 Android Studio 打开 `clients/android` 后 Run。`:app` 另有 Deep Link `multilivetv://vod/...`。

## 9. 停止 / 重启

无脚本。设备侧：

```bash
adb shell am force-stop com.heibaimiao.multilivetv
adb shell am force-stop com.heibaimiao.multilivetv.tv
```

重启 = `force-stop` + `am start`。卸载用 `adb uninstall <包名>`。

## 10. 开发环境

JDK 17 + Android SDK。`./gradlew :core:test`，再 `installDebug` 或 Android Studio Run。平板装 `:app`，电视 / 盒子装 `:tv`。无 `dev` flavor。改 `core/src/main/resources/` 后重新编译。

## 11. 测试环境

**没有独立测试/生产启动命令。**

```bash
./gradlew :core:test
```

`:core` 用 `kotlin("test")` + JUnit Platform。`:app` / `:tv` 没有 `androidTest`。

## 12. 正式环境

没有 `prod` flavor、没有商店流水线。发布 = 打 APK 侧载。不经过仓库 Docker Compose。

## 13. Docker

本目录没有 Dockerfile / docker-compose / Podman 配置。

## 14. 配置文件与环境变量

无 `.env`、无 `application.yml`、无 `BuildConfig` 字段、无 `System.getenv`。

| 文件 | 作用 |
|------|------|
| `local.properties` | 本机 `sdk.dir`（不入库） |
| `gradle.properties` | `-Xmx2g`、UTF-8、AndroidX、parallel |
| `source-registry.json` | 源站注册 |
| `sources.json` | 采集源 |
| `unified-categories.json` | 统一分类 |
| `play-line-weights.json` | 线路权重 |
| `lives.json` | 直播订阅 |
| `local-live.m3u` | 本地直播列表 |
| `NetworkConfig.kt` | UA；连接 5s；读写/整呼 8s |
| Manifest `usesCleartextTraffic=true` | 允许 HTTP |

改 JSON 必须重编 APK。

## 15. 操作系统与基础环境

构建：macOS / Linux / Windows，JDK 17，Android SDK Platform 35。运行：Android 6.0+（API 23）。未设 `abiFilters`，APK 含 `arm64-v8a` / `armeabi-v7a` / `x86` / `x86_64`。Leanback `required=false`。权限：`INTERNET`、`ACCESS_NETWORK_STATE`。

## 16. CI/CD

`.github/workflows/api.yml` 只覆盖 `apps/api-go`。Android **无** GitHub Actions / Jenkins / GitLab CI。提交不会自动出 APK。

## 17. 发布产物

| 产物 | 路径 |
|------|------|
| 平板 Debug APK | `app/build/outputs/apk/debug/app-debug.apk` |
| TV Debug APK | `tv/build/outputs/apk/debug/tv-debug.apk` |

`versionName=1.0`，`versionCode=1`。`build/` 已 gitignore。

## 18. 部署需要的文件

侧载一个 APK 即可（平板用 app，盒子用 tv）。源站 JSON 与 so 已打进包内。不需要 JDK、Go 后端、`.env`。

## 19. 常见问题与版本兼容

1. Gradle / AGP 8.7 必须用 JDK 17，不能用 JDK 8 跑 Wrapper。
2. minSdk 23。Android 6 HTTPS 靠 Conscrypt。
3. 无正式签名；`assembleRelease` 未配 keystore。侧载用 debug 包。
4. `isMinifyEnabled = false`，ProGuard 规则在但不混淆。
5. 不依赖 Go API；不要用 `10.0.2.2:8080`。
6. `useLegacyPackaging = true`，方便老盒子解压 `.so`。
7. 1GB 内存盒子能装，Compose 可能卡。
8. 改源必须重编，没有远程配置下发。
