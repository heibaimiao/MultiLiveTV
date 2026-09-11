# 数据库文档

> 运行时 schema 以 GORM `AutoMigrate` 为准（`apps/api-go/internal/repository/db.go`）。  
> `apps/api-go/migrations/001_init.sql` **未被进程执行**，仅作对照。

## 总览

| 项 | 事实 |
| --- | --- |
| 数据库 | PostgreSQL 16（Docker 镜像 `postgres:16-alpine`） |
| ORM | GORM v1.25 |
| 连接 | 环境变量 `DATABASE_URL`；为空则 `Connect` 返回 `(nil, nil)`，不建表 |
| 表数量 | **4** |
| 迁移工具 | 代码中未发现 goose / flyway / liquibase 调用 |
| Redis 等 | 代码中未发现 |

点播片库、源站、分类、线路权重 **不入库**。

## 表关系

```text
users 1 ──< favorites
users 1 ──< watch_progress
users 1 ──< refresh_tokens
```

均为一对多。删除用户时 Admin `DeleteUser` 在事务中先删三张子表再删 `users`。SQL 文件写了 `ON DELETE CASCADE`；GORM 模型 **未** 声明 `constraint:OnDelete:CASCADE`，运行时外键行为以 AutoMigrate 实际生成的约束为准（**待确认**）。

无多对多中间表。无软删除字段（无 `deleted_at`）。

---

## 表：users

**用途：** 注册用户账号。  
**模型：** `model.User`（`internal/model/user.go`）  
**GORM 默认表名：** `users`

| 字段 | 类型（GORM / 预期 PG） | NULL | 默认值 | 主键 | 索引 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| id | uuid | NOT NULL | 应用生成 `uuid.New()` | 是 | PK | |
| email | varchar(255) | NOT NULL | 无 | 否 | uniqueIndex | 登录名 |
| password_hash | 字符串（SQL 文件为 TEXT） | NOT NULL | bcrypt | 否 | 否 | JSON 不输出（`json:"-"`） |
| created_at | time | 否（模型无 `not null` tag） | 注册时 `time.Now()` | 否 | 否 | |

**状态字段：** 代码中未发现（无 banned / verified）。

---

## 表：favorites

**用途：** 用户收藏影片。业务键是 `merge_key`（与片名规范化相关，由客户端传入，服务端不计算）。  
**模型：** `model.Favorite`

| 字段 | 类型 | NULL | 默认值 | 主键 | 索引 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| id | uuid | NOT NULL | `uuid.New()` | 是 | PK | |
| user_id | uuid | NOT NULL | JWT 解析 | 否 | index；`uniqueIndex:idx_user_favorite` | |
| merge_key | varchar(255) | NOT NULL | 请求体 | 否 | `uniqueIndex:idx_user_favorite` | 与 user_id 组成唯一 |
| vod_name | varchar(255) | NOT NULL | 请求体 | 否 | 否 | |
| primary_source_id | int | 模型无 not null | 请求体 | 否 | 否 | |
| primary_vod_id | varchar(64) | NOT NULL | 请求体 | 否 | 否 | |
| poster | varchar(512) | 可空 | 请求体可选 | 否 | 否 | |
| created_at | time | — | GORM 创建时间 | 否 | 否 | |

重复添加同一 `merge_key`：handler 先查已有记录，存在则 **200 返回已有行**，不报 409。

---

## 表：watch_progress

**用途：** 播放进度。  
**模型：** `model.WatchProgress`

| 字段 | 类型 | NULL | 默认值 | 主键 | 索引 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| id | uuid | NOT NULL | `uuid.New()` | 是 | PK | |
| user_id | uuid | NOT NULL | JWT | 否 | index | **未** 打 `uniqueIndex:idx_user_progress` |
| progress_key | varchar(255) | NOT NULL | 请求体 | 否 | `uniqueIndex:idx_user_progress` | 含义由客户端约定，服务端不解析 |
| position_sec | float64 | — | 0（请求可省略） | 否 | 否 | |
| duration_sec | float64 | — | 0 | 否 | 否 | |
| updated_at | time | — | GORM 更新 | 否 | 否 | |

**注意：** GORM 复合唯一索引需要同名 `uniqueIndex` 打在多个字段上。当前只有 `progress_key` 带 `idx_user_progress`，因此 AutoMigrate 很可能把 **progress_key 全局唯一**，而不是 `(user_id, progress_key)`。SQL 文件意图是后者。以实际库 `\d watch_progress` 为准（**待确认**）。

PUT 逻辑：按 `user_id + progress_key` 查找，有则更新，无则插入。

---

## 表：refresh_tokens

**用途：** 刷新令牌哈希存储。明文 refresh 只在登录响应出现。  
**模型：** `model.RefreshToken`

| 字段 | 类型 | NULL | 默认值 | 主键 | 索引 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| id | uuid | NOT NULL | `uuid.New()` | 是 | PK | |
| user_id | uuid | NOT NULL | 用户 ID | 否 | index | |
| token_hash | varchar(128) | NOT NULL | SHA-256 hex | 否 | 否 | JSON 不输出 |
| expires_at | time | — | now + 7 天 | 否 | 否 | |
| created_at | time | — | now | 否 | 否 | |

刷新成功后 **删除旧行** 再写入新 token（rotation）。无按过期时间清理的定时任务（**代码中未发现**）。

---

## 非数据库持久化

| 数据 | 介质 | 写入方 |
| --- | --- | --- |
| 采集站列表 | `config/sources.json` | 启动加载；Admin Upsert/Delete 写回文件 |
| 统一分类 | `unified-categories.json` | 启动只读；脚本 `scripts/refresh-unified-categories.py` |
| 线路权重 | `play-line-weights.json` | 启动只读 |
| 分类树缓存 | 进程内存，TTL 5 分钟 | `category.Cache` |
| 请求日志 | 内存环形缓冲 200 条 | `RequestLogBuffer` |
| Apple 下载记录 | 客户端本地（`DownloadStore`） | Apple App |
| Apple Top Shelf | 客户端本地 | `TopShelfStore` |

## SQL 文件问题

`migrations/001_init.sql` 第 17–18 行：

```sql
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    UNIQUE(user_id, merge_key)
```

`NOW()` 后缺少逗号。该文件若被 goose 直接执行会失败。当前启动路径不使用它。
