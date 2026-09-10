# Apple 原生官方站详情挂线 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** Apple 详情在 CMS 合并结果上，用原生 Swift HTTP（移植自 EHR663 腾讯等 spider）按片名挂上官方分集线；播放走源 `jx_url`；不调用 Python。

**架构：** `OfficialPlayEnricher` 在 `VodMergeService.enrichMergedVodDetail` 之后并行调用各 `OfficialWebClient`；纯解析函数可单测；registry 将 `ehr663_py` 改为 `official_web`；`DetailView` 取消 ticket-only 过滤。

**技术栈：** Swift / URLSession / 现有 `PlayParser` + `PlayLineWeighting` / `clients/apple/scripts/verify-client-logic.swift`

**规格：** [`../specs/2026-09-10-apple-official-web-detail-enrich-design.md`](../specs/2026-09-10-apple-official-web-detail-enrich-design.md)

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `clients/apple/MultiLiveTV/Resources/source-registry.json` | 官方源 `protocol` / `adapter` / `endpoint` 调整 |
| `clients/apple/MultiLiveTV/Services/PlayLineWeights.swift` | 将 `officialOnly` 改为按权重保留全量线路 |
| `clients/apple/MultiLiveTV/Views/DetailView.swift` | 调用新的展示过滤（或直接 `sort`） |
| `clients/apple/MultiLiveTV/Services/Official/OfficialWebModels.swift` | `OfficialSearchHit`、client 协议 |
| `clients/apple/MultiLiveTV/Services/Official/OfficialPlayEnricher.swift` | 编排、匹配、超时、合并 |
| `clients/apple/MultiLiveTV/Services/Official/TencentWebParsing.swift` | 腾讯 search/detail JSON → 模型（纯函数） |
| `clients/apple/MultiLiveTV/Services/Official/TencentWebClient.swift` | 腾讯 HTTP |
| `clients/apple/MultiLiveTV/Services/VodMergeService.swift` | enrich 完成后挂官方线 |
| `clients/apple/scripts/verify-client-logic.swift` | 单测 |
| `clients/apple/scripts/run-logic-tests.sh` | 编译进 Official 源文件 |
| `clients/apple/MultiLiveTV.xcodeproj/project.pbxproj` | 加入新 Swift 文件到 iOS/tvOS target |
| （二期）`YoukuWebParsing.swift` / `YoukuWebClient.swift` | 优酷 |
| （二期）`MgtvWebParsing.swift` / `MgtvWebClient.swift` | 芒果 |
| （三期）`QiyiWebParsing.swift` / `QiyiWebClient.swift` | 爱奇艺 |

参考（只读，不运行）：`/tmp` 或上游 `https://raw.githubusercontent.com/FGBLH/EHR663/.../腾讯视频.py` 的 `searchContent` / `detailContent` / `playerContent`。

---

### 任务 1：修正详情线路过滤（去掉 ticket-only）

**文件：**
- 修改：`clients/apple/MultiLiveTV/Services/PlayLineWeights.swift`
- 修改：`clients/apple/MultiLiveTV/Views/DetailView.swift`
- 修改：`clients/apple/scripts/verify-client-logic.swift`

- [ ] **步骤 1：编写失败的测试**

在 `verify-client-logic.swift` 将 `testOfficialOnlyKeepsTicketLines` 改为：

```swift
func testDisplayPlaySourcesKeepsWeightedOrder() {
    PlayLineWeighting.table = PlayLineWeights(
        version: 2,
        defaultWeight: 100,
        byPlayFrom: ["qq": 2000, "hnm3u8": 500],
        byProviderId: [:],
        bySourceId: nil
    )
    PlayLineWeighting.playPriorityBySourceId = [:]
    PlayLineWeighting.healthStore = SourceHealthStore()
    defer {
        PlayLineWeighting.table = .bundled
        PlayLineWeighting.healthStore = .shared
    }

    let sources = [
        PlaySource(name: "红牛", key: "hn", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 1, mode: "direct", playFrom: "hnm3u8"),
        PlaySource(name: "腾讯", key: "official-qq", episodes: [Episode(name: "1", url: "https://v.qq.com/x/cover/a/b.html")], sourceId: 901, mode: "direct", playFrom: "qq"),
    ]
    let annotated = sources.map { PlayLineWeighting.annotate($0) }
    let display = PlayLineWeighting.forDetailDisplay(annotated)
    assertEqual(display.map(\.key), ["official-qq", "hn"], "detail shows all lines, official first by weight")
    assertEqual(PlayLineWeighting.forDetailDisplay([]).count, 0, "empty stays empty")
}
```

