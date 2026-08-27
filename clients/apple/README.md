# MultiLiveTV — Apple TV + iPad

SwiftUI 原生客户端，调用 Go API。

## 功能

- 首页分类 Tab + Feed 分页（50/30/+20）
- 跨源搜索与合并
- 详情多线路选集
- `play/parse` 解析后 AVPlayer 播放
- 登录/注册 + Keychain JWT
- 收藏与播放进度同步
- tvOS 焦点高亮 + 遥控器适配

## 环境要求

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（生成 `.xcodeproj`）

```bash
brew install xcodegen
```

## 构建

```bash
cd clients/apple
xcodegen generate
open MultiLiveTV.xcodeproj
```

选择 **MultiLiveTV-tvOS** 或 **MultiLiveTV-iOS** scheme，运行模拟器或真机。

## API 地址

编辑 [`MultiLiveTV/Config/APIConfig.swift`](MultiLiveTV/Config/APIConfig.swift)：

- Debug：`http://localhost:8080/api/v1`
- Release：改为 VPS HTTPS 地址

模拟器访问本机 API 用 `localhost`；真机改为局域网 IP。

## 联调清单

1. 启动 Go API：`docker compose up` 或 `go run ./cmd/server`（需 `DATABASE_URL` 才能登录）
2. Smoke：`apps/api-go/scripts/smoke-test.sh http://localhost:8080`
3. Apple 客户端：首页加载 → 搜索「鲨笼绝境」→ 详情选集 → 播放
4. 登录后测试收藏按钮

## 目录

```
MultiLiveTV/
  Config/       API 基址
  Models/       数据模型
  Services/     APIClient、Keychain、HomeFeed
  Views/        首页、搜索、详情、播放、登录
```
