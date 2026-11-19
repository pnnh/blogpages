# 将应用发布到 Cloudflare Workers：完整步骤与 Wrangler 使用指南

> 面向从零发布到生产落地的实践文档。涵盖账号准备、Wrangler 安装与登录、项目脚手架、配置文件、本地开发、正式发布、版本与灰度、密钥与多环境、CI/CD、从本地 SQLite + Drizzle 迁移到 D1，以及常见问题。
>
> 命令以官方当前用法为准：旧命令 `wrangler publish` 已淘汰，统一使用 `wrangler deploy`。

---

## 目录

- [1. 概念：Workers 与 Wrangler](#1-概念workers-与-wrangler)
- [2. 前置条件](#2-前置条件)
- [3. 安装 Wrangler](#3-安装-wrangler)
- [4. 登录与鉴权](#4-登录与鉴权)
- [5. 准备项目](#5-准备项目)
- [6. 配置文件（发布的核心）](#6-配置文件发布的核心)
- [7. 本地开发](#7-本地开发)
- [8. 发布到线上](#8-发布到线上)
- [9. 密钥、域名与路由](#9-密钥域名与路由)
- [10. 常用命令速查](#10-常用命令速查)
- [11. 生产实践：多环境与 CI/CD](#11-生产实践多环境与-cicd)
- [12. 从本地 SQLite + Drizzle 迁移到 Cloudflare D1](#12-从本地-sqlite--drizzle-迁移到-cloudflare-d1)
- [13. 常见问题与坑](#13-常见问题与坑)
- [14. 最短路径（Hello World）](#14-最短路径hello-world)
- [15. 参考链接](#15-参考链接)

---

## 1. 概念：Workers 与 Wrangler

**Cloudflare Workers** 是运行在 Cloudflare 全球边缘网络上的无服务器运行时。典型用途包括：

- HTTP API / 反向代理 / 边缘中间件
- 静态站点与 SPA（配合 Workers Static Assets）
- 定时任务（Cron Trigger）
- 队列消费者、Durable Objects、Workflows 等

**Wrangler** 是官方命令行工具，负责：

- 用 esbuild 打包 Worker 代码与 npm 依赖
- 本地模拟运行（`wrangler dev`）
- OAuth / API Token 鉴权
- 上传代码、静态资源与绑定（KV、D1、R2 等）
- 管理密钥、版本（Version）与部署（Deployment）

官方建议把 Wrangler **安装为项目本地开发依赖**，不要全局安装。这样团队版本一致，也方便按项目回滚 Wrangler。

---

## 2. 前置条件

1. 注册 [Cloudflare 账号](https://dash.cloudflare.com/sign-up/workers-and-pages)。
2. 安装 Node.js（建议使用 nvm、volta 或 mise 管理版本，避免权限问题）。
   - Wrangler 跟随 Node 的 Current / Active / Maintenance 版本。
   - 文档历史上要求过 `16.17.0+`，实际请使用当前受支持的 Node LTS。
3. 操作系统：macOS 13.5+、Windows 11，或带 glibc 2.35+ 的 Linux。

---

## 3. 安装 Wrangler

在项目目录安装为开发依赖：

```bash
npm i -D wrangler@latest
```

查看版本：

```bash
npx wrangler --version
# 或
npx wrangler -v
```

更新同样执行：

```bash
npm i -D wrangler@latest
```

日常通过 `npx` 调用，或在 `package.json` 中写脚本：

```json
{
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  }
}
```

之后即可：

```bash
npm run dev
npm run deploy
```

> 其他包管理器同样适用，例如 `pnpm add -D wrangler`、`yarn add -D wrangler`，运行时用 `pnpm exec wrangler` 或 `yarn wrangler`。

---

## 4. 登录与鉴权

### 4.1 本地交互登录（推荐个人开发）

第一次执行 `wrangler dev` 或 `wrangler deploy` 时，通常会打开浏览器完成 OAuth。也可显式登录：

```bash
npx wrangler login
npx wrangler whoami
```

`whoami` 成功时会打印账号邮箱和 `account_id`，后者可写入项目配置或环境变量。

### 4.2 API Token（CI / 无浏览器环境）

在 Cloudflare 控制台 **Overview → Get your API token → Create token**，使用模板 **Edit Cloudflare Workers**。

```bash
export CLOUDFLARE_API_TOKEN="你的token"
export CLOUDFLARE_ACCOUNT_ID="你的account_id"
```

也可用交互命令写入本机凭据：

```bash
npx wrangler config
```

旧的 Email + Global API Key 组合仍可用，但不推荐作为默认方案。

### 4.3 多账号 / 多目录 Profile

同一台机器要切换多个 Cloudflare 账号时，可使用 Authentication profiles：

```bash
npx wrangler auth create work
npx wrangler auth activate work ~/projects/work
npx wrangler deploy --profile staging
```

Profile 绑定到目录及其子目录。配置里的 `account_id` 可作为保险，避免发到错误账号。

---

## 5. 准备项目

### 5.1 全新项目：C3 脚手架（最稳）

```bash
npm create cloudflare@latest -- my-first-worker
cd my-first-worker
```

向导建议选择：

| 问题 | 建议 |
|---|---|
| What would you like to start with? | Hello World example |
| Which template? | Worker only（纯 Worker）或 Static site / 框架模板 |
| Language | JavaScript 或 TypeScript |
| Use git? | Yes |
| Deploy now? | **No**（先改代码再发） |

C3 通常会生成：

- `wrangler.jsonc`：Wrangler 配置
- `src/index.js` 或 `src/index.ts`：入口
- `package.json`、锁文件、本地 `node_modules`（含 wrangler）

入口应为 **ES Module** 格式：

```js
export default {
  async fetch(request, env, ctx) {
    return new Response("Hello Worker!");
  },
};
```

说明：

- `fetch` 在收到 HTTP 请求时调用，必须返回 `Response` 或 Promise\<Response\>。
- `env` 是绑定对象（KV、D1、R2、secrets、vars）。
- `ctx` 是执行上下文（如 `waitUntil`）。
- 定时任务可再导出 `scheduled` handler。

从已有 Git 仓库模板创建：

```bash
npm create cloudflare@latest -- --template user/repo
```

模板至少需要 `package.json`、`wrangler.jsonc`，以及配置中 `main` 指向的脚本。

### 5.2 已有前端 / 框架项目

在没有 Wrangler 配置文件的目录直接运行：

```bash
npx wrangler deploy
```

较新的 Wrangler（约 4.68+）会：

1. 检测框架
2. 提示确认
3. 安装必要适配器
4. 生成 `wrangler.jsonc`
5. 部署

只生成配置、不发布：

```bash
npx wrangler setup
npx wrangler setup --dry-run
```

CI 或非交互环境跳过确认：

```bash
npx wrangler deploy --yes
```

---

## 6. 配置文件（发布的核心）

把 Wrangler 配置当作部署的**真相来源**。常见文件名：

- `wrangler.jsonc`（推荐，带注释和 `$schema`）
- `wrangler.json`
- `wrangler.toml`

### 6.1 最小配置

```jsonc
{
  "$schema": "./node_modules/wrangler/config-schema.json",
  "name": "my-worker",
  "main": "src/index.js",
  "compatibility_date": "2026-09-20"
}
```

TOML 等价写法：

```toml
"$schema" = "./node_modules/wrangler/config-schema.json"
name = "my-worker"
main = "src/index.js"
compatibility_date = "2026-09-20"
```

### 6.2 关键字段

| 字段 | 是否必填 | 说明 |
|---|---|---|
| `name` | 是 | Worker 名称。仅字母数字和 `-`，不要用 `_`。workers.dev 下长度建议 ≤ 63 |
| `main` | 是 | 入口文件路径，如 `./src/index.ts` |
| `compatibility_date` | 是 | `yyyy-mm-dd`，锁定 Workers 运行时行为，建议设为当天 |
| `compatibility_flags` | 否 | 开启即将到来的运行时特性，如 `nodejs_compat` |
| `account_id` | 否 | 也可用环境变量 `CLOUDFLARE_ACCOUNT_ID` |
| `workers_dev` | 否 | 是否发布到 `*.workers.dev`，默认 `true` |
| `preview_urls` | 否 | 是否启用 Preview URL，默认跟随 `workers_dev` |
| `route` / `routes` | 否 | 自定义域名或 zone 路由 |
| `vars` | 否 | 非敏感环境变量（**不会**自动继承到 named env） |
| `kv_namespaces` 等 | 否 | 资源绑定，named env 需单独声明 |
| `assets` | 否 | 静态资源目录 |
| `triggers.crons` | 否 | Cron 触发器 |
| `observability` | 否 | 可观测性 |
| `env.<name>` | 否 | 多环境覆盖 |

`name` 规则：不要用下划线；若走 `*.workers.dev`，不要以 `-` 开头或结尾。

### 6.3 带路由、KV 与 staging 的完整示例

```jsonc
{
  "$schema": "./node_modules/wrangler/config-schema.json",
  "name": "my-worker",
  "main": "src/index.js",
  "compatibility_date": "2026-09-20",
  "workers_dev": false,
  "route": {
    "pattern": "example.org/*",
    "zone_name": "example.org"
  },
  "kv_namespaces": [
    {
      "binding": "MY_KV",
      "id": "<KV_ID>"
    }
  ],
  "vars": {
    "ENVIRONMENT": "production"
  },
  "env": {
    "staging": {
      "name": "my-worker-staging",
      "route": {
        "pattern": "staging.example.org/*",
        "zone_name": "example.org"
      },
      "kv_namespaces": [
        {
          "binding": "MY_KV",
          "id": "<STAGING_KV_ID>"
        }
      ],
      "vars": {
        "ENVIRONMENT": "staging"
      }
    }
  }
}
```

部署指定环境：

```bash
npx wrangler deploy --env staging
# 等价
CLOUDFLARE_ENV=staging npx wrangler deploy
```

注意：`vars`、KV、D1、R2 等绑定是 **non-inheritable**，named environment 必须自己写一份，不会从顶层自动继承。

### 6.4 静态资源 / SPA

```jsonc
{
  "name": "my-spa",
  "main": "src/index.js",
  "compatibility_date": "2026-09-20",
  "assets": {
    "directory": "./dist",
    "binding": "ASSETS",
    "not_found_handling": "single-page-application"
  }
}
```

部署时 Wrangler 会把 `directory` 中的文件一并上传。Worker 内可通过 `ASSETS` binding 读取或回退到静态文件。纯静态站也可以不写 `main`，只配 `assets`。

### 6.5 自动创建资源（Beta）

部分资源（KV、R2、D1、Queues 等）可以只写 binding、不写 ID：

```jsonc
{
  "kv_namespaces": [
    { "binding": "MY_KV_NAMESPACE" }
  ]
}
```

- `wrangler dev`：本地创建可持久化的模拟资源
- `wrangler deploy`：在账号中创建真实资源，并把 ID 写回配置文件

从控制台 / Git 部署且仓库里没有 ID 时，资源仍会创建，但 ID 可能只出现在控制台。

---

## 7. 本地开发

```bash
npx wrangler dev
```

默认监听 `http://localhost:8787`。会尽量模拟 KV、D1、R2、Durable Objects 等绑定。保存代码后刷新浏览器即可。

没有图形界面或不便打开浏览器时，参考官方 Authentication 文档使用 Token 登录。

查看打包结果、不实际上传：

```bash
npx wrangler deploy --dry-run --outdir dist
```

已有构建产物、不希望 Wrangler 再 bundle：

```bash
npx wrangler deploy --no-bundle
```

默认打包器是 **esbuild**。文本、HTML、SQL、二进制、Wasm 等可通过模块规则以特定类型导入。自定义构建可在配置的 `build` 字段中声明。

---

## 8. 发布到线上

### 8.1 默认：上传并立即切 100% 流量

```bash
npx wrangler deploy
```

这一步会：

1. 按配置打包 Worker（以及 assets）
2. 创建新的 **Version**（代码与配置快照）
3. 立即创建 **Deployment**，将 100% 流量切到该版本

若尚未配置子域或自定义域，CLI 会提示创建 `*.workers.dev`。发布成功后访问：

```text
https://<worker名>.<你的子域>.workers.dev
```

首次开通 `*.workers.dev` 时偶发 **HTTP 523**，等待一两分钟通常会恢复。

### 8.2 先上传版本，再决定何时上线

适合审批、错峰、灰度发布。

```bash
# 只上传新版本，不切换线上流量
npx wrangler versions upload

# 交互选择版本并部署；可将流量百分比设为小于 100% 做灰度
npx wrangler versions deploy
```

约束：

- **全新 Worker 第一次必须用 `wrangler deploy`（或 C3）**，不能一上来就 `versions upload`。
- Service Worker 旧语法不支持 `versions upload`，请使用 Module 语法（`export default { fetch }`）。

控制台等价操作：

1. **Workers & Pages** → 选择 Worker → **Edit code**
2. Deploy 按钮旁的下拉 → **Save**（只保存版本）
3. **Deployments** 标签中选择版本并切流量

回滚：

```bash
npx wrangler rollback
```

### 8.3 Version 与 Deployment 的区别

| 概念 | 含义 |
|---|---|
| Version | 一次代码/配置快照，可以存在但不接流量 |
| Deployment | 决定当前哪些 Version 在服务流量（100% 或按百分比拆分） |

`wrangler deploy` 默认把两步绑在一起。拆开后可以做渐进发布（gradual deployment）。

---

## 9. 密钥、域名与路由

### 9.1 Secrets（不要写进配置文件或 git）

```bash
echo "真实值" | npx wrangler secret put API_KEY
npx wrangler secret put API_KEY --env production
npx wrangler secret list
npx wrangler secret delete API_KEY
```

代码中通过 `env.API_KEY` 读取。

对比：

| 类型 | 存放位置 | 用途 |
|---|---|---|
| `vars` | 配置文件 | 非敏感开关、公开 URL、环境名 |
| `secret` | Cloudflare 侧加密存储 | Token、私钥、数据库密码 |

可在配置中用 `secrets.required` 声明部署前必须存在的密钥名，便于校验和类型生成。

### 9.2 自定义域名与路由

配置示例：

```jsonc
"route": {
  "pattern": "example.org/*",
  "zone_name": "example.org"
}
```

或多条 `routes`。也可在控制台给 Worker 绑定 **Custom Domain**。

权限注意：

- 更新已有 Worker 代码：对该 Worker 的 **Editor** 即可
- 部署时新增/修改 Route 或 Custom Domain：还需要对应 zone 的 **Workers Routes Write**
- **新建**一个尚不存在的 Worker：通常需要产品级 **Admin**

---

## 10. 常用命令速查

```bash
# 账号
npx wrangler login
npx wrangler logout
npx wrangler whoami
npx wrangler config

# 开发与发布
npx wrangler dev
npx wrangler deploy
npx wrangler deploy --env production
npx wrangler deploy --dry-run --outdir dist
npx wrangler deploy --no-bundle
npx wrangler deploy --yes

# 版本
npx wrangler versions upload
npx wrangler versions deploy
npx wrangler rollback

# 密钥与排障
npx wrangler secret put NAME
npx wrangler secret list
npx wrangler tail
```

资源子命令（KV / D1 / R2 等）按产品文档使用，例如创建命名空间后再把 ID 填回配置。

建议在项目里固定 Wrangler 调用方式：

```text
npx wrangler <COMMAND> [OPTIONS]
```

---

## 11. 生产实践：多环境与 CI/CD

### 11.1 多环境建议

- 使用 `env.staging`、`env.production`（或顶层作为生产）
- 不同环境使用不同的 `name`、路由、KV/D1/R2 ID、secrets
- 不要让预发和线上共用同一套绑定

### 11.2 Workers Builds（官方 Git CI）

将仓库推到 GitHub 或 GitLab，在 Workers 控制台连接仓库：

| 分支 | 常见部署命令 | 含义 |
|---|---|---|
| 生产分支 | `npx wrangler deploy` | 构建并切生产流量 |
| 其他分支 | `npx wrangler versions upload` | 只上传版本 / 预览，不切生产 |

构建配置在 Worker 的 **Settings → Builds**。若 `package.json` 未定义 `deploy` script，Cloudflare 默认使用 `npx wrangler deploy`。

### 11.3 GitHub Actions 示例

```yaml
name: Deploy Worker

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: npm
      - run: npm ci
      - run: npx wrangler deploy --env production
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CF_ACCOUNT_ID }}
```

Token 权限与控制台角色一致：发已有 Worker 用 Editor；改路由还要 zone 写权限。

### 11.4 可观测性

```bash
npx wrangler tail
```

配置中可开启：

```jsonc
"observability": {
  "enabled": true
}
```

控制台可查看调用次数、异常、Deployment 历史。需要的话可打开 `logpush`。

---

## 12. 从本地 SQLite + Drizzle 迁移到 Cloudflare D1

本地用 `better-sqlite3` / `libsql` + Drizzle，上 Workers 后应改用 **Cloudflare D1**。D1 是边缘托管的 SQLite，SQL 方言接近 SQLite 3，但**不能把 `.sqlite` 文件直接挂到 Worker 里**，也不能在边缘使用 Node 的文件系统驱动。

迁移分两层，不要混为一谈：

| 层次 | 做什么 | 工具 |
|---|---|---|
| **Schema 迁移** | 把表结构从 Drizzle schema 同步到 D1 | `drizzle-kit generate` + `wrangler d1 migrations apply` |
| **数据迁移** | 把本地 SQLite 里已有行导入 D1 | `sqlite3 .dump` + `wrangler d1 execute --file` |

推荐生产路径：**Drizzle 只负责生成 SQL，真正 apply 一律走 Wrangler D1 迁移系统**。这样本地 D1、远程 D1、CI 用同一套文件，状态记在 D1 的 `d1_migrations` 表里。

### 12.1 为什么不能继续用本地 SQLite 驱动

Workers 运行时没有随意读写磁盘的 Node `fs`，也跑不了 `better-sqlite3` 这种原生 addon。

| 环境 | 连接方式 | Drizzle 入口 |
|---|---|---|
| 本地 Node 脚本 / 旧服务 | 文件路径，如 `./data.db` | `drizzle-orm/better-sqlite3` 或 `drizzle-orm/libsql` |
| Worker / Pages | `env.DB`（D1 binding） | `drizzle-orm/d1` |
| 本机调试 Worker | Wrangler 模拟的本地 D1 | 同样是 `drizzle-orm/d1` + `env.DB` |
| Drizzle Kit 远程操作（push / studio） | D1 HTTP API | `driver: "d1-http"` |

Schema 文件（`sqliteTable` 等）通常可以原样保留；要改的是 **client 工厂** 和 **迁移落地方式**。

### 12.2 安装依赖

```bash
npm i drizzle-orm
npm i -D drizzle-kit wrangler
# 旧的 better-sqlite3 仅留给一次性导数据脚本，Worker 运行时不要依赖它
```

### 12.3 创建 D1 并写入 Wrangler 配置

```bash
npx wrangler d1 create my-app-db
```

把输出的 `database_id` 写进 `wrangler.jsonc`。Drizzle 默认会把每次迁移写成子目录（例如 `drizzle/0001_init/migration.sql`），必须同时配置 `migrations_dir` 和 `migrations_pattern`，否则 `wrangler d1 migrations apply` 找不到文件：

```jsonc
{
  "name": "my-app",
  "main": "src/index.ts",
  "compatibility_date": "2026-09-20",
  "compatibility_flags": ["nodejs_compat"],
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "my-app-db",
      "database_id": "<从 wrangler d1 create 复制>",
      "preview_database_id": "local-preview-db",
      "migrations_dir": "drizzle",
      "migrations_pattern": "drizzle/*/migration.sql"
    }
  ]
}
```

说明：

- `binding` 决定代码里是 `env.DB`。
- `migrations_pattern` 是相对 Wrangler 配置文件的 glob；`*` 匹配一层目录。若目录更深，用 `drizzle/**/*.sql`。
- 配置了 `migrations_pattern` 时必须同时写 `migrations_dir`。
- `wrangler d1 migrations create` 只会在目录顶层写空 `.sql`，**嵌套布局请用 `drizzle-kit generate`，不要用 wrangler 建迁移文件**。
- named env（staging / production）要各自声明完整的 `d1_databases`（含不同的 `database_id`），绑定不会从顶层继承。

### 12.4 Drizzle schema 保持 SQLite 方言

```ts
// src/db/schema.ts
import { sql } from "drizzle-orm";
import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const users = sqliteTable(
  "users",
  {
    id: text("id").primaryKey(),
    email: text("email").notNull().unique(),
    name: text("name").notNull(),
    createdAt: integer("created_at", { mode: "timestamp" })
      .notNull()
      .default(sql`(unixepoch())`),
  },
  (table) => ({
    emailIdx: index("users_email_idx").on(table.email),
  }),
);
```

不要改成 `pgTable` / `mysqlTable`。D1 是 SQLite。

### 12.5 drizzle.config.ts

生成 SQL、不直接连远程库时，最少配置即可：

```ts
// drizzle.config.ts
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
});
```

若要用 `drizzle-kit push` / `migrate` / `studio` 走 D1 HTTP API（不经过 Wrangler 迁移表），再加上：

```ts
import "dotenv/config";
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  driver: "d1-http",
  dbCredentials: {
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID!,
    databaseId: process.env.CLOUDFLARE_DATABASE_ID!,
    token: process.env.CLOUDFLARE_D1_TOKEN!,
  },
});
```

Token 需要 D1 编辑权限。`accountId` 在 Workers Overview 右侧；`databaseId` 在 D1 详情页。

> 生产更稳妥的做法仍是：**Kit 只 `generate`，Wrangler 负责 `apply`**。否则会出现两套迁移账本（`__drizzle_migrations` 与 `d1_migrations`）互相看不见。

### 12.6 在 Worker 里换驱动

旧代码（本地文件）：

```ts
import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";

const sqlite = new Database("./data.db");
export const db = drizzle(sqlite);
```

新代码（D1 binding）：

```ts
import { drizzle } from "drizzle-orm/d1";
import * as schema from "./db/schema";

export interface Env {
  DB: D1Database;
}

export default {
  async fetch(request: Request, env: Env) {
    const db = drizzle(env.DB, { schema });
    const rows = await db.select().from(schema.users).all();
    return Response.json(rows);
  },
};
```

查询 API 与 schema 基本不变，变的是实例化方式。注意 D1 上的 Drizzle 是异步的，不要再写同步的 `.get()` / `.all()`（better-sqlite3 风格）。

### 12.7 Schema 迁移工作流（推荐）

```bash
# 1. 根据 schema.ts 的差异生成 SQL（提交到 git）
npx drizzle-kit generate

# 2. 先打到 Wrangler 本地 D1，配合 wrangler dev
npx wrangler d1 migrations list my-app-db --local
npx wrangler d1 migrations apply my-app-db --local

# 3. 确认无误后再打远程
npx wrangler d1 migrations list my-app-db --remote
npx wrangler d1 migrations apply my-app-db --remote

# 指定环境
npx wrangler d1 migrations apply my-app-db --remote --env production
```

`apply` 会按顺序执行未应用的文件，并在库内 `d1_migrations` 记账。失败的那一条会回滚，之前成功的保留。交互环境会确认；CI 非交互会跳过确认但仍会打备份。

`package.json` 可写成：

```json
{
  "scripts": {
    "db:generate": "drizzle-kit generate",
    "db:migrate:local": "wrangler d1 migrations apply my-app-db --local",
    "db:migrate:remote": "wrangler d1 migrations apply my-app-db --remote",
    "db:list": "wrangler d1 migrations list my-app-db"
  }
}
```

### 12.8 已有数据：从本地 `.sqlite` 导入 D1

不能把 `.db` / `.sqlite3` 文件直接丢给 D1，要先导出 SQL，清洗后再执行。

**1. 导出**

```bash
sqlite3 ./data.db .dump > dump.sql
```

**2. 清洗 dump.sql**

- 删除 `BEGIN TRANSACTION;` 与 `COMMIT;`（否则会报 “cannot start a transaction within a transaction”）。
- 若有 Cloudflare 内部表，删掉：

```sql
CREATE TABLE _cf_KV (
  key TEXT PRIMARY KEY,
  value BLOB
) WITHOUT ROWID;
```

- 也可视情况去掉 `sqlite_sequence` 等不需要的内部对象。
- 超大 `INSERT ... VALUES (...), (...), ...` 容易触发 D1「Statement too long」。按大约每批 100～250 行拆开。
- 有外键时保证 `CREATE TABLE` 顺序正确；必要时在文件开头加：

```sql
PRAGMA defer_foreign_keys = true;
```

**3. 导入**

```bash
# 先导入本地 D1 验证
npx wrangler d1 execute my-app-db --local --file=./dump.sql

# 再导入远程
npx wrangler d1 execute my-app-db --remote --file=./dump.sql
```

**4. 核对**

```bash
npx wrangler d1 execute my-app-db --remote --command \
  "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name;"

npx wrangler d1 execute my-app-db --remote --command \
  "SELECT COUNT(*) AS n FROM users;"
```

**5. 导入后与 Drizzle 迁移账本对齐**

如果 dump 已经包含完整表结构，不要再对空库跑一遍会 `CREATE TABLE` 冲突的初始迁移。两种处理方式：

- **先导入数据，再把已体现在 dump 里的迁移标记为已应用**（按 D1 文档维护 `d1_migrations`，或让后续迁移从「下一版」开始编号）。
- **先对空 D1 `migrations apply` 建表，再只导入数据**（dump 里删掉所有 `CREATE TABLE` / 索引，只留 `INSERT`）。第二种更可控，推荐有 Drizzle 迁移历史的项目使用。

从 D1 再导出备份：

```bash
npx wrangler d1 export my-app-db --remote --output=./backup.sql
npx wrangler d1 export my-app-db --remote --no-data --output=./schema-only.sql
npx wrangler d1 export my-app-db --remote --table=users --output=./users.sql
```

FTS5 等虚拟表不能直接 export，需先删虚拟表再导出，导入后重建。

### 12.9 推荐迁移顺序（现有应用）

1. 确认 schema 已是 `drizzle-orm/sqlite-core`，查询尽量不依赖 SQLite 专有且 D1 不支持的扩展。
2. 在仓库里固定 `drizzle-kit generate` 产出，并配置 `migrations_dir` + `migrations_pattern`。
3. `wrangler d1 create`，写入各环境的 `database_id`。
4. 把 Worker 入口从 `better-sqlite3` 换成 `drizzle(env.DB)`。
5. `migrations apply --local`，用 `wrangler dev` 跑通读写。
6. 用清洗过的 dump 把业务数据导入本地 D1，核对行数与抽样数据。
7. `migrations apply --remote`（空库建表）或按上一节对齐账本后导入数据。
8. 小流量验证后再切域名。需要回滚时可结合 D1 Time Travel（约 30 天分钟级恢复）。

### 12.10 兼容性与坑

- **驱动**：Worker 内只用 `drizzle-orm/d1`。`better-sqlite3`、`sqlite3`、`libsql` 文件 URL 都不能作为线上 binding。
- **同步 vs 异步**：D1 查询都是 Promise，记得 `await`。
- **两套迁移系统**：不要既 `drizzle-kit migrate` 又 `wrangler d1 migrations apply` 打同一套库，账本表不同。
- **嵌套 SQL 路径**：未配 `migrations_pattern` 时 Wrangler 只扫 `migrations_dir/*.sql`，看不到 `0001_xxx/migration.sql`。
- **SQL 限制**：语句长度有上限；避免巨型单条 INSERT。部分 SQLite 扩展、部分 ATTACH、任意文件函数在 D1 不可用。
- **整数精度**：经 JS 绑定时要注意超过 53 bit 的整数精度。
- **外键**：导入顺序不当会失败，用 `PRAGMA defer_foreign_keys`。
- **多环境数据隔离**：staging 与 production 必须是两套 D1，不要把生产 dump 误打进预发后当正式库。
- **首次 apply 与已有表冲突**：对「已经用 dump 建好表」的库再跑初始 `CREATE TABLE` 会报 already exists，先对齐迁移记录。

### 12.11 其它 ORM 的同一思路

Prisma 等也是「工具生成 SQL → `wrangler d1 migrations apply`」，例如用 `prisma migrate diff` 写出 `.sql` 再交给 Wrangler。原则相同：D1 的权威迁移执行器是 Wrangler，不是 ORM 自己的 migrate 运行时。

---

## 13. 常见问题与坑

1. **入口不是 Module 格式**  
   必须 `export default { fetch }`（或带 `scheduled` 等）。旧 Service Worker 语法在 `versions upload` 场景不受支持。

2. **`compatibility_date` 过旧**  
   新运行时 API 不可用。发布前把它更新到接近当天的日期，并评估 breaking change。

3. **把密钥写进 `vars` 或提交进 git**  
   敏感值只用 `wrangler secret put`。

4. **named env 漏写绑定**  
   误以为 staging 会继承顶层 KV / vars。不会。每个环境单独声明。

5. **第一次就用 `versions upload`**  
   新 Worker 首次创建必须 `wrangler deploy` 或 C3。

6. **自定义域名 zone 不在当前账号**  
   检查 `account_id` / `CLOUDFLARE_ACCOUNT_ID` 是否对应那个 zone。

7. **静态站只发了脚本、没发前端资源**  
   需要配置 `assets.directory`，并确保构建产物已生成在该目录。

8. **首次 `*.workers.dev` 返回 523**  
   等待约一分钟再试，DNS / 路由传播延迟。

9. **CI 里权限不足**  
   创建 Worker 与改 Route 所需权限高于“只更新代码”。按官方 Workers roles 给 Token 授权。

10. **全局安装的 Wrangler 版本和项目不一致**  
    用项目本地 `npx wrangler`，并锁定 `package.json` 中的版本。

11. **Worker 里继续 `new Database('./data.db')` 或 `better-sqlite3`**  
    边缘没有可用的本地 SQLite 文件。改为 D1 binding + `drizzle-orm/d1`。详见第 12 节。

12. **`wrangler d1 migrations apply` 提示没有迁移，但 drizzle 目录里有 SQL**  
    Drizzle 常用 `drizzle/0001_xxx/migration.sql` 嵌套布局。要同时配置 `migrations_dir` 与 `migrations_pattern`。

13. **本地数据导入 D1 后表已存在，再 apply 初始迁移失败**  
    dump 已含 `CREATE TABLE` 时不要重复跑建表迁移，先对齐 `d1_migrations` 或改为「先 apply 再只导入 INSERT」。

14. **dump 执行报 transaction / statement too long**  
    去掉 `BEGIN`/`COMMIT`；拆分大 INSERT。

---

## 14. 最短路径（Hello World）

```bash
# 1. 脚手架
npm create cloudflare@latest -- my-app
cd my-app

# 2. 登录
npx wrangler login

# 3. 本地预览
npx wrangler dev
# 打开 http://localhost:8787

# 4. 发布
npx wrangler deploy
# 访问 https://<name>.<subdomain>.workers.dev
```

按应用类型可替换第 1 步模板，例如静态站、React、或已有仓库的 `--template`。

---

## 15. 参考链接

- [Get started - CLI](https://developers.cloudflare.com/workers/get-started/guide/)
- [Install / Update Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/)
- [Wrangler Commands](https://developers.cloudflare.com/workers/wrangler/commands/)
- [Wrangler Configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)
- [Environments](https://developers.cloudflare.com/workers/wrangler/environments/)
- [Authentication](https://developers.cloudflare.com/workers/wrangler/)
- [Authentication profiles](https://developers.cloudflare.com/workers/wrangler/profiles/)
- [Versions & Deployments](https://developers.cloudflare.com/workers/configuration/versions-and-deployments/)
- [Deployment management](https://developers.cloudflare.com/workers/versions-and-deployments/deployment-management/)
- [Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Deploy an existing project（自动配置）](https://developers.cloudflare.com/workers/framework-guides/automatic-configuration/)
- [Workers roles and permissions](https://developers.cloudflare.com/workers/authorization/workers/)
- [Workers Builds / CI](https://developers.cloudflare.com/workers/ci-cd/builds/)
- [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
- [D1 Migrations](https://developers.cloudflare.com/d1/reference/migrations/)
- [D1 Import and export data](https://developers.cloudflare.com/d1/best-practices/import-export-data/)
- [D1 Local development](https://developers.cloudflare.com/d1/best-practices/local-development/)
- [D1 Wrangler commands](https://developers.cloudflare.com/d1/wrangler-commands/)
- [Drizzle + D1（新项目）](https://orm.drizzle.team/docs/get-started/d1-new)
- [Drizzle + D1（已有项目）](https://orm.drizzle.team/docs/get-started/d1-existing)
- [Drizzle Kit D1 HTTP](https://orm.drizzle.team/docs/guides/d1-http-with-drizzle-kit)

---

## 附录 A：package.json 推荐片段

```json
{
  "name": "my-worker",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "deploy:staging": "wrangler deploy --env staging",
    "versions:upload": "wrangler versions upload",
    "tail": "wrangler tail",
    "db:generate": "drizzle-kit generate",
    "db:migrate:local": "wrangler d1 migrations apply my-app-db --local",
    "db:migrate:remote": "wrangler d1 migrations apply my-app-db --remote",
    "db:list": "wrangler d1 migrations list my-app-db"
  },
  "devDependencies": {
    "wrangler": "^4"
  }
}
```

版本号请按你锁定的实际 Wrangler 大版本调整。

## 附录 B：权限对照（Wrangler）

| 操作 | 命令 | 最低角色（示意） |
|---|---|---|
| 看实时日志 | `wrangler tail` | 该 Worker 的 Metadata Read-Only |
| 部署已有 Worker | `wrangler deploy` | 该 Worker 的 Editor |
| 部署时改 Route / 自定义域 | `wrangler deploy` | Editor + 对应 zone 的 Workers Routes Write |
| 创建新 Worker | 对尚不存在的 name 执行 `deploy` | 产品级 Admin |
| 上传版本 | `wrangler versions upload` | Editor |
| 发布已上传版本 | `wrangler versions deploy` | Editor |
| 回滚 | `wrangler rollback` | Editor |
| 管理密钥 | `wrangler secret put/delete` | Editor |

具体以 Cloudflare 当前 Workers roles 文档为准。

---

*文档整理自 Cloudflare Workers / Wrangler 官方文档公开说明，命令与字段随 SDK 版本可能调整。发布前请对照官网最新页核对 `compatibility_date` 与命令帮助（`npx wrangler --help`）。*