并更新 `main` 里对该测试函数的调用名（若有显式列表）。

- [ ] **步骤 2：运行测试验证失败**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

预期：FAIL（`forDetailDisplay` 未定义或旧 `officialOnly` 行为不匹配）。

- [ ] **步骤 3：实现最少代码**

在 `PlayLineWeights.swift` 替换 `officialOnly`：

```swift
/// Detail UI: keep every line, sorted by effective play weight (official platforms rank first).
static func forDetailDisplay(_ sources: [PlaySource]) -> [PlaySource] {
    sort(sources.map { annotate($0) })
}

@Deprecated("Use forDetailDisplay")
static func officialOnly(_ sources: [PlaySource]) -> [PlaySource] {
    forDetailDisplay(sources)
}
```

（若项目不支持 `@Deprecated`，直接删除 `officialOnly`，全局替换调用点。）

`DetailView.swift` `applyDetail`：

```swift
playSources: PlayLineWeighting.forDetailDisplay(response.playSources),
```

- [ ] **步骤 4：运行测试验证通过**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

预期：PASS（含新断言）。

- [ ] **步骤 5：Commit**

```bash
git add clients/apple/MultiLiveTV/Services/PlayLineWeights.swift \
  clients/apple/MultiLiveTV/Views/DetailView.swift \
  clients/apple/scripts/verify-client-logic.swift
git commit -m "$(cat <<'EOF'
fix(apple): show all weighted play lines on detail

Replace ticket-only filtering so MacCMS and official-web lines remain visible.
EOF
)"
```

---

### 任务 2：Registry 改为 official_web

**文件：**
- 修改：`clients/apple/MultiLiveTV/Resources/source-registry.json`
- 修改：`clients/apple/scripts/verify-client-logic.swift`（若有 registry 解析断言）

- [ ] **步骤 1：编写失败的测试**

在 `verify-client-logic.swift` 增加：

```swift
func testOfficialSourcesUseOfficialWebAdapter() {
    let store = SourceStore(bundle: .moduleOrTestBundle) // 若现有测试用文件 URL，沿用同一加载方式
    // 与现有 SourceStore 测试一致：从 Resources/source-registry.json 路径加载
    let qq = store.byID(901)
    assertTrue(qq != nil, "official-qq present")
    assertEqual(qq!.adapter.type, "official_web", "adapter is official_web")
    assertEqual(qq!.adapter.parser, "qq", "parser qq")
    assertEqual(qq!.protocolName /* or protocol field */, "https", "https protocol")
    assertTrue(qq!.connection.endpoint.contains("pbaccess.video.qq.com"), "tencent API base")
    assertFalse(qq!.capabilities.search, "search stays false")
    assertFalse(qq!.capabilities.detail, "detail stays false")
    assertTrue(qq!.capabilities.play, "play true")
}
```

**注意：** 打开现有 `Source` / `SourceStore` 测试，复制其加载 registry 的方式；属性名以 `Models.swift` 为准（如 `protocol` 在 Swift 中可能是 `` `protocol` `` 或 `protocolKind`）。不要臆造 API——先读 `Models.swift` 里 `Source` 定义再写断言。

- [ ] **步骤 2：运行测试验证失败**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

预期：FAIL（仍为 `ehr663_py` / `.py` endpoint）。

- [ ] **步骤 3：更新四个官方源条目**

对 `official-qq` / `official-youku` / `official-qiyi` / `official-mgtv`：

