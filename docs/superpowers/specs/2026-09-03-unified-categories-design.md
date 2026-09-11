# 跨源统一分类设计

- 日期：2026-09-03
- 状态：已实现
- 范围：全端（`web/` + `apps/api-go/` + `clients/apple/`）
- 方案：B3 — 静态统一分类表 + 可刷新脚本

## 1. 背景与问题

各 MacCMS 资源站的 `type_id` **不能跨源复用**（实测约 74 个 id 冲突，例如 `type_id=1` 可能是「电影」「电视剧」或「国产动漫」）。

当前实现按**单源**构建分类树（`buildCategoryTree` / `CategoryTreeBuilder`），首页 Tab 还会把挂不上父类的项（足球、NBA、短剧细分等）塞进一级，导致：

1. 跨源浏览时分类错位或空列表
2. 一级 Tab 过长、噪音大
3. 「电视剧」等别名未归一到「剧集」，部分源缺一级父类

分类快照已落盘：`web/config/category-snapshots/`（27/29 源成功；1080、爱坤当时不可达）。

## 2. 目标

| 目标 | 说明 |
| --- | --- |
| 统一键 | 用稳定 `slug`（如 `movie`）标识分类，而不是某站的 `type_id` |
| 跨源拉列表 | 选分类后，对所有启用且有映射的源并行请求，再按片名合并 |
| 干净 Tab | 一级仅：全部 / 电影 / 剧集 / 综艺 / 动漫 / 短剧 |
| 全端一致 | Go API、Web、Apple 共用同一份映射语义 |
| 可维护 | 仓库内静态 JSON；脚本可从各源 `class` 重新生成 |

非目标（本期不做）：

- 不改播放解析 / `jx_url`
- 不为体育、NBA 等建一级分类
- 不为当前不可达源（1080、爱坤）强行保留映射占位
- 不做用户自定义分类排序

## 3. 配置格式

### 3.1 文件位置（内容保持一致）

| 路径 | 用途 |
| --- | --- |
| `apps/api-go/config/unified-categories.json` | Go API 权威读取 |
| `web/config/unified-categories.json` | Next.js 归档网页 |
| `clients/apple/MultiLiveTV/Resources/unified-categories.json` | Apple 内嵌聚合 |

脚本刷新时三份一起写。

### 3.2 Schema

```json
{
  "version": 1,
  "generated_at": "2026-09-03T00:00:00+08:00",
  "aliases": {
    "电视剧": "剧集",
    "连续剧": "剧集",
    "日本剧": "日剧",
    "韩国剧": "韩剧",
    "泰国剧": "泰剧",
    "台湾剧": "台剧",
    "香港剧": "港剧",
    "大陆剧": "国产剧",
    "记录片": "纪录片",
    "日本动漫": "日韩动漫",
    "电影片": "电影",
    "综艺片": "综艺",
    "动漫片": "动漫"
  },
  "tree": [
    {
      "slug": "movie",
      "label": "电影",
      "sources": { "33": 1, "143": 2 },
      "children": [
        {
          "slug": "movie-action",
          "label": "动作片",
          "sources": { "33": 6 }
        }
      ]
    }
  ]
}
```

约定：

- `slug`：**全局唯一**。一级：`movie` / `tv` / `variety` / `anime` / `short`。二级带前缀：`movie-action`、`tv-cn`、`variety-cn`、`anime-jpkr`、`short-xianxia` 等，避免 `us` 在剧集/综艺/动漫间冲突
- `label`：展示名（中文）
- `sources`：`string(sourceId) → number(type_id)`；仅包含 `flag=0` 且探测成功的源
- `children`：可空数组
- 含「伦理 / 倫理 / `[关]` / 末尾 `x`」的类型永不写入
- 「全部」**不是** tree 节点：URL/API 不传 `cat`（或显式约定不使用 `cat=all`）

### 3.3 初始树（覆盖率来自 2026-09-03 快照）

一级（括号内为有映射的源数 / 当时可用源）：

| slug | label | 覆盖 |
| --- | --- | ---: |
| `movie` | 电影 | 27 |
| `tv` | 剧集 | 27 |
| `variety` | 综艺 | 27 |
| `anime` | 动漫 | 26 |
| `short` | 短剧 | 18 |

二级（节选，完整以生成脚本输出为准）：

- 电影：动作/喜剧/爱情/科幻/恐怖/剧情/战争/纪录片（27），动画片（17）
- 剧集：国产剧（23）、港剧（22）、台/日/韩剧（27）、泰剧（23）、欧美剧（25）、海外剧（18）
- 综艺：大陆/港台/日韩/欧美综艺（26）
- 动漫：日韩/欧美（26）、国产（18）、海外/港台（13）
- 短剧：古装仙侠（18）、现代都市/反转爽剧（16）、脑洞悬疑（14）

默认首页分类：`movie`（与当前 Apple `defaultTypeId` 偏好一致）。

## 4. API 契约

权威定义更新：`packages/openapi/openapi.yaml`。

### 4.1 `GET /api/v1/vod/categories`

返回统一树（**不**下发各站 `type_id`，避免客户端误用）：

```json
{
  "version": 1,
  "defaultSlug": "movie",
  "tree": [
    {
      "slug": "movie",
      "label": "电影",
      "children": [
        { "slug": "movie-action", "label": "动作片" }
      ]
    }
  ]
}
```

Web 对齐：`GET /api/vod/categories`。

### 4.2 `GET /api/v1/vod/list`

新增查询参数：

| 参数 | 说明 |
| --- | --- |
| `cat` | 统一分类 `slug`；与 `t` 同时存在时 **`cat` 优先** |
| `t` | 保留：单源 MacCMS `type_id`（需配合 `sourceId` 或默认源） |
| `sourceId` | 可选；有 `cat` 时忽略（统一路径为多源） |
| `pg` | 页码，默认 1 |

