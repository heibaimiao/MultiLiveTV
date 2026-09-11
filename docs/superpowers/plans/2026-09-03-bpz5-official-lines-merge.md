# 详情合并 bpz5 官方线 实现计划

> 规格：[`../specs/2026-09-03-bpz5-official-lines-merge-design.md`](../specs/2026-09-03-bpz5-official-lines-merge-design.md)

**目标：** 详情 `playSources` 按片名自动挂上 bpz5 官方 ticket 线；解票带匿名 session。

---

- [x] 匿名 session + ResolveLine 带 cookie / 401 重试
- [x] catalog 搜索 / episodes / playback resolve
- [x] EnrichOfficialPlaySources + 匹配测试
- [x] 接入 GetVodDetail
- [x] Web detail 对齐 + 规格勾选