```json
"protocol": "https",
"connection": {
  "endpoint": "<见下表>",
  "jx_url": "https://jx.xmflv.cc/?url="
},
"capabilities": {
  "search": false,
  "category": false,
  "detail": false,
  "play": true,
  "pagination": false,
  "live": false
},
"adapter": {
  "type": "official_web",
  "parser": "<qq|youku|qiyi|mgtv>"
}
```

| source_id | endpoint |
| --- | --- |
| official-qq | `https://pbaccess.video.qq.com` |
| official-youku | `https://search.youku.com` |
| official-qiyi | `https://www.iqiyi.com` |
| official-mgtv | `https://mobileso.bz.mgtv.com` |

（优酷/爱奇艺/芒果基址以实现客户端实际请求域名为准；一期测试至少断言腾讯。）

- [ ] **步骤 4：运行测试验证通过**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

- [ ] **步骤 5：Commit**

```bash
git add clients/apple/MultiLiveTV/Resources/source-registry.json \
  clients/apple/scripts/verify-client-logic.swift
git commit -m "$(cat <<'EOF'
chore(apple): mark official sources as official_web

Point endpoints at platform HTTP bases instead of EHR663 Python files.
EOF
)"
```

---

### 任务 3：Official 模型 + Enricher（可注入 client）

**文件：**
- 创建：`clients/apple/MultiLiveTV/Services/Official/OfficialWebModels.swift`
- 创建：`clients/apple/MultiLiveTV/Services/Official/OfficialPlayEnricher.swift`
- 修改：`clients/apple/scripts/verify-client-logic.swift`
- 修改：`clients/apple/scripts/run-logic-tests.sh`

- [ ] **步骤 1：编写失败的测试**

```swift
struct StubOfficialClient: OfficialWebClient {
    let parserKey: String
    let hits: [OfficialSearchHit]
    let movie: SourceMovie?

    func search(keyword: String, page: Int) async throws -> [OfficialSearchHit] { hits }
    func detail(id: String) async throws -> SourceMovie {
        guard let movie else { throw URLError(.badServerResponse) }
        return movie
    }
}

func testOfficialPlayEnricherPrependsMatchedLine() async {
    let source = Source(
        // 用现有 Source 测试工厂或最小 init：sourceId official-qq, numericId 901,
        // adapter official_web/qq, jxUrl xmflv, play_priority 2000
    )
    let hit = OfficialSearchHit(id: "cid1", title: "测试剧", year: "2024", poster: "", remarks: "")
    let movie = SourceMovie(
        sourceId: "official-qq",
        numericSourceId: 901,
        sourceMovieId: "cid1",
        title: "测试剧",
        year: "2024",
        poster: "",
        remarks: "",
        area: "",
        genre: "",
        blurb: "",
        content: "",
        actors: [],
        director: "",
        typeId: 0,
        typeName: "",
        playFrom: "qq",
        playURL: "第1集$https://v.qq.com/x/cover/cid1/vid1.html",
        updatedAt: 0
    )
    let client = StubOfficialClient(parserKey: "qq", hits: [hit], movie: movie)
    let primary = VodItemRaw(
        vodId: "1", vodName: "测试剧", vodPic: "", vodRemarks: "", vodYear: "2024",
        vodArea: "", vodClass: "", vodBlurb: "", vodContent: "", vodActor: "", vodDirector: "",
        vodPlayFrom: "hnm3u8", vodPlayURL: "1$https://a.com/a.m3u8", typeId: 1, typeName: "", vodTime: 0
    )
    let existing = [
        PlaySource(name: "红牛", key: "1:红牛", episodes: [Episode(name: "1", url: "https://a.com/a.m3u8")], sourceId: 1, playFrom: "hnm3u8")
    ]
    let enriched = await OfficialPlayEnricher.enrich(
        primary: primary,
        existing: existing,
        officialSources: [source],
        clients: ["qq": client],
        timeoutNanoseconds: 1_000_000_000
    )
    assertTrue(enriched.contains(where: { $0.sourceId == 901 }), "adds official-qq line")
    assertEqual(enriched.first?.sourceId, 901, "official sorted first after weighting")
}

func testOfficialPlayEnricherSkipsTitleMismatch() async {
    // hit title 不同 → 不调用 detail / 不增加线路
}
```

