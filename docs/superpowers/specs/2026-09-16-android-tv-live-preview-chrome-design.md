# Android TV 直播页：背景预览 + 半透明双列选台

日期：2026-09-16  
范围：`clients/android/tv` 直播 Tab（`LiveScreen` + 内嵌播放）  
非目标：本次不改 Pad（`:app`）、不改 M3U 源、不改影视首页/播放器

---

## 1. 背景与目标

### 现状

- 布局：Sidebar | 分组列表 | 频道**网格**
- 点频道 → 导航 `livePlayer` → `LivePlayerScreen` 全屏播放
- 全屏页已支持上下/频道键切台（与本次「观看态上下只唤出列表」冲突，需迁移）

### 目标体验

用户在直播页即可：

1. 半透明双列（分组 + 频道列表）浏览
2. 焦点停在某频道后**自动静音预览**该台（背景全屏视频）
3. OK 进入**观看态**：收起列表、开声
4. 观看态再按 OK / 上下 / Menu：**只唤出列表**，不直接切台
5. 列表透明但**文字可读**（焦点行强对比）

核心原则：Live 页内嵌**唯一** ExoPlayer；浏览/观看是同一播放会话的 UI 态，不再为预览单独起第二个播放器。

---

## 2. 已确认产品决策

| 项 | 决策 |
|----|------|
| 预览触发 | **A**：焦点停留后自动预览 |
| 预览防抖 | 建议 **600ms**（可配置常量）；只播最后聚焦频道 |
| 声音 | **浏览静音 → OK 观看开声** |
| 观看态 UI | **收起**分组列 + 频道列（及左侧全局 Sidebar 是否同藏：见 §4.3） |
| 唤出列表 | 观看态：OK / DirectionUp / DirectionDown / Menu |
| 观看态上下 | **B**：只唤出列表，**不**直接切台 |
| 布局 | **保留双列**：左分组 + 右频道；左右键切换列 |
| 实现路径 | **方案 A**：Live 页内嵌唯一 Player，弱化/移除独立 `livePlayer` 路由 |

---

## 3. 信息架构与状态机

### 3.1 视觉层级

```text
底层：全屏 Live 视频（ExoPlayer Surface）
中层：错误/缓冲 OSD（轻量）
上层：浏览态 Chrome
      ├── 可选：全局 Sidebar（见 §4.3）
      ├── 分组列（半透明）
      └── 频道列（半透明）
观看态：上层 Chrome 全部隐藏（或仅极短 OSD）
```

### 3.2 UI 模式

```text
loading / empty / error（无分组数据）
        ↓
browse（浏览态）
  - chromeVisible = true
  - player.volume = 0
  - focus ∈ { sidebar?, group, channel }
  - channel 焦点停留 ≥ debounce → preview(channel)
        ↓ OK（焦点在频道行）
watch（观看态）
  - chromeVisible = false
  - player.volume = 1（或系统音量）
  - 焦点落在全屏可聚焦容器（吞键用）
        ↓ OK | Up | Down | Menu
browse（焦点恢复到当前播放频道行）
```

### 3.3 Back 键

| 当前 | Back |
|------|------|
| watch | → browse（显示双列，焦点回当前频道） |
| browse 且焦点在频道列 | → 焦点到分组列（或该组第一项） |
| browse 且焦点在分组列 | → 焦点到 Sidebar「直播」 |
| Sidebar | 系统默认 / 不在本次强改 |

禁止：观看态一次 Back 直接退出 App 或离开直播 Tab。

### 3.4 预览请求代数

与首页分类 `loadGeneration` 同理：

- `previewGeneration` / Job：每次焦点目标变化 +1 并 cancel 旧 Job
- 防抖结束后若 generation 仍匹配，才 `setMediaItem` / prepare
- 快速滑动时中间台不得完成起播

---

## 4. Focus 与遥控器

### 4.1 浏览态

