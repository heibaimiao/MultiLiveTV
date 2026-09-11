# 跨源统一分类 实现计划

> **面向 AI 代理的工作者：** 按规格 [`../specs/2026-09-03-unified-categories-design.md`](../specs/2026-09-03-unified-categories-design.md) 实现。

**目标：** 用 slug 统一分类；`list?cat=` 多源扇出合并；一级 Tab 仅电影/剧集/综艺/动漫/短剧。

**架构：** `unified-categories.json` 三端同步；刷新脚本从 MacCMS `class` 或本地快照填充 `sources` 映射。

---

### 任务 1：生成配置 + 刷新脚本
- [x] `scripts/refresh-unified-categories.py`（支持 `--from-snapshots`）
- [x] 写出三端 `unified-categories.json`

### 任务 2：api-go
- [x] 加载配置；`GET /vod/categories`；`GET /vod/list?cat=` 扇出合并
- [x] OpenAPI；单测查找 slug / 扇出映射

### 任务 3：web
- [x] `/api/vod/categories`；`list?cat=`
- [x] 首页 `/?cat=` + CategoryTabs 改 slug

### 任务 4：Apple
- [x] 内嵌 JSON；Tab 用 slug；列表按映射多源并行（内嵌模式）

### 任务 5：验证
- [x] Go test；Apple logic 相关；文档交叉引用
