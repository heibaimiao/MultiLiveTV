# MultiLiveTV — Apple TV + iPad

SwiftUI 原生客户端，**内嵌 MacCMS 多源聚合**（无需 Go 后端）。

## 功能

- 首页分类 Tab + Feed 分页（50/30/+20）
- 跨源搜索与合并（本地 `VodMergeService`）
- 详情多线路选集（海报 + 简介）
- `jx_url` 解析后 AVPlayer 播放
- 统一 loading / 错误重试 / 空态 UI
- tvOS 焦点高亮 + 遥控器适配

## 环境要求

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（生成 `.xcodeproj`）

```bash
brew install xcodegen
```

## 构建

直播里的 HTTP-FLV（TVBox 常见虎牙转推）需要 [VLCKit](https://github.com/videolan/vlckit)。HLS / m3u8 仍走 AVPlayer。

```bash
cd clients/apple
xcodegen generate
pod install
open MultiLiveTV.xcworkspace
```

必须打开 **`.xcworkspace`**，不要再开 `.xcodeproj`。重新跑 `xcodegen generate` 之后会自动执行 `pod install`。

选择 **MultiLiveTV-tvOS** 或 **MultiLiveTV-iOS** scheme，运行模拟器或真机。TVVLCKit 体积很大，首次 `pod install` 会下载约 200MB。

如果链接报 `Framework 'TVVLCKit' not found` 或 `XCFrameworkIntermediates/TVVLCKit` 不存在：关掉 Xcode，在 `clients/apple` 执行 `xcodegen generate && pod install`，再打开 `MultiLiveTV.xcworkspace` 后 Clean Build Folder。不要用 `.xcodeproj` 构建。

## 资源站配置

编辑 [`MultiLiveTV/Resources/sources.json`](MultiLiveTV/Resources/sources.json)（`flag: 0` 启用），修改后重新运行 App。

与 Go 后端 [`apps/api-go/config/sources.json`](../../apps/api-go/config/sources.json) 格式相同，可同步复制。

## 架构

```
MultiLiveTV/
  Resources/    sources.json（打包进 App）
  Services/
    SourceStore.swift      加载资源站
    MacCMSClient.swift     请求 MacCMS API
    VodMergeService.swift  跨源合并
    PlayParser.swift       线路解析 + jx_url
    VodService.swift       View 层门面
  Views/        首页、搜索、详情、播放
```

App **不依赖** `localhost:8080` Go API，直接请求第三方采集站。

## 验证

无 Xcode 时可用脚本验证跨源搜索合并：

```bash
swift clients/apple/scripts/verify-aggregation.swift
```

期望输出 `merged groups: 1`（关键词「鲨笼绝境」）。

Xcode 联调清单：

1. **首页**：加载分类与影片列表
2. **搜索**：输入关键词 → 结果或空态
3. **详情**：多线路 `playSources` 可见
4. **播放**：选集后 AVPlayer 播放

## 目录

```
MultiLiveTV/
  Resources/    sources.json
  Models/       数据模型
  Services/     VodService、MacCMS、Merge、HomeFeed
  Views/        首页、搜索、详情、播放
  Views/Components/  StateViews、VodCard
```
