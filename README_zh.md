# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/) [![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE) [![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest) [![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

一款 macOS 菜单栏应用，实时监控 ChatGPT Codex 的使用额度。

<p align="center">
  <img src="https://raw.githubusercontent.com/HanryYu/codex_multi_monitor/main/assets/codexmonitor-screenshot.png" alt="CodexMonitor 截图" width="420">
</p>

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [安装方式](#安装方式)
- [获取 API Token](#获取-api-token)
- [使用说明](#使用说明)
- [状态颜色](#状态颜色)
- [更新提醒](#更新提醒)
- [自动化与 CI/CD](#自动化与-cicd)
- [常见问题](#常见问题)
- [开源协议](#开源协议)

## 功能特性

- **实时监控** — 从 macOS 菜单栏直接追踪 Codex 使用情况
- **多账户支持** — 监控多个 Codex 账户，轻松切换
- **用量可视化** — 带颜色编码的状态指标显示额度使用情况
- **限额提醒** — 5 小时或周额度用尽时显示视觉遮罩和重置倒计时
- **智能通知** — 额度过低或账户恢复时收到通知
- **自动账户同步** — 启动时自动检测本地 Codex 账户并添加
- **多语言** — English、中文、日本語
- **版本更新提醒** — GitHub 有新版本时自动提醒

## 系统要求

- macOS 15.0+
- Xcode 16+（从源码构建时）
- Swift 6.0+

## 安装方式

### 下载 DMG（推荐）

1. 前往 [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
2. 下载 `CodexMonitor-x.x.x.dmg` 文件
3. 打开 DMG，将 **CodexMonitor** 拖入 **Applications** 文件夹
4. 启动 CodexMonitor — 它会出现在菜单栏中

> **注意：** 应用使用 Apple Development 证书签名。首次启动时 macOS 可能显示安全警告，右键点击应用选择"打开"即可绕过。

### 从源码构建

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
make install
```

或手动：

```bash
swift build -c release
cp -f .build/release/CodexMonitor /Applications/CodexMonitor.app/Contents/MacOS/
open /Applications/CodexMonitor.app
```

## 获取 API Token

1. 访问 [chatgpt.com/codex](https://chatgpt.com/codex)
2. 使用 ChatGPT 账户登录
3. 打开开发者工具 → **Network** 标签
4. 查找发往 `ab.chatgpt.com` 或 `chatgpt.com` 的 API 请求
5. 找到 **Authorization** 头 — 其中包含一个 UUID 格式的 token（如 `3f8c2b1a-...`）
6. 复制此 token

> **提示：** 如果你已经在本地使用过 Codex，应用可以在首次启动时自动检测你的账户。

## 使用说明

1. 从应用程序文件夹启动 **CodexMonitor**
2. 点击菜单栏图标查看账户
3. 点击 **+** 添加账户，粘贴 API token
4. 应用每 30 秒自动刷新数据

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘ + N` | 添加新账户 |
| `⌘ + ,` | 打开偏好设置 |
| `⌘ + Q` | 退出 |

### 账户 Token 检测

首次启动时，应用会搜索 `~/Library/Application Support/codex/` 中的现有 Codex 账户，并提示你导入 — 无需手动复制 token。

## 状态颜色

| 颜色 | 含义 |
|------|------|
| 🟢 绿色 | 剩余额度 > 50% |
| 🟡 黄色 | 剩余额度 20-50% |
| 🔴 红色 | 剩余额度 < 20% |

当达到限额（5 小时或周限额）时，状态区域会显示 "Limit Reached" 遮罩和预计重置时间。

## 更新提醒

CodexMonitor 会自动检查 GitHub Releases 上的新版本。有新版本时，菜单栏会显示通知，你可以直接打开 release 页面下载更新。

## 自动化与 CI/CD

CodexMonitor 旨在与 OpenAI 的 Codex GitHub 机器人无缝协作，用于自动化代码审查和 PR 管理。

### 工作原理

1. **Codex 机器人** 通过 `codex.yaml` 工作流在 GitHub 上运行
2. **CodexMonitor** 追踪所有账户的 API 使用情况和额度
3. 当一个账户达到限额时，切换到另一个账户以保持 Codex 持续运行

### 为你的仓库配置

在你的仓库中添加 `.github/workflows/codex.yaml`：

```yaml
name: Codex

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  codex:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '/codex')) ||
      (github.event_name == 'pull_request')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: openai/codex-action@v1
        with:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

## 常见问题

**菜单栏图标不显示？**
- 打开活动监视器检查 — 应用可能已在运行。强制退出后重新启动。

**首次启动时"未找到账户"？**
- 确保你已经在本地使用过 Codex 至少一次，或通过 **+** 按钮手动添加 token。

**DMG 打不开 / "未识别的开发者"？**
- 右键 → 打开，或前往 系统设置 → 隐私与安全性 → 仍要打开。

## 开源协议

[GPLv3](LICENSE) — © 2025 Henry Yu
