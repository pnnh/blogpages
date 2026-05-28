---
title: "Cloudflare R2 大批量图片上传实战指南：10万张图片使用 rclone 的完整经验总结"
date: 2026-05-28
categories: [Cloud, Cloudflare, R2, rclone]
tags: [大批量上传, rclone, S3, 云存储, 实践]
---

# Cloudflare R2 大批量图片上传实战指南

> 10万张图片使用 rclone 的完整经验总结

## 背景与问题

计划将约 10 万张图片上传到 Cloudflare R2 存储桶。直接使用 API 接口上传容易遇到限流问题，而网页 Dashboard 无法满足大规模需求。

**核心结论**：推荐使用 **rclone** 作为主要上传工具，它是 S3 兼容存储（如 R2）大批量文件同步/迁移的最佳选择，支持高并发、断点续传、智能跳过、智能分块等特性。

## rclone 优势与替代方案对比

- **rclone**：高并发、支持 multipart、断点续传、智能 sync/copy、跨平台。
- **AWS CLI**：稳定，但功能稍弱于 rclone。
- **原生 API/SDK**：灵活但需自行处理限流、重试、并发，开发成本高。
- **Wrangler**：适合小批量，不适合 10 万量级。

rclone 是社区处理数万至数十万文件的主流工具。

## 在 Ubuntu 上安装 rclone

### 推荐方式：官方安装脚本（安装最新版）

```bash
sudo apt update && sudo apt install -y curl
sudo -v ; curl https://rclone.org/install.sh | sudo bash
```

### 其他方式

- APT 安装（版本较旧）：
  ```bash
  sudo apt install rclone -y
  ```
- 手动安装（最新版可控）：
  ```bash
  curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
  unzip rclone-current-linux-amd64.zip
  sudo cp rclone-*-linux-amd64/rclone /usr/bin/
  sudo chmod 755 /usr/bin/rclone
  ```

验证：
```bash
rclone version
```
建议：始终使用官方脚本保持最新版本（对话中用户初始版本为 v1.60.1-DEV，明显过旧）。

## rclone 配置文件位置

默认路径：
```bash
~/.config/rclone/rclone.conf
```
- 普通用户：/home/用户名/.config/rclone/rclone.conf
- root 用户：/root/.config/rclone/rclone.conf

查看当前配置文件路径：
```bash
rclone config file
```
权限建议：
```bash
chmod 600 ~/.config/rclone/rclone.conf
```

## rclone sync 目录行为

命令示例：
```bash
rclone sync ./public/icons r2:seicons/ --transfers 32 -P
```
行为：该命令不会在 seicons/ 下额外创建 icons 目录，而是把 icons 目录里面的内容直接同步到 seicons/ 根目录。

如果想要保留 icons 层级：
```bash
rclone sync ./public/icons r2:seicons/icons/
```

测试建议：始终先使用 `--dry-run` 参数验证：
```bash
rclone sync ... --dry-run
```

## 常见错误：501 NotImplemented

错误现象：
部分文件（尤其是 SVG 小文件）上传时报 NotImplemented: Not Implemented（status code: 501）。

根本原因：Cloudflare R2 是 S3 兼容存储，但并非完全实现所有 S3 特性。rclone 默认发送的某些 Header（如 ACL、Checksum、Metadata、Tagging 等）R2 不支持。

### 优化配置（rclone.conf）

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = your_key
secret_access_key = your_secret
endpoint = https://<AccountID>.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
chunk_size = 50M
upload_concurrency = 4
disable_checksum = true
no_head = true
no_system_metadata = true
```

### 推荐命令参数

```bash
rclone copy ./public/icons r2:seicons/ \
  --transfers 16 \
  --s3-upload-concurrency 4 \
  --s3-chunk-size 50M \
  --s3-disable-checksum \
  --s3-no-check-bucket \
  --s3-no-head \
  --fast-list \
  -P --verbose
```

## copy 与 sync 的区别及选择

| 特性           | rclone copy | rclone sync | 推荐场景         |
| -------------- | ----------- | ----------- | ---------------- |
| 检查目标文件   | 是（默认）  | 是          | -                |
| 跳过相同文件   | 是          | 是          | -                |
| 删除目标多余文件 | 否         | 是          | 首次上传用 copy  |
| 支持 --no-check-dest | 是    | 否          | copy 配合使用    |

强制不检查目标（最快方式）：
```bash
rclone copy ... --no-check-dest
```

首次全量上传：推荐 `copy --no-check-dest`
后续增量更新：使用 `copy`（不加 --no-check-dest）或 `sync`

## 其他实用技巧与注意事项

- 并发控制：小文件（SVG、图标）建议 `--transfers 8~16`，避免过高并发触发限流。
- 分批上传：按子目录逐个上传，降低风险。
- 清理残留：
  ```bash
  rclone cleanup r2:seicons/
  ```
- 查看目录结构：
  ```bash
  rclone ls r2:seicons/ --dirs-only
  rclone tree r2:seicons/
  ```
- 费用考虑：R2 Class A 操作（写入）收费，减少不必要的 multipart part 和检查操作。
- 更新 rclone：定期更新以获得更好的兼容性和性能。

## 完整推荐流程

1. 更新 rclone 到最新版。
2. 配置 R2 remote（rclone config）。
3. 使用优化后的 copy 命令 + --no-check-dest 首次上传。
4. 后续更新去除 --no-check-dest 实现智能跳过。
5. 监控日志，遇到问题使用 -vv 输出详细调试信息。

## 总结

通过 rclone + 针对 R2 的参数优化，可以稳定、高效地完成 10 万张图片的上传任务。关键在于：

- 使用最新版 rclone
- 正确配置 disable_checksum、no_head 等兼容参数
- 合理选择 copy 与 --no-check-dest
- 分批测试 + 详细日志诊断

此方案综合考虑了速度、稳定性、成本和 R2 的兼容性限制，是目前处理大规模图片上传到 R2 的成熟实践。