（`Source` / `VodItemRaw` 构造参数以仓库实际 init 为准，复制现有测试里的构造方式。）

- [ ] **步骤 2：把新文件加入 `run-logic-tests.sh` 的 `swiftc` 列表**（在 `PlayParser.swift` 附近）：

```
"$ROOT/MultiLiveTV/Services/Official/OfficialWebModels.swift" \
"$ROOT/MultiLiveTV/Services/Official/OfficialPlayEnricher.swift" \
```

运行测试，预期 FAIL（类型未定义）。

- [ ] **步骤 3：实现模型与 Enricher**

`OfficialWebModels.swift`：

```swift
import Foundation

struct OfficialSearchHit: Hashable {
    let id: String
    let title: String
    let year: String
    let poster: String
    let remarks: String
}

protocol OfficialWebClient: Sendable {
    var parserKey: String { get }
    func search(keyword: String, page: Int) async throws -> [OfficialSearchHit]
    func detail(id: String) async throws -> SourceMovie
}
```

`OfficialPlayEnricher.swift` 核心逻辑：

1. 对每个 `officialSources`（`enabled && adapter.type == "official_web"`），用 `clients[parser]` 调用
2. `withThrowingTaskGroup` + 单平台 deadline（调用方传入总超时，默认 5s）
3. search 后选第一个满足 `VodMergeService.isCompatibleVodMatch(primary, hitAsRaw)` 的 hit
4. `detail(id:)` → `PlayParser.parsePlayURL` / 或 `PlayParser.mergePlaySources` 单条
5. `PlaySource`：`key = source.sourceId`，`name = source.name`，`sourceId = source.numericId`，`playFrom = parser`（`qq`…），`mode = "direct"`，`annotate` 后与 `existing` 合并再 `PlayLineWeighting.sort`

标题匹配：把 hit 转成临时 `VodItemRaw(vodName:title, vodYear:year, …空字段)` 再调 `isCompatibleVodMatch`。

- [ ] **步骤 4：运行测试验证通过**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

- [ ] **步骤 5：Commit**

```bash
git add clients/apple/MultiLiveTV/Services/Official \
  clients/apple/scripts/verify-client-logic.swift \
  clients/apple/scripts/run-logic-tests.sh
git commit -m "$(cat <<'EOF'
feat(apple): add OfficialPlayEnricher with injectable clients

Enable detail-time official line merge behind a testable protocol.
EOF
)"
```

---

### 任务 4：腾讯 search/detail 纯解析（TDD + fixture）

**文件：**
- 创建：`clients/apple/MultiLiveTV/Services/Official/TencentWebParsing.swift`
- 修改：`clients/apple/scripts/verify-client-logic.swift`
- 修改：`clients/apple/scripts/run-logic-tests.sh`

- [ ] **步骤 1：编写失败的测试（嵌入最小 fixture JSON）**

搜索 fixture 形状对齐 spider（`data.areaBoxList[-1].itemList`）：

```swift
func testTencentParseSearch() throws {
    let json = """
    {"data":{"areaBoxList":[{"itemList":[{
      "doc":{"id":"mzc00200abc"},
      "videoInfo":{"title":"庆余年","imgUrl":"https://example.com/p.jpg","imgTag":"{\\"tag_2\\":{\\"text\\":\\"2019\\"},\\"tag_4\\":{\\"text\\":\\"更新至8集\\"}}"}
    }]}]}}
    """
    let hits = try TencentWebParsing.parseSearch(Data(json.utf8))
    assertEqual(hits.count, 1, "one hit")
    assertEqual(hits[0].id, "mzc00200abc", "cid")
    assertEqual(hits[0].title, "庆余年", "title")
    assertEqual(hits[0].year, "2019", "year from imgTag")
}

func testTencentParseDetailBuildsOfficialPageURLs() throws {
    // intro JSON: module_list_datas[0]... item_params title/year
    // episode JSON: item_datas with item_id + union_title
    // 期望 playURL 含 "第1集$https://v.qq.com/x/cover/{cid}/{vid}.html"
    // playFrom == "qq"
}
```

