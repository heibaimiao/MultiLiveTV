# Apple 原生官方站详情挂线

- 日期：2026-09-10
- 状态：已批准（待实现）
- 范围：`clients/apple`（优先）；不改 Go / Web / Android 本期行为
- 相关：[`2026-09-03-unified-play-lines-design.md`](2026-09-03-unified-play-lines-design.md)、[`2026-09-03-bpz5-official-lines-merge-design.md`](2026-09-03-bpz5-official-lines-merge-design.md)、[`demos/ehr663-vod/official.json`](../../../demos/ehr663-vod/official.json)

## 1. 目标

详情在现有 MacCMS 多源合并结果之上，按**片名**在腾讯 / 优酷 / 爱奇艺 / 芒果四站用**原生 HTTP**（从 EHR663 spider 抽取的请求与解析逻辑，Swift 重写）搜索并拉分集，插入高权重 `PlaySource`。分集 URL 为官方页；播放走该源已配置的 `jx_url`，与 spider `playerContent` 行为一致。

非目标：

- 不在 Apple 内嵌或调用 Python / EHR663 脚本 / 侧车进程
- 官方源不进入首页 / 分类列表 fan-out
- 官方源不进入全局搜片 fan-out（避免拖慢 `SearchView`）
- 本期不做 Go / Web / Android 对齐
- 不追求平台直链 m3u8（接受官方页 + jx）
- 不依赖 bpz5 ticket；Apple 仍可不调 Go

## 2. 已确认决策

| 决策 | 选择 |
| --- | --- |
| 产品形态 | 详情挂官方线；列表仍只走 CMS |
| 运行时 | 原生 Swift HTTP，不调脚本 |
| 播放 | 官方页 URL + 源 `jx_url`（方案 A + 选项 1） |
| 优先级 | 先 Apple |

## 3. 流程

```text
DetailView.loadDetail
  → VodService.detail（现有 CMS 主详情 + 多源 merge）
  → OfficialPlayEnricher.enrich(vod, existingPlaySources)
       并行：qq / youku / qiyi / mgtv（仅 enabled 的 official_web 源）
         search(片名) → 标题/年份匹配 → detail(id)
         → PlaySource（高权重）
  → 按 play weight 排序后展示
```

任一侧失败或超时：**静默跳过**，不影响 CMS `playSources`。

## 4. Registry

对 `source-registry.json` 中 `official-qq` / `official-youku` / `official-qiyi` / `official-mgtv`：

| 字段 | 现况 | 目标 |
| --- | --- | --- |
| `protocol` | `python` | `https` |
| `adapter.type` | `ehr663_py` | `official_web` |
| `adapter.parser` | `ehr663_qq` 等 | `qq` / `youku` / `qiyi` / `mgtv` |
| `connection.endpoint` | EHR663 `.py` raw URL | 各平台 API 基址（如腾讯 `https://pbaccess.video.qq.com`） |
| `connection.jx_url` | 已有（如 `https://jx.xmflv.cc/?url=`） | 保留；可备选第二解析前缀 |
| `capabilities.search` | `false` | **保持 `false`**（不进 `SourceCollector` 搜片） |
| `capabilities.detail` | `false` | **保持 `false`**（不进 CMS 详情 fan-out） |
| `capabilities.category` | `false` | 保持 `false` |
| `capabilities.play` | `true` | 保持 `true` |
| `numericId` / `play_priority` | 901–904 / 2000–1970 | 不变 |

`OfficialPlayEnricher` 按 `type == official && adapter.type == official_web && enabled` **主动**调用客户端，**不**依赖 `capabilities.search/detail`。

`SourceAdapterRegistry` 本期可不为 `official_web` 注册通用 list/search/detail adapter（避免误用）；逻辑集中在 Official 包。若后续要让官方源独立搜片，再打开 capability 并实现 `SourceAdapter`。

## 5. 组件

```text
clients/apple/MultiLiveTV/Services/Official/
  OfficialPlayEnricher.swift   # 编排、匹配、合并、超时
  OfficialWebClient.swift      # 协议：search / detail → 与 SourceMovie 兼容的模型
  TencentWebClient.swift       # 移植 腾讯视频.py 的 HTTP + JSON 解析
  YoukuWebClient.swift
  QiyiWebClient.swift
  MgtvWebClient.swift
```

职责边界：

