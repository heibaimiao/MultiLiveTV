# E2E 验收

## 后端

```bash
# 启动（含 Auth）
docker compose up --build -d

# Smoke
apps/api-go/scripts/smoke-test.sh http://localhost:8080

# Health（含 DB）
curl http://localhost:8080/health
# {"status":"ok","db":"ok"}
```

## Apple 客户端

1. `cd clients/apple && xcodegen generate && open MultiLiveTV.xcworkspace`
2. 选 **MultiLiveTV-tvOS** scheme，Apple TV 模拟器运行
3. 验收路径：
   - 首页分类切换，影片卡片可焦点导航
   - 搜索「鲨笼绝境」→ 1 条合并结果
   - 进入详情 → 切换线路 Tab → 选集播放（经 parse）
   - 登录 → 详情页收藏

## VPS 联调

1. 按 [`docs/DEPLOY.md`](DEPLOY.md) 部署
2. 修改 `APIConfig.swift` Release URL
3. 真机 Apple TV 指向 HTTPS API