- [ ] **步骤 2：运行确认失败**

- [ ] **步骤 3：实现 `TencentWebParsing`**

对照 `/tmp/ehr_spiders/qq.py`：

- `parseSearch`：遍历 `areaBoxList` 最后一块 `itemList`
- `parseDetail(cid:intro:episodes:)`：演员可选；分集 `union_title$cid@item_id` → 映射为 `Episode` 名 + URL `https://v.qq.com/x/cover/{cid}/{vid}.html`（`playerContent` 逻辑）
- 预告片可单独 `playFrom` 或丢弃预告（一期：**丢弃含「预告」的分集**，降低噪音）

返回 `SourceMovie`，`playFrom: "qq"`，`playURL` 为 `#` 连接的 `名$url`。

- [ ] **步骤 4：测试通过 + 加入 `run-logic-tests.sh`**

- [ ] **步骤 5：Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(apple): parse Tencent search and detail JSON

Port EHR663 qq spider response mapping into pure Swift helpers.
EOF
)"
```

---

### 任务 5：TencentWebClient 网络层

**文件：**
- 创建：`clients/apple/MultiLiveTV/Services/Official/TencentWebClient.swift`
- 修改：`run-logic-tests.sh`、`project.pbxproj`

- [ ] **步骤 1：实现 client**

```swift
struct TencentWebClient: OfficialWebClient {
    let parserKey = "qq"
    let endpoint: URL  // from source.connection.endpoint
    var session: URLSession = .shared

    func search(keyword: String, page: Int) async throws -> [OfficialSearchHit] {
        // POST {endpoint}/trpc.videosearch.mobile_search.MultiTerminalSearch/MbSearch?vplatform=2
        // body 同 spider searchContent；Headers: User-Agent / origin https://v.qq.com / referer
        // timeout: 使用 NetworkConfig.requestTimeout 或 3s
    }