- **上下**：当前列内移动（分组列或频道列）
- **左右**：Sidebar ↔ 分组 ↔ 频道（边界不循环或按现有 Sidebar 习惯）
- **OK**：
  - 焦点在分组：选中该组并 dual-focus 到该组频道列第一项（或上次该组频道）
  - 焦点在频道：进入 **watch**
- 切换分组：频道列刷新为该组列表；预览目标重置；可先停在「该组第一项」并启动防抖预览

### 4.2 观看态

- **Up / Down / OK / Menu**：`chromeVisible = true`，回到 browse，焦点在**当前正在播放**的频道行
- **ChannelUp / ChannelDown**（若遥控器有实体键）：与 DirectionUp/Down **同一语义**（只唤出列表），避免与旧 `LivePlayerScreen` 直接 zap 行为不一致造成困惑  
  - 若后续要恢复「实体频道键直接切台」，单开产品开关，默认关闭
- 其它键：不强制处理

### 4.3 全局 Sidebar

推荐（默认写入规格）：

- **浏览态**：Sidebar 可见（与现在一致），便于回首页
- **观看态**：Sidebar **一并隐藏**，真正全屏
- 从 watch 唤出 browse 时 Sidebar 一并恢复

备选（若实现成本高）：观看态只藏分组+频道，Sidebar 仍在——不推荐，会破坏「电视感」。

### 4.4 与旧全屏页切台逻辑

现有 `LivePlayerScreen` 在全屏用上下直接 zap。本规格采用 **B**，该行为**不再作为主路径**。  
迁移后：`livePlayer` 路由可删除或仅作深链兜底；主路径为内嵌播放。

---

## 5. 视觉：透明列表 + 字体可读性

### 5.1 列容器

- 背景：`Color.Black.copy(alpha ≈ 0.50)`（实现时抽常量，允许 0.45–0.55 微调）
- **不要**整列高模糊毛玻璃（TV 性能差）；如需分隔可用细边或轻渐变
- 列宽：分组列约保持现宽（~148dp）；频道列可略宽以便长台名

### 5.2 行样式

| 状态 | 背景 | 文字 |
|------|------|------|
| 普通 | 透明或 alpha≤0.15 | `textPrimary` / `textSecondary`，可加 1dp 暗色阴影 |
| 选中但未焦（当前分组） | 轻强调底 | 次级高亮 |
| **焦点行** | **不透明或 α≥0.92 实色条**（可用 `accent`） | 高对比（黑字或纯白，与底对比 ≥ WCAG 思路） |

禁止：焦点行也半透明白字压在亮视频上。

### 5.3 内容

- 频道行主文案：台名（单行 ellipsis）
- Logo：可选缩小左侧图标；无 logo 不占大块 16:9（网格卡片逻辑删除）
- 去掉「卫视频道 / N 个频道」大标题占位，或改为频道列顶一行小字（半透明区顶部）

### 5.4 OSD（观看态 / 切预览瞬间）

- 短暂显示：频道名、可选「分组 · 第 i/n」
- 约 2–2.5s 后淡出（可复用现 `LivePlayerScreen` OSD 时长思路）
- 不挡住焦点行（浏览态不必叠大 OSD）

---

## 6. 播放器行为

### 6.1 单一实例

- `LiveScreen`（或其子 `LiveStage`）`remember` 一个 `ExoPlayer`
- `DisposableEffect`：离开组合 → `release()`
- Tab 切走 / 进详情 / App 后台：`playWhenReady=false` + stop/clearMediaItems（实现选稳妥方案，避免音频残留）

### 6.2 起播

- 输入：`LiveChannel.streams`（可多线路）
- 默认从 `streams.first()` 开始；失败则顺序试下一线路（与现全屏页可对齐增强）
- Headers：沿用 `LiveStream.headers`，空则 `User-Agent`
- 浏览态：`volume = 0f`，`playWhenReady = true`（静音解码预览）
- 观看态：`volume = 1f`

### 6.3 换台

- 同一 Player `setMediaItem` / `prepare`，避免频繁 `release`+新建（防抖后执行）
- 换台瞬间可保留上一帧或黑场；需避免长时间显示错误旧台名

### 6.4 错误与缓冲

