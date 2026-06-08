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

### Homebrew（推荐）

```bash
brew tap HanryYu/tap
brew install --cask codexmonitor
```

升级：
```bash
brew upgrade --cask codexmonitor
```

### 下载 DMG

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

### 方式 1：自动账户管理（推荐）

CodexMonitor 可以自动检测和管理你的 Codex 账户。只需启动应用 — 它会自动扫描本地认证数据、导入账户，并处理 token 刷新和去重。

> 如果你使用 [cc-switch](https://github.com/HanryYu/cc-switch) 或手动切换 token，CodexMonitor 会自动保持账户同步，无需额外操作。

### 方式 2：浏览器 Network 面板

1. 在浏览器中打开 [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) 并**登录**
2. 打开开发者工具（Mac 上按 `⌘⌥I`）→ **Network** 标签
3. 页面会自动加载使用数据 — 查找 `wham/usage` 请求
4. 点击该请求 → **Headers** → 复制 `Authorization: Bearer *** 的值
5. 将 token（不含 `Bearer ` 前缀）粘贴到 CodexMonitor

### 方式 3：本地命令提取

如果你安装了 [Codex CLI](https://github.com/openai/codex)，可以用本地命令提取 token：

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

复制输出结果并粘贴到 CodexMonitor。

## 使用说明

1. 从应用程序文件夹启动 **CodexMonitor**
2. 点击菜单栏图标查看账户
3. 启动时自动检测账户 — 或点击 **+** 手动添加
4. 应用每 30 秒自动刷新数据

## 状态颜色

| 颜色 | 含义 |
|------|------|
| 🟢 绿色 | 剩余额度 > 50% |
| 🟡 黄色 | 剩余额度 20-50% |
| 🔴 红色 | 剩余额度 < 20% |

当达到限额（5 小时或周限额）时，状态区域会显示 "Limit Reached" 遮罩和预计重置时间。

## 常见问题

**菜单栏图标不显示？**
- 打开活动监视器检查 — 应用可能已在运行。强制退出后重新启动。

**首次启动时"未找到账户"？**
- 确保你已经在本地使用过 Codex 至少一次，或通过 **+** 按钮手动添加 token。

**DMG 打不开 / "未识别的开发者"？**
- 右键 → 打开，或前往 系统设置 → 隐私与安全性 → 仍要打开。

## 开源协议

[GPLv3](LICENSE) — © 2025 Henry Yu