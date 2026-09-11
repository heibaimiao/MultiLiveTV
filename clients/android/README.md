# MultiLiveTV Android Pad

按 Apple iPad 客户端行为重建的平板 App：内嵌 MacCMS 多源聚合，**不依赖 Go 后端**。

## 功能（对标 iPad）

- 底部 / 侧边 Tab：首页、直播、搜索、下载
- 首页：统一分类 Chip + 海报网格，首屏 30、滚动再揭 20、分页 50
- 列表排序：**上映年份优先**，同年再按更新时间；分类切换缓存 + 后台刷新；下拉刷新
- 多源合并：同名同年折叠（空年份并入），伦理片客户端过滤
- 海报角标显示备注（正片 / HD / 更新至…）
- 详情：线路按权重排序，点选集全屏播放
- 播放：jx 解析 + 直链探测 + 最多 4 路故障切换（Media3 ExoPlayer）
- 搜索：多源并行合并
- 直播：`lives.json` → M3U / TXT 列表，HLS 播放

## 构建

需要 JDK 17 与 Android SDK（`local.properties` 里 `sdk.dir=`）。

```bash
cd clients/android
./gradlew :core:test
./gradlew :app:assembleDebug
```

用 Android Studio 打开 `clients/android`，平板模拟器或真机安装 `:app`。

## 改源

与 Apple 同源 JSON，在 `core/src/main/resources/`：

- `source-registry.json`
- `unified-categories.json`
- `play-line-weights.json`
- `lives.json`

改完后与 `clients/apple/MultiLiveTV/Resources/` 保持同步。