| 场景 | UI |
|------|----|
| 缓冲 | 角落小 Progress 或 OSD「加载中」 |
| 当前线路失败 | 自动下一线路；都失败则 OSD「无法播放」+ 保留列表可换台 |
| 无可用 URL | 不调用 prepare；OSD 提示 |
| 列表加载失败 | 保持现有空态 + 重试（无背景播放） |

### 6.5 首次进入

- 加载完分组后：焦点到分组列（或恢复记忆）
- **记忆（推荐做）**：上次 `groupName + channelId`；进入后选中该组该台并启动预览防抖
- 无记忆：第一组第一台，防抖后预览

---

## 7. 与导航 / 路由

### 7.1 主路径

```text
Tab.Live → LiveScreen（内嵌 Player + 双列）
不再：LiveScreen → navigate("livePlayer")
```

### 7.2 `livePlayer` 路由

- 删除主入口调用；或保留路由但 `LivePlayerScreen` 改为薄封装跳回同一体验（不推荐双实现）
- `MainActivity.hideChrome`：观看态时 Live Tab 自身藏 Sidebar，等同全屏；若 `hideChrome` 仅认 route 前缀，需扩展为「Live 且 watch」或 Live 常驻自管 chrome

### 7.3 Pad

- **本次不做**；`:app` Live 保持网格/现逻辑
- 规格注明：日后 Pad 可用「点选预览 / 再点全屏」，模型不同

---

## 8. 非目标 / 不做

- 不改 `lives.json` / M3U 源内容
- 不做 EPG 节目单
- 不做多路画中画
- 不做浏览态出声或预览小声（已否决）
- 不做观看态上下直接 zap（已选 B）
- 不引入新第三方 UI 库

---

## 9. 实现落点（指导，非本次编码）

| 区域 | 说明 |
|------|------|
| `tv/.../ui/LiveScreen.kt` | 主改造：Box 底层 Player + 半透明双列 LazyColumn |
| `tv/.../player/PlayerScreen.kt` 中 Live 部分 | 抽可复用 `LivePreviewPlayer` / 起播逻辑；或内联到 LiveScreen |
| `tv/.../MainActivity.kt` | 去掉 `pendingLive`→`livePlayer`；Live Tab chrome 与 watch 联动 |
| `core` | 可选：`LivePreviewPolicy`（debounce ms、是否 mute）纯函数 + 单测 |
| 测试 | 防抖/generation、Back 栈语义用 JVM 测；UI 真机验透明对比度 |

---

## 10. 验收标准

- [ ] 频道为上下列表，非网格
- [ ] 分组列 + 频道列均半透明，背后可见视频
- [ ] 焦点行文字在亮/暗画面下仍清晰
- [ ] 焦点停在频道 ≥ debounce 后静音预览该台；快速滑动不误播中间台
- [ ] OK → 列表（+Sidebar）隐藏并出声
- [ ] 观看态 Up/Down/OK/Menu → 只显示列表，焦点在当前台，不立刻换台
- [ ] 在列表再次上下并停留 → 换预览（仍静音直到再次 OK？见开放问题）
- [ ] Back：watch→browse→分组/Sidebar 逐步返回
- [ ] 离开直播 Tab 无残留声音
- [ ] 多线路失败有降级提示
- [ ] Pad 行为未误改

---

## 11. 开放问题（实现前需默认）

1. **从观看态唤出列表后，焦点仍在当前台：此时是否保持有声，还是回到浏览静音？**  
   - **默认建议：唤出列表 = 回到 browse = 重新静音**，直到再次 OK。避免「列表挡着还在大声播」。  
2. Sidebar 观看态是否必藏：规格默认 **必藏**。  
3. 实体 ChannelUp/Down：默认与方向键相同（只唤出列表）。

若无异议，按上述默认实现。

---

## 12. 规格自检

- 无 TBD 占位实现细节（开放问题已给默认）
- 与已确认选择 A/1/1/B/双列/方案 A 一致
- 范围限定 TV；明确非目标
- 未要求现在改代码