`cat` 模式响应在现有 list 字段上增加：

```json
{
  "cat": "movie",
  "label": "电影",
  "sourcesUsed": [33, 125, 143],
  "sourcesFailed": [146],
  "page": 1,
  "pagecount": 120,
  "total": 5000,
  "list": [ /* MergedVodItem[] */ ]
}
```

Web：`GET /api/vod/list?cat=movie&pg=1`。

### 4.3 兼容

- 旧客户端只传 `t` + `sourceId`：行为与现网一致（单源）
- Web 旧链接 `/?t=12`：能映射到当前默认源同名 slug 则 302/rewrite 到 `/?cat=…`，否则仍按单源 `t` 拉

## 5. 服务端行为（api-go + web）

### 5.1 加载映射

启动或首次请求时读取 `unified-categories.json` 到内存；admin「清缓存」可顺带重载该文件（可选，本期可重启生效）。

### 5.2 列表扇出

1. 用 `cat` 查找节点（一级或二级）
2. 取 `sources` 与当前 `flag=0` 源的交集
3. 并发请求各源 `ac=list&t={type_id}&pg={pg}`（超时 15s，并发上限 8）
4. 失败源记入 `sourcesFailed`，不阻断
5. 各源结果打上 `sourceId` / `sourceName`，经既有 `mergeVodItems` 合并
6. `pagecount` = 各成功源 `pagecount` 的最大值；`total` = 各源 `total` 之和（近似，仅展示用）

父级 `cat=movie`：直接用父级映射的 `type_id` 请求（站方通常已汇总子类）；若某源父级映射缺失但有子类，可对该源扇出子类再合并（可选增强，一期可用「跳过该源」简化）。

### 5.3 单源树 API

`GET /vod/types?sourceId=` 保留，供调试/管理；产品 UI 改走 `/vod/categories`。

## 6. 客户端

### 6.1 Apple

- 内嵌 `unified-categories.json`；Tab 数据源改为 slug 树
- 首页默认 `defaultSlug = movie`
- 列表请求：有 Go API 时用 `?cat=`；纯内嵌 MacCMS 模式时本地查 `sources` 映射后多源并行（复用现有聚合客户端）
- `CategoryTree` / 缓存键：由 `typeId: Int?` 改为 `slug: String?`，其中 `nil` = 「全部」（最新、不按分类过滤）
- 更新 `verify-client-logic.swift`：默认分类、伦理隐藏、子类匹配改为基于 slug/label

### 6.2 Web

- `HomePageClient` / `CategoryTabs`：`typeId` → `slug`
- URL：`/?cat=movie`，二级 `/?cat=movie-action`
- `buildListUrl` 使用 `cat`；加载更多继续带同一 `cat`
- 一级 Tab 不再渲染 standalone 杂项

### 6.3 UI 规则

- 一级：全部（无 `cat`）+ `tree` 一级节点
- 选中一级且有 `children` 时展示二级；二级「全部」= 当前一级 slug（例如仍请求 `cat=movie`）

## 7. 刷新脚本

`scripts/refresh-unified-categories.py`：

1. 读 `sources.json`（以 api-go 为准）
2. 对每个启用源请求 `ac=list&pg=1`，取 `class`
3. 过滤不可见类型；用 `aliases` 归一 `label`
4. 按预设树模板（一级/二级 label 列表）填充 `sources` 映射
5. 写入三端 JSON，打印覆盖率报告
6. 退出码：一级覆盖低于阈值（如电影 < 15）时非 0，防止误提交空表

保留人工可改：模板中的 slug/label/排序；脚本只填 `sources` 与 `generated_at`。

开发期可用已有快照目录离线生成，避免重复打满站。

## 8. 实现顺序建议

1. 生成初始 `unified-categories.json`（三端）+ 刷新脚本
2. api-go：加载配置、`/vod/categories`、`list?cat=` 扇出合并；OpenAPI
3. web：API 路由 + 首页 Tab/URL
4. Apple：模型/Tab/列表/缓存键 + 验证脚本
5. 文档：`docs/maccms-api.md` 增补统一分类说明

## 9. 测试与验收

- 单元：别名归一、slug 查找、父/子映射、伦理过滤
- 集成：`cat=movie` 返回 `list.length > 0` 且条目含多个不同 `sourceId`（环境网络可用时）
- Apple 逻辑脚本：默认 `movie`、Tab 无伦理、无足球级噪音一级
- 回归：仅 `t`+`sourceId` 的单源 list 仍可用
- 验收清单：
  - [ ] 电影/剧集/综艺映射源 ≥ 20（以生成报告为准）
  - [ ] Web / Apple 一级 Tab 仅约定集合
  - [ ] `cat` 合并列表可翻页
  - [ ] 三端 JSON `version` 与 tree 结构一致

## 10. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 站方改 type_id | 跑刷新脚本并提交 |
| 多源扇出延迟 | 并发上限 + 超时；先返回已完成源（一期可等齐再返回，实现简单） |
| total/pagecount 不精确 | 文档标明近似；UI 以「还有更多」为准 |
| Apple 缓存键迁移 | 清本地分类缓存或 bump cache version |

## 11. 已决问题

- 方案：B3（静态表 + 刷新脚本）
- 范围：全端
- 默认分类：电影（`movie`）
- 一级含短剧；体育等不进一级

## 12. 相关规格

播放线路统一（模型 / 权重 / 取播 API）见 [`2026-09-03-unified-play-lines-design.md`](2026-09-03-unified-play-lines-design.md)；与分类独立，可并行实现。
