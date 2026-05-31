# CodexMonitor

<div align="right">

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

</div>

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/)[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/)[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE)[![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

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
- [自动化与 CI/CD](#自动化与-cicd)
- [常见问题](#常见问题)
- [开源协议](#开源协议)

---

## 功能特性

- 🎯 **菜单栏应用** — 常驻 macOS 菜单栏，不显示 Dock 图标
- 📊 **实时监控** — 追踪 5 小时和每周的使用限额
- 🔐 **安全存储** — AES-256 加密的本地 Token 存储
- 🔄 **自动刷新** — 可配置的刷新间隔（1–60 分钟，默认 5 分钟）
- 🎨 **状态指示** — 根据使用量显示颜色编码图标（绿/黄/红）
- 👥 **多账户** — 同时监控多个 ChatGPT 账户
- 🤖 **账户自动同步** — 自动检测并导入 `~/.codex/auth.json` 中的账户 — 兼容 [cc-switch](https://github.com/HanryYu/cc-switch) 或手动切换 Token
- ⚙️ **统一设置** — 标签页式的设置窗口
- 📐 **显示模式** — 显示剩余或已用百分比
- ⏱️ **重置时间格式** — 相对时间（"3 小时 20 分钟后"）或绝对时间（"15:06"）
- 🔔 **智能通知** — 超过阈值时提醒，限额恢复时通知
- 🌐 **多语言** — English、简体中文、繁體中文、日本語

## 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- Swift 6.0+
- ChatGPT Plus / Pro / Enterprise 订阅

## 安装方式

### 下载 DMG（推荐）

1. 前往 [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
2. 下载 `.dmg` 文件
3. 打开并将 **CodexMonitor** 拖入 Applications

### 从源码构建

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
swift build -c release
```

构建产物位于 `.build/release/CodexMonitor`。

## 获取 API Token

### 方式一：Codex CLI 认证文件（推荐）

如果已安装 [Codex CLI](https://github.com/openai/codex)，Token 存储在本地：

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

复制输出内容并粘贴到 CodexMonitor。

### 方式二：浏览器网络面板

1. 在浏览器中打开 [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) 并**登录**
2. 打开开发者工具（Mac 上按 `⌘⌥I`）→ **网络** 标签页
3. 页面会自动加载使用数据 — 找到 `wham/usage` 请求
4. 点击该请求 → **标头** → 复制 `Authorization: Bearer ***` 的值
5. 将 Token（不含 `Bearer ` 前缀）粘贴到 CodexMonitor

## 使用说明

1. **启动** — 应用以仪表盘图标出现在菜单栏
2. **点击** — 打开监控面板，显示所有账户
3. **添加账户** — 点击 "+"（或打开设置）粘贴你的 Token
4. **监控** — 查看每个账户的实时使用统计

### 设置

通过齿轮图标打开：

- **账户管理** — 添加、编辑、删除或拖拽排序账户
- **偏好设置** — 显示模式、重置时间格式、刷新间隔、开机自启、通知设置

## 状态颜色

| 颜色 | 含义 |
|------|------|
| 🟢 绿色 | 使用量健康（< 60%） |
| 🟡 黄色 | 接近限额（60–80%） |
| 🔴 红色 | 已达或接近限额（> 80%） |

## 自动化与 CI/CD

项目使用 GitHub Actions 进行自动发布构建：

- **Release 工作流** 在版本标签推送时触发（`v*`）
- 使用 `swift build -c release` 构建发布二进制文件
- 通过 Developer ID 进行代码签名（经由 GitHub Secrets）
- 创建 DMG 安装包
- 发布 GitHub Release 并附带 DMG

创建新版本：

```bash
git tag v1.0.0
git push origin v1.0.0
```

工作流会自动构建、签名并发布。

## 常见问题

**"Unauthorized" 错误**
- Token 可能已过期 — 使用上面的命令行获取新 Token

**无数据展示**
- 检查网络连接
- 验证 Token 是否有效
- 点击弹窗中的刷新按钮

**应用未显示**
- 检查是否正在运行：`ps aux | grep CodexMonitor`
- 在菜单栏中查找仪表盘图标
- 应用默认不在 Dock 中显示（设计如此）

## 开源协议

[GPLv3](LICENSE)
