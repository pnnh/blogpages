# Cloudflare D1：`migrations apply --remote` 与本地/远程表结构冲突处理指南

> 针对命令  
> `npx wrangler d1 migrations apply <database> --remote`  
> 说明它如何决定「该不该跑某份迁移」、失败时会发生什么、远程没有 `d1_migrations` 时怎么处理，以及本地模拟库与远程 D1 结构不一致时如何对齐。
>
> 文中数据库名以 `my-app-db` 为例，请换成你的 `database_name` 或 binding 名。

---

## 目录

- [1. 先分清三套「真相」](#1-先分清三套真相)
- [2. apply 实际比较的是什么](#2-apply-实际比较的是什么)
- [3. 命令执行流程](#3-命令执行流程)
- [4. 出错时 Wrangler 会怎样](#4-出错时-wrangler-会怎样)
- [5. 远程还没有 d1_migrations 时](#5-远程还没有-d1_migrations-时)
- [6. 典型冲突与处理](#6-典型冲突与处理)
- [7. 如何对比本地和远程结构](#7-如何对比本地和远程结构)
- [8. 推荐操作清单](#8-推荐操作清单)
- [9. 日常如何避免再冲突](#9-日常如何避免再冲突)
- [10. 命令速查](#10-命令速查)

---

## 1. 先分清三套「真相」

本地 D1 和远程 D1 是 **两套独立的 SQLite**，不会自动同步。冲突往往来自把下面三件事当成了同一件事：

| 来源 | 是什么 | 说明 |
|---|---|---|
| Git 里的迁移文件 | `drizzle/` 或 `migrations/` 下的 `.sql` | 团队约定的 schema 演变史，应作为唯一来源 |
| 账本表 `d1_migrations` | 每套库各自一份 | Wrangler 用它判断「哪些文件已经打过」 |
| 真实 schema | `sqlite_schema` 里的表、索引、视图 | 可能被 dump、`d1 execute`、`drizzle-kit push` 改过，和账本不一定一致 |

`apply` **只看前两套**：磁盘上的文件列表 vs 目标库 `d1_migrations.name`。  
它 **不会** 先 diff 本地表结构和远程表结构。

所以会出现：

- 远程表已经在，账本没有记录 → 再执行 `CREATE TABLE` → `already exists`
- 账本有记录，表被人 DROP 了 → apply 认为没问题，应用代码却查不到表
- 本地已 apply 完，远程是空账本 → 远程会被当成「全部未应用」

---

## 2. apply 实际比较的是什么

对指定的那一套库（`--local` 或 `--remote`）：

1. 按 Wrangler 配置收集迁移文件  
   - 默认：`migrations_dir/*.sql`  
   - Drizzle 嵌套布局需要：

```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "my-app-db",
    "database_id": "<UUID>",
    "migrations_dir": "drizzle",
    "migrations_pattern": "drizzle/*/migration.sql"
  }
]
```

2. 读取该库的 `d1_migrations`（可用 `migrations_table` 改名）
3. 文件有、账本没有的，视为未应用，按文件名顺序执行
4. **整份文件成功后** 才 `INSERT` 一行 `name`

Drizzle 嵌套目录下，账本里的 `name` 一般是相对 `migrations_dir` 的路径，例如：

```text
0000_init/migration.sql
0001_users/migration.sql
```

手工补账本时，`name` 必须和 `wrangler d1 migrations list` 打印的字符串完全一致。

账本 DDL（Wrangler 会按需创建）：

```sql
CREATE TABLE IF NOT EXISTS d1_migrations (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
```

---

## 3. 命令执行流程

```bash
npx wrangler d1 migrations apply my-app-db --remote
```

大致步骤：

1. 解析 Wrangler 配置，定位远程 `database_id`
2. `CREATE TABLE IF NOT EXISTS d1_migrations (...)`
3. 计算未应用文件列表并打印
4. 交互环境要求确认；CI 非交互会跳过确认，但仍会尝试备份
5. 按顺序执行每一份未应用 SQL
6. 该份成功 → 写入 `d1_migrations`
7. 该份失败 → 停止，不再跑后面的文件

`--local` 打的是 Wrangler 给 `wrangler dev` 用的本地持久化库，与远程互不影响。

---

## 4. 出错时 Wrangler 会怎样

官方说明：

> 某一份迁移执行出错时，这一份会被回滚；此前已经成功的迁移保持已应用。

实际含义要拆开看：

| 层级 | 行为 |
|---|---|
| 账本 | 失败的那一份 **不会** 出现在 `d1_migrations` 里，下次 apply 还会再试它 |
| 后续文件 | 不会执行 |
| 真实 schema | **不保证**回到该份开始之前。SQLite/D1 的 DDL（`CREATE TABLE` / `ALTER TABLE`）经常无法整段回滚 |

典型结果：

- 文件第一句就是 `CREATE TABLE users`，而 `users` 已存在  
  → 整份失败，账本不记；表保持原样。再 apply 会再次失败。
- 文件里先建了 `users` 成功，后建 `orders` 失败  
  → `users` 往往还在，整份未记账。再 apply 会在 `CREATE TABLE users` 上再次失败。
- 纯 DML 在同一批语句里失败  
  → 更可能整段撤销，但仍不要假设一定如此。

生产上误跑、需要整库回到 apply 之前，用 D1 Time Travel（约 30 天、分钟级），不是日常 down migration：

```bash
npx wrangler d1 time-travel info my-app-db
npx wrangler d1 time-travel restore my-app-db --timestamp=2026-09-21T08:00:00Z
```

Restore 会覆盖整个远程库。

---

## 5. 远程还没有 d1_migrations 时

不必先手工建表。`apply --remote` 会 `CREATE TABLE IF NOT EXISTS`。

先看远程有没有业务表：

```bash
npx wrangler d1 execute my-app-db --remote --command \
  "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name;"
```

### 5.1 远程是空库

直接：

```bash
npx wrangler d1 migrations list my-app-db --remote
npx wrangler d1 migrations apply my-app-db --remote
```

会建账本并按顺序打完全部文件。这是最干净的路径。

### 5.2 远程已有业务表，只是没有账本

**不要**直接指望 apply 一次成功。它会建空账本，再把第 1 份迁移当未应用执行，撞上 `already exists`。

处理：

1. 让账本出现（apply 失败一次通常已经建好表，或显式执行上面的 `CREATE TABLE IF NOT EXISTS`）
2. 确认远程 schema 已经等价于前 N 份迁移
3. 把这 N 个 `name` 插入账本（基线记账）
4. 再 `apply`，只跑后面真正缺的文件

```bash
npx wrangler d1 migrations list my-app-db --remote

npx wrangler d1 execute my-app-db --remote --command \
  "INSERT INTO d1_migrations (name) VALUES ('0000_init/migration.sql');"

npx wrangler d1 execute my-app-db --remote --command \
  "INSERT INTO d1_migrations (name) VALUES ('0001_users/migration.sql');"

npx wrangler d1 migrations list my-app-db --remote
npx wrangler d1 migrations apply my-app-db --remote
```

本地若已经正常 apply 过，用本地账本当「该插入哪些 name」的模板：

```bash
npx wrangler d1 execute my-app-db --local --command \
  "SELECT name FROM d1_migrations ORDER BY id;"
```

只插入「远程结构已经具备」的那些 name，不要把尚未体现在远程 schema 上的文件也标记为已应用。

### 5.3 远程有表但可以推倒（无重要数据）

删掉业务表后按空库 apply，或新建一个 D1 改 `database_id`。有生产数据时不要走这条。

---

## 6. 典型冲突与处理

先采集状态，再对号入座：

```bash
npx wrangler d1 migrations list my-app-db --local
npx wrangler d1 migrations list my-app-db --remote

npx wrangler d1 execute my-app-db --local --command \
  "SELECT id, name, applied_at FROM d1_migrations ORDER BY id;"
npx wrangler d1 execute my-app-db --remote --command \
  "SELECT id, name, applied_at FROM d1_migrations ORDER BY id;"

npx wrangler d1 execute my-app-db --remote --command \
  "SELECT name, sql FROM sqlite_schema
   WHERE type IN ('table','index')
     AND name NOT LIKE 'sqlite_%'
     AND name NOT IN ('_cf_KV','d1_migrations')
   ORDER BY type, name;"
```

### 冲突 1：远程表已存在，账本没有对应行

**现象：** `apply --remote` 报 `table ... already exists`。

**原因：** dump、`d1 execute --file`、`drizzle-kit push`、或失败半截留下的表。

**处理：**

- 结构已与该份（及之前若干份）迁移等价 → **基线记账**（第 5.2 节），不要重跑 `CREATE TABLE`
- 只想改未发布过的迁移文件 → 可改成幂等后再 apply：

```sql
CREATE TABLE IF NOT EXISTS users ( ... );
CREATE INDEX IF NOT EXISTS users_email_idx ON users (email);
```

已在任一环境成功记账的文件不要改内容，否则 git 历史分叉。已发布的文件只允许再加一份修复迁移。

### 冲突 2：一份迁移执行到一半失败（半截 schema）

**现象：** `users` 在、`orders` 不在，整份未进入账本。再 apply 卡在已存在的 `users`。

**处理（三选一）：**

1. 手工补齐缺失对象，再按冲突 1 把这一份 `name` 记入账本  
2. 新增 `00xx_repair_....sql`，只建缺的对象（`IF NOT EXISTS`）；失败的那份用记账跳过，保留原文件  
3. Time Travel 回到该次 apply 之前，修好 SQL 再 apply

### 冲突 3：账本有记录，对象却不在

**现象：** `list` 显示已应用，查询报 `no such table`。

**原因：** 有人 `DROP TABLE`、导入时覆盖、或 Time Travel / 换库后没重打迁移。

**处理：**

- 对象不该存在 → 从账本删除对应 `name` 后重新 apply（确认 SQL 是安全的 `CREATE`）  
- 误删表且需要数据 → Time Travel  
- 空表即可 → 写一份修复迁移重建对象，不要改已经记账的旧文件

删除账本行示例（谨慎）：

```bash
npx wrangler d1 execute my-app-db --remote --command \
  "DELETE FROM d1_migrations WHERE name = '0002_orders/migration.sql';"
```

### 冲突 4：本地已全部应用，远程落后或为空账本

这不是错误，是正常的环境差。

**处理：** 以 git 迁移文件为准，让远程追赶。

- 远程空库 → `apply --remote`
- 远程有表无账本 → 先基线再 apply
- 远程账本只少最后几份 → 直接 `apply --remote`

本地多打几份、远程少几份可以；**不要**让远程账本出现本地 git 里没有的 `name`。

### 冲突 5：两边 `name` 字符串对不上

**现象：** 同一份 SQL，本地记成 `0001_users.sql`，远程按 pattern 记成 `0001_users/migration.sql`。`list` 两边对不齐，apply 行为混乱。

**处理：** 本地和远程使用同一份 Wrangler 配置（同一 `migrations_dir`、`migrations_pattern`、`migrations_table`）。改 pattern 后，以 `migrations list` 的新名字为准，必要时更新账本里的 `name`（先 list 确认，再 `UPDATE`/`INSERT`）。

### 冲突 6：混用了两套迁移系统

`drizzle-kit migrate` / `push` 使用 `__drizzle_migrations`（或自定义名），**不是** `d1_migrations`。

远程如果只被 Kit 推过：

- 业务表可能已在
- `d1_migrations` 仍不存在或为空
- `apply --remote` 会按「全部未应用」重跑

**处理：** 选定一个权威执行器。推荐生产只用 Wrangler apply；Kit 只负责 `generate`。已用 Kit 推过的库，按冲突 1 做基线记账，之后停止 `push`。

### 冲突 7：本地和远程列/索引不一致（漂移）

账本看起来对齐，但有人手改过远程列，或本地多跑过实验 SQL。

`apply` 发现不了这种问题。用第 7 节做 DDL diff，然后：

- 差异是远程缺的正式变更 → 写成新迁移，先 local 再 remote apply
- 差异是远程多出来的实验列 → 新迁移把它纳入正式 schema，或评估能否删掉
- 不要改已经应用过的旧 SQL 文件去「修补历史」

---

## 7. 如何对比本地和远程结构

Wrangler **没有** `d1 schema diff` 这类命令。用下面几种近似方法。

### 7.1 只比迁移进度

```bash
npx wrangler d1 migrations list my-app-db --local
npx wrangler d1 migrations list my-app-db --remote
```

只能说明未应用文件列表，不能说明列是否被改过。

### 7.2 导出两边 DDL 再 diff（推荐）

```bash
npx wrangler d1 export my-app-db --local  --no-data --output=/tmp/d1-local.sql
npx wrangler d1 export my-app-db --remote --no-data --output=/tmp/d1-remote.sql

diff -u /tmp/d1-local.sql /tmp/d1-remote.sql
```

导出可能包含 `d1_migrations`、`_cf_KV`，对比前可先删掉这些段落。FTS5 等虚拟表 export 支持不完整。

或只拉 schema 目录：

```bash
npx wrangler d1 execute my-app-db --local --json --command \
  "SELECT type, name, sql FROM sqlite_schema
   WHERE name NOT LIKE 'sqlite_%'
     AND name NOT IN ('_cf_KV','d1_migrations')
   ORDER BY type, name;" > /tmp/schema-local.json

npx wrangler d1 execute my-app-db --remote --json --command \
  "SELECT type, name, sql FROM sqlite_schema
   WHERE name NOT LIKE 'sqlite_%'
     AND name NOT IN ('_cf_KV','d1_migrations')
   ORDER BY type, name;" > /tmp/schema-remote.json

diff -u /tmp/schema-local.json /tmp/schema-remote.json
```

### 7.3 用 sqldiff（本机有 sqlite3 / sqldiff 时）

```bash
rm -f /tmp/local.db /tmp/remote.db
sqlite3 /tmp/local.db  < /tmp/d1-local.sql
sqlite3 /tmp/remote.db < /tmp/d1-remote.sql
sqldiff --schema /tmp/local.db /tmp/remote.db
```

输出的是「把左边变成右边」的 SQL，便于判断缺了什么，不要不经审阅直接打到生产。

### 7.4 Drizzle 能做什么

| 命令 | 比较对象 |
|---|---|
| `drizzle-kit generate` | `schema.ts` vs 上次 snapshot |
| `drizzle-kit check` | 迁移 journal 是否自洽，不连库 |
| `drizzle-kit pull`（`d1-http`） | 只内省远程 D1，生成 schema.ts |
| `drizzle-kit push` | schema.ts → 配置里的那一套库 |

没有官方的「本地 D1 live vs 远程 D1 live」一条命令。要对代码 schema 和远程库：先 `pull` 远程到临时目录，再和仓库 `schema.ts` diff。

---

## 8. 推荐操作清单

在生产执行 `apply --remote` 之前：

1. 迁移文件已提交 git，本地 `wrangler dev` 验证过  
2. `list --local` 与 `list --remote` 已对比  
3. 远程若无账本：先判断是空库还是已有表（第 5 节）  
4. 远程已有表：先基线记账，确认 `list --remote` 只剩下真正未建的文件  
5. 有疑虑时先 `export --no-data` 做 DDL diff  
6. 再 `apply --remote`  
7. 再次 `list --remote`，并抽查 `SELECT COUNT(*)` / 关键表结构  

决策简图：

```text
apply --remote 失败或不敢跑
        │
        ├─ 远程没有任何业务表 ──────────► 直接 apply
        │
        ├─ 有表，无 d1_migrations
        │         ├─ 结构 = 前 N 份迁移 ─► INSERT name × N，再 apply 剩余
        │         └─ 结构残缺 / 不明 ──► 导出 DDL 对比 → 补对象或 Time Travel
        │
        ├─ 有账本，apply 报 already exists
        │         └─ 失败那一份对应的表已在 ─► 只补这一份 name，再 apply
        │
        └─ 有账本，对象缺失 ────────────► 修复迁移或 Time Travel，不要改旧文件
```

---

## 9. 日常如何避免再冲突

1. **单一执行器：** 生产 schema 只通过 `wrangler d1 migrations apply` 变更。`drizzle-kit` 只 `generate`。  
2. **先 local 后 remote：** 同一 git 文件，先 `--local` 验证，再 `--remote`。  
3. **已应用文件只追加不改写：** 需要修正就新增下一份。  
4. **导入数据不要带 CREATE TABLE：** 空库先 apply 建表，dump 只留 `INSERT`。  
5. **多环境各用各的 D1：** staging / production 不同 `database_id`，各有各的 `d1_migrations`。对齐的是文件内容，不是共用一张账本。  
6. **配置一致：** 所有环境相同的 `migrations_dir`、`migrations_pattern`、`migrations_table`。  
7. **不要把本地整库 export 直接 execute 到远程** 来「同步」（会把本地账本、内部表和数据缠在一起）。

`package.json` 示例：

```json
{
  "scripts": {
    "db:list:local": "wrangler d1 migrations list my-app-db --local",
    "db:list:remote": "wrangler d1 migrations list my-app-db --remote",
    "db:apply:local": "wrangler d1 migrations apply my-app-db --local",
    "db:apply:remote": "wrangler d1 migrations apply my-app-db --remote",
    "db:schema:local": "wrangler d1 export my-app-db --local --no-data --output=/tmp/d1-local.sql",
    "db:schema:remote": "wrangler d1 export my-app-db --remote --no-data --output=/tmp/d1-remote.sql"
  }
}
```

---

## 10. 命令速查

```bash
# 进度
npx wrangler d1 migrations list my-app-db --local
npx wrangler d1 migrations list my-app-db --remote

# 应用
npx wrangler d1 migrations apply my-app-db --local
npx wrangler d1 migrations apply my-app-db --remote
npx wrangler d1 migrations apply my-app-db --remote --env production

# 账本与目录
npx wrangler d1 execute my-app-db --remote --command \
  "SELECT id, name, applied_at FROM d1_migrations ORDER BY id;"
npx wrangler d1 execute my-app-db --remote --command \
  "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name;"

# 基线记账（name 以 list 输出为准）
npx wrangler d1 execute my-app-db --remote --command \
  "INSERT INTO d1_migrations (name) VALUES ('0000_init/migration.sql');"

# 结构导出
npx wrangler d1 export my-app-db --local  --no-data --output=/tmp/d1-local.sql
npx wrangler d1 export my-app-db --remote --no-data --output=/tmp/d1-remote.sql

# 事故回退（覆盖整库）
npx wrangler d1 time-travel info my-app-db
npx wrangler d1 time-travel restore my-app-db --bookmark=<bookmark>
```

---

## 附录：和数据迁移的关系

表结构冲突按本文处理。已有行数据的导入仍建议：

1. 远程 schema 与目标迁移对齐（apply 或基线）  
2. `sqlite3 ./data.db .dump > dump.sql`  
3. 去掉 `BEGIN`/`COMMIT`、内部表、所有 `CREATE TABLE`（只留 INSERT）  
4. 拆分过长的 INSERT  
5. `npx wrangler d1 execute my-app-db --remote --file=./dump.sql`

结构未对齐时不要先灌数据。

---

*命令与表名以 Cloudflare D1 / Wrangler 当前公开行为为准。执行破坏性操作（DROP、Time Travel、改账本）前先导出 schema 或确认 bookmark。*
