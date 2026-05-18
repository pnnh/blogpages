# 希望的光波 - 个人技术博客

基于 [Jekyll](https://jekyllrb.com/) 构建的静态博客，使用 [Chirpy](https://github.com/cotes2333/jekyll-theme-chirpy) 主题，部署于 Cloudflare Workers。

## 技术栈

| 组件 | 说明 |
|------|------|
| Jekyll 4.4 | 静态站点生成器 |
| jekyll-theme-chirpy 7.x | 博客主题，支持暗色/亮色模式、TOC、分类、标签 |
| Cloudflare Workers + Wrangler | 站点托管与部署 |
| Rouge | 代码语法高亮 |

## 支持的文档格式

| 格式 | 扩展名 | 实现方式 |
|------|--------|----------|
| Markdown | `.md` | Jekyll 内置（kramdown + GFM） |
| AsciiDoc | `.adoc`, `.asciidoc` | [jekyll-asciidoc](https://github.com/asciidoctor/jekyll-asciidoc) 插件 |
| reStructuredText | `.rst` | 自定义插件（`_plugins/rst_converter.rb`），依赖系统安装的 [pandoc](https://pandoc.org/) |

### RST 支持前提

需在系统中安装 pandoc（macOS 使用 Homebrew）：

```bash
brew install pandoc
```

## 目录结构

```
├── _config.yml          # Jekyll 配置（主题、插件、分页等）
├── _posts/              # 博客文章，按技术分类
│   ├── CPlus/           # C/C++ 相关
│   ├── Database/        # 数据库
│   ├── Devserver/       # 服务端库与工具
│   ├── Docker/          # Docker
│   ├── Dotnet/          # .NET / C#
│   ├── Flutter/         # Flutter
│   ├── Git/             # Git
│   ├── Java/            # Java
│   ├── Kubernetes/      # Kubernetes / K8s
│   ├── Linux/           # Linux
│   ├── LLM/             # 大语言模型
│   ├── Macos/           # macOS
│   ├── Nodejs/          # Node.js
│   ├── Python/          # Python
│   ├── Qt/              # Qt
│   ├── Rust/            # Rust
│   ├── Swift/           # Swift / iOS
│   ├── Ubuntu/          # Ubuntu
│   ├── VScode/          # VS Code
│   ├── Windows/         # Windows
│   └── 其它/            # 其他主题
├── _plugins/            # 自定义 Jekyll 插件
│   ├── rst_converter.rb # reStructuredText → HTML 转换器（调用 pandoc）
│   └── posts-lastmod-hook.rb  # 文章最后修改时间（读取 git log）
├── _tabs/               # 侧边栏导航页（About、Archives、Categories、Tags）
├── assets/              # 静态资源（CSS、图片、JS 库）
├── _site/               # Jekyll 构建输出（不提交到版本库）
├── temp/                # 待处理的草稿文章
├── Gemfile              # Ruby 依赖
├── _config.yml          # Jekyll 主配置
├── wrangler.jsonc       # Cloudflare Workers 配置
└── package.json         # Node.js 脚本（wrangler 命令封装）
```

## 文章格式

文章放置于 `_posts/<分类>/` 目录，文件名格式为 `YYYY-MM-DD-slug.{md,adoc,rst}`，必须包含 YAML front matter：

```yaml
---
layout: post
title: "文章标题"
date: 2026-01-01 00:00:00 +0800
categories: [分类名]
tags: [tag1, tag2]
---
```

## 插件列表

| 插件 | 作用 |
|------|------|
| jekyll-seo-tag | 自动生成 SEO 标签 |
| jekyll-sitemap | 生成 sitemap.xml |
| jekyll-paginate | 首页分页（每页 10 篇） |
| jekyll-archives | 分类和标签归档页 |
| jekyll-asciidoc | AsciiDoc 文档格式支持 |

## 本地开发

```bash
# 安装依赖
bundle install

# 本地预览（热重载）
bundle exec jekyll serve --watch

# 生产构建
bundle exec jekyll build
```

## 部署

站点通过 Cloudflare Workers 托管：

```bash
# 构建并部署
npm run build && npm run deploy

# 或单独部署
npx wrangler deploy
```

## 许可

内容版权归作者所有，不另行声明。
