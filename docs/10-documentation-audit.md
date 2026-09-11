# 文档审计

审计日期：2026-09-04。范围：当前工作区源码（排除 `node_modules`、`.tmp-repos`、`.next`、`.git`）。

## 扫描规模

| 项 | 数量 |
| --- | --- |
| 扫描文件数量（go/swift/kt/ts/tsx，排除依赖） | 163 |
| Go 文件 `apps/api-go` | 37（含 8 个 `*_test.go`） |
| Handler 源文件 | 4：`vod.go` `auth.go` `admin.go` `health.go` |
| Handler 测试 | 2：`handler_test.go` `admin_test.go` |
| Service 包 | maccms、merge、unified、parser、bpz5、category、auth、admin |
| Repository | 1 文件 `db.go`（仅连接+Migrate） |
| Entity/Model | `types.go` `user.go` `maccms_json.go` `vod_time.go` |
| Apple Swift（非 Pods） | 66 |
| Android Kotlin | 4（MainActivity、ApiModels、PlayLineWeights 等） |
| HTTP 路由（完整栈） | 31 |
| OpenAPI path | 14（未含 admin/health/swagger） |
| 数据库表（AutoMigrate） | 4 |
| JSON 配置（运行时） | sources / unified-categories / play-line-weights；（Apple 另 lives） |
| 配置文件 | `config.go`、compose×2、`.env.prod.example`、Dockerfile×2、`nginx.conf`、CI yaml |
| 第三方服务 | MacCMS 采集站、jx_url 解析站、bpz5.com |
| Redis / Kafka / 定时任务框架 | 0 |

Controller 在本仓库对应 **Gin Handler**，无 Spring Controller。

## 文档覆盖率

| 文档 | 覆盖 |
| --- | --- |
| 00 总览 | 定位、栈、模块、接口/表数量、问题 |
| 01 产品 | 功能地图、角色、流程 |
| 02 API | 31 条路由参数与真实 JSON 字段 |
| 03 数据库 | 4 表 + JSON 持久化 + migration 差异 |
| 04 架构 | 真实拓扑、认证、无 MQ |
| 05 链路 | 12 条（超过要求的 10 条） |
| 06 配置 | env / JSON / Docker / CI |
| 07 部署 | compose / 命令 / 与 DEPLOY.md 差异 |
| 08 测试 | go test / smoke / 脚本 / 缺口 |
| 09 事实清单 | 上表 |
| README | 指向 docs，不重复长文 |

**未写入独立章节但已声明冻结/非主路径：** `web/app/api/*` Next 路由、`demos/`、`.tmp-repos/` 参考克隆。

## 检查清单

1. **Controller/Handler：** 已覆盖 `vod` `auth` `admin` `health`。无遗漏文件。
2. **API：** `main.go` 注册的路由均在 02 总览表中。Swagger 标为部分实现。
3. **Entity：** Source/Vod/Play/User 四组均在 02/03。
4. **数据库表：** 仅 4 张；sources 不是表。
5. **配置：** `Load()` 全部键已列入 06。compose 未传的 BPZ5 已标明。
6. **MQ：** 代码中未发现，文档未虚构。
7. **Redis：** 代码中未发现。
8. **定时任务：** 无；仅 TTL 缓存。
9. **第三方：** MacCMS、jx_url、bpz5 已记录。直播 M3U 仅 Apple。
10. **虚构检查：** 未写支付/订单/网关产品/K8s。Apple 登录按「代码中未发现」处理。PlaySource 使用 `name` 而非设计稿 `label`。

## 发现的问题（与实现相关）

- OpenAPI 落后于 Admin 与部分响应字段。
- Swagger 路由存在但无生成文档包。
- goose SQL 语法错误且未执行。
- WatchProgress 唯一索引 tag 可能与 SQL 意图不符。
- Docker 镜像缺权重/分类文件。
- 生产 compose 未接 BPZ5。
- E2E.md / DEPLOY.md Apple APIConfig 与登录项过时。
- CORS 反射任意 Origin。
- `json_parse` / `danmaku_api_url` 死字段。
- 单源 list 上游失败返回 200 空列表。
- Android 非完整工程。

## 未能确认的信息

- `/swagger/index.html` 运行时是否报错。
- AutoMigrate 在目标 Postgres 上实际创建的约束名与 `watch_progress` 唯一键形态。
- 用户删除时 PG 是否具备 ON DELETE CASCADE（模型未声明）。
- `web/lib/__tests__/*.check.ts` 是否有人手工跑。
- 各 MacCMS 源当前可达性（配置有 29 条，网络状态会变）。
- bpz5 HMAC 与前端是否仍匹配（密钥随时会换，见 souju 文档）。
- 目标用户画像、商业授权（仅 README 学习研究声明）。

## 本轮未修改

任何业务代码、OpenAPI 文件、既有 `docs/DEPLOY.md` 等均未删除或改逻辑。仅新增编号文档并更新根 `README.md`。
