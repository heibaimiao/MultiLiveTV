# MultiLiveTV Android Client (TV / Pad)

Jetpack Compose MVP，调用 Go API。

## 功能

- 搜索（跨源合并）
- 详情弹窗展示线路与集数
- Retrofit + Kotlin Serialization

## 集成到 Android Studio

1. 新建 **Empty Activity** 项目，包名 `com.heibaimiao.multilivetv`
2. 将 `clients/android/app/src/main/java/com/heibaimiao/multilivetv/` 复制到工程
3. `build.gradle.kts` 添加依赖：

```kotlin
implementation("com.squareup.retrofit2:retrofit:2.11.0")
implementation("com.squareup.retrofit2:converter-kotlinx-serialization:2.11.0")
implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
implementation("io.coil-kt:coil-compose:2.7.0")
```

4. 插件：`kotlin("plugin.serialization")`

## API 地址

- 模拟器访问本机：`http://10.0.2.2:8080/api/v1/`
- 真机：改为开发机局域网 IP

## Android TV

在 `AndroidManifest.xml` 添加 `LEANBACK_LAUNCHER` category 与 TV banner 即可上架 TV 启动器。
