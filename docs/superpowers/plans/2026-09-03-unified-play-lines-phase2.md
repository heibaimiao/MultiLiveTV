# 统一播放线路二期（bpz5 ticket 解票）实现计划

> **面向 AI 代理的工作者：** 按规格 [`../specs/2026-09-03-unified-play-lines-design.md`](../specs/2026-09-03-unified-play-lines-design.md) 与 [`../../souju-playback-api.md`](../../souju-playback-api.md) 实现。

**目标：** `POST /play/resolve` 的 `mode=ticket` 由服务端代调 bpz5 `resolve-line`，返回可播 URL；密钥不出客户端。

**架构：** Go 内嵌 HMAC 客户端；未配置密钥时仍返回 `501 ticket_not_enabled`。Web 归档站同等实现。本期**不做**详情页合并官方 `line_options`（需片库 token 映射，另开规格）。

**技术栈：** Go、Next.js、环境变量

---

### 任务 1：环境与配置
- [x] 修复 `.env.prod.example`，增加 `BPZ5_BASE_URL`、`BPZ5_HMAC_SECRET`
- [x] `config.Load` 读取上述变量

### 任务 2：Go bpz5 客户端（TDD）
- [x] 签名 / NormalizeTicket / mock ResolveLine 测试
- [x] `internal/service/bpz5/client.go`

### 任务 3：接入 ResolvePlay
- [x] ticket 分支；handler 测试；OpenAPI / 规格

### 任务 4：Web
- [x] `web/lib/bpz5.ts`；`/api/play/resolve` ticket；详情页识别 `resolve://`

### 明确不做（另开）
- 详情合并 bpz5 `line_options`
- Apple 内嵌 HMAC

---

## 验收
- [x] `go test ./internal/service/bpz5/ ./internal/handler/`
- [x] 无 secret：ticket → 501
- [x] mock upstream：ticket → 200