| 单元 | 做什么 | 依赖 |
| --- | --- | --- |
| `*WebClient` | 单平台 search/detail；返回片名、封面、分集标题与官方页 URL | `URLSession`、源 registry 连接信息 |
| `OfficialPlayEnricher` | 读 official 源列表；并行调用；匹配；产出 `[PlaySource]` 并与已有线合并排序 | WebClient、匹配规则、`PlayLineWeighting` |
| `VodService` / `VodMergeService` | 在 CMS merge 完成后调用 enrich | Enricher |
| `DetailView` | 展示 enrich 后的全量加权线路 | 去掉 ticket-only 过滤 |

移植来源（逻辑参考，不运行）：上游 EHR663 `py/腾讯视频.py`、`优酷视频.py`、`爱奇艺.py`、`芒果TV.py` 中的 `searchContent` / `detailContent`；`playerContent` 仅映射为「官方页 + jx」，不在客户端执行 Python。

## 6. PlaySource 形状

| 字段 | 值 |
| --- | --- |
| `key` | `official-qq` 等（与 `source_id` 一致） |
| `name` | 源显示名（腾讯视频 / 优酷 / …） |
| `sourceId` | `901`–`904` |
| `playFrom` | `qq` / `youku` / `qiyi` / `mgtv` |
| `mode` | `direct`（与现有 MacCMS 非直链一致：点播时走 `PlayParser.parsePlayAddress` + 该源 `jxUrl`） |
| `weight` | 由 `play-line-weights` / `play_priority` 计算（官方已高于 CMS） |
| `episodes[].url` | 官方站页面 URL（如 `https://v.qq.com/x/cover/{cid}/{vid}.html`） |
| `providerId` / `ticket` | 空；非 bpz5 |

播放：`VodService.parsePlay(sourceId: 901…, url: 官方页)` → 查 registry 得 `jx_url` → 现有 jx 解析链。解析成败取决于第三方 jx，属预期外部风险，不阻塞本功能合并。

## 7. 匹配规则

与现有多源详情 merge 对齐：

- 标题归一：复用 `HomeFeed.mergeKey` / 现有 normalize（小写、去空白与常见标点）
- 优先归一后全等；其次双向包含且惩罚长度差
- `vod_year` 与候选年份一致加分；冲突降权
- 达不到阈值：**不挂该平台线**（少合并优于错合并）
- 每平台最多挂 **1** 条 `PlaySource`（最佳匹配一部作品的全部分集）

## 8. 性能与失败

- enrich 总预算约 **5s**；单平台约 **3s**
- 四平台并行；单平台失败不影响其他
- 可选短缓存：`(parser, normalizeTitle, year) → detail 结果`，TTL 30–60min（实现期可先不做，二期加）
- 不写 health 降权到「禁用」；可选记录成功/失败供调试

## 9. UI 变更

现状：`DetailView` 使用 `PlayLineWeighting.officialOnly`，只保留 `mode == ticket`，Apple 直连 CMS 时几乎永远空线。

目标：

- 删除或改写 `officialOnly`：**展示全部 `playSources`，按权重排序**
- 官方线因权重 1970–2000 自然靠前；CMS 线作后备
- 逻辑测试同步更新（原「只留 ticket」断言改为「按权重排序且保留 direct」）

## 10. 分期

| 期 | 内容 |
| --- | --- |
| 1 | Registry 字段调整；`OfficialPlayEnricher` 骨架；**腾讯** search/detail；接入 `VodService.detail`；修 `officialOnly`；fixture 逻辑测试 |
| 2 | 优酷、芒果 |
| 3 | 爱奇艺（上游脚本更长，单独排期） |

## 11. 验收

- [ ] 打开任意 CMS 详情，片名能在腾讯匹配时出现「腾讯视频」线路且排序靠前
- [ ] 官方 enrich 超时或失败时，仍展示 CMS `playSources`
- [ ] 选择官方分集后走该源 `jx_url` 解析路径（与 MacCMS 非 m3u8 相同）
- [ ] 首页 / 分类 / 全局搜索请求数不因官方源增加
- [ ] `clients/apple/scripts/run-logic-tests.sh` 通过

## 12. 明确不做

- 不把 `connection.endpoint` 继续指向 `.py` 文件
- 不在 `SourceCollector.list/search` 中默认拉起官方源
- 不在本期实现 Go 侧同类 enrich
- 不把 `mode` 设为 `ticket`（避免与 bpz5 解票语义混淆）