    func detail(id: String) async throws -> SourceMovie {
        // 并行两次 GetPageData（intro + episode list），与 spider detailContent 一致
        // video_appid=3000010 路径同 get_vdata
    }
}
```

请求失败抛错，由 Enricher 吞掉。

- [ ] **步骤 2：Xcode 工程**

将 `Services/Official/*.swift` 加入 **MultiLiveTV-iOS** 与 **MultiLiveTV-tvOS** 的 Compile Sources（仿 `SourceAdapter.swift` 双 target `PBXBuildFile`）。可用 Xcode 或手动编辑 `project.pbxproj`（生成唯一 24 位 hex ID）。

- [ ] **步骤 3：`run-logic-tests.sh` 加入 `TencentWebClient.swift`**

（网络 client 若依赖 UIKit 则不要；保持 Foundation-only。）

- [ ] **步骤 4：Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(apple): add TencentWebClient HTTP for official enrich

Call pbaccess search and page APIs using registry endpoint and jx-ready URLs.
EOF
)"
```

---

### 任务 6：接入详情 enrich 管道

**文件：**
- 修改：`clients/apple/MultiLiveTV/Services/VodMergeService.swift`
- 可选：`clients/apple/MultiLiveTV/Services/VodService.swift`

- [ ] **步骤 1：在 `enrichMergedVodDetail` 末尾挂官方线**

在现有 `return makeDetailResponse(...)` 之前或之后：

```swift
let base = makeDetailResponse(source: source, primary: primary, extras: extraOnly, store: store)
let officialSources = store.enabled().filter {
    $0.type == "official" && $0.adapter.type == "official_web"
}
guard !officialSources.isEmpty else { return base }

let clients = OfficialPlayEnricher.defaultClients(for: officialSources)
let playSources = await OfficialPlayEnricher.enrich(
    primary: primary,
    existing: base.playSources,
    officialSources: officialSources,
    clients: clients,
    timeoutNanoseconds: 5_000_000_000
)
return DetailResponse(
    vod: base.vod,
    playSources: playSources,
    variants: base.variants,
    merged: base.merged || playSources.count > base.playSources.count
)
```

`defaultClients(for:)`：按 `adapter.parser` 构造 `TencentWebClient(endpoint:)`；未知 parser 跳过。一期仅注册 `qq`。

- [ ] **步骤 2：手动冒烟（可选）**

真机/模拟器打开一部能在腾讯搜到的片子，确认出现「腾讯视频」线路且可点（jx 成败取决于外网）。

- [ ] **步骤 3：跑逻辑测试**

```bash
cd clients/apple && ./scripts/run-logic-tests.sh
```

- [ ] **步骤 4：Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(apple): enrich vod detail with official-web play lines

After CMS merge, search matched platform titles and prepend weighted sources.
EOF
)"
```

---

### 任务 7：一期验收清单

- [ ] **步骤 1：对照规格 §11**

- [ ] 详情在腾讯可匹配时出现官方线且排序靠前  
- [ ] enrich 失败不影响 CMS 线  
- [ ] 点播走 `sourceId` 901 的 `jx_url`  
- [ ] 首页/分类/搜索请求数不因官方源增加（capability 仍为 false）  
- [ ] `./scripts/run-logic-tests.sh` 全绿  

- [ ] **步骤 2：若有缺口，开跟随 commit 修，不扩 scope 到优酷**

---

### 任务 8（二期）：优酷 + 芒果

**文件：** `YoukuWebParsing.swift` / `YoukuWebClient.swift` / `MgtvWebParsing.swift` / `MgtvWebClient.swift`

- [ ] **步骤 1：** 各写 `parseSearch` / `parseDetail` fixture 测试（对照 `/tmp/ehr_spiders/youku.py`、`mgtv.py`）
- [ ] **步骤 2：** HTTP client；`playerContent` → 官方页 URL（优酷 `ihost/video?vid=`；芒果 `rhost+path`）
- [ ] **步骤 3：** `defaultClients` 注册 `youku`、`mgtv`
- [ ] **步骤 4：** 测试 + commit

```bash
git commit -m "$(cat <<'EOF'
feat(apple): add Youku and MGTV official-web clients

Extend detail enrich to youku and mgtv parsers with the same jx playback path.
EOF
)"
```

---

### 任务 9（三期）：爱奇艺

- [ ] 对照上游 `爱奇艺.py`（更长）移植 search/detail
- [ ] fixture 测试 + client + `defaultClients` 注册 `qiyi`
- [ ] commit

```bash
git commit -m "$(cat <<'EOF'
feat(apple): add Qiyi official-web client for detail enrich
EOF
)"
```

---

## 自检（对照规格）

| 规格章节 | 任务 |
| --- | --- |
| §1 目标 / 非目标 | 任务 1–6；不调 Python；capability false |
| §3 流程 | 任务 6 |
| §4 Registry | 任务 2 |
| §5 组件 | 任务 3–5、8–9 |
| §6 PlaySource 形状 | 任务 3、6 |
| §7 匹配 | 任务 3（`isCompatibleVodMatch`） |
| §8 超时 | 任务 3、6（5s） |
| §9 UI | 任务 1 |
| §10 分期 | 任务 4–6 = 期1；8=期2；9=期3 |
| §11 验收 | 任务 7 |

无 TBD 占位；类型名统一：`OfficialWebClient`、`OfficialSearchHit`、`OfficialPlayEnricher`、`TencentWebParsing`、`forDetailDisplay`。

---

## 执行交接

计划已保存到 `docs/superpowers/plans/2026-09-10-apple-official-web-detail-enrich.md`。

**两种执行方式：**

1. **子代理驱动（推荐）** — 每个任务调度一个新子代理，任务间审查，快速迭代  
2. **内联执行** — 当前会话用 executing-plans，批量执行并设检查点  

选哪种方式？
