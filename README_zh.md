# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/) [![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE) [![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest) [![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

一款 macOS 菜单栏应用，实时监控 ChatGPT Codex 的使用额度、重置 credit 和周额度周期启动状态。

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
- **用量可视化** — 同时显示 5 小时额度和周额度，并支持重置倒计时或绝对时间
- **限额状态** — 5 小时或周额度用尽时显示视觉遮罩和重置倒计时
- **重置 credit 看板** — 在每个账户卡片上显示可用重置次数、发放时间和到期时间
- **智能通知** — 额度过低时预警，并在 5 小时或周额度固定重置时间发送恢复提醒
- **周额度周期启动 (Beta)** — 周额度恢复后，或检测到云端重置导致周额度回到 100% 时，发送一次简短 Codex 请求来启动新的周订阅额度周期
- **自动账户同步** — 启动时自动检测本地 Codex 账户并添加
- **多语言** — English、中文、日本語
- **版本更新提醒** — GitHub 有新版本时自动提醒

> 周额度周期启动需要开启“自动账户同步”，这样 CodexMonitor 才能在你使用 [cc-switch](https://github.com/HanryYu/cc-switch) 等工具切换账号时捕获每个账号的完整 Codex 登录凭证。未开启时，只能使用当前 Codex 已登录账号执行刷新。主动请求会按账号和周额度 reset key 去重。

## 系统要求

- macOS 15.0+
- Xcode 16+（从源码构建时）
- Swift 6.0+

## 安装方式

### Homebrew（推荐）

```bash
brew install --cask HanryYu/tap/codex-multi-monitor
```

请使用上面的完整 tap token。Homebrew 官方 cask 仓库里也有另一个
`codexmonitor` cask，直接运行 `brew install --cask codexmonitor` 可能会安装到错误应用。

升级：
```bash
brew upgrade --cask HanryYu/tap/codex-multi-monitor
```

如果之前安装过旧的 tap token：
```bash
brew uninstall --cask HanryYu/tap/codexmonitor
brew install --cask HanryYu/tap/codex-multi-monitor
```

### 下载 DMG

1. 前往 [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
2. 下载 `CodexMonitor-x.x.x.dmg` 文件
3. 打开 DMG，将 **CodexMonitor** 拖入 **Applications** 文件夹
4. 启动 CodexMonitor — 它会出现在菜单栏中

官方发布版使用 Developer ID 签名、经过 Apple notarization，并同时支持 Apple Silicon 和 Intel Mac。

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

> 如果你使用 [cc-switch](https://github.com/HanryYu/cc-switch) 或手动切换 token，请保持“自动账户同步”开启；CodexMonitor 会保存每个切换过账号的完整登录凭证，用于全账号周额度周期启动。

### 方式 2：浏览器 Network 面板

1. 在浏览器中打开 [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) 并**登录**
2. 打开开发者工具（Mac 上按 `⌘⌥I`）→ **Network** 标签
3. 页面会自动加载使用数据 — 查找 `wham/usage` 请求
4. 点击该请求 → **Headers** → 复制 `Authorization: Bearer ***` 的值
5. 将 token（不含 `Bearer ` 前缀）粘贴到 CodexMonitor

### 方式 3：本地命令提取

如果你安装了 [Codex CLI](https://github.com/openai/codex)，可以用本地命令提取 token：

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

复制输出结果并粘贴到 CodexMonitor。

### Claude 与 Grok

CodexMonitor 支持 Codex、Claude 和 Grok 三种账户类型：

- **本地自动导入**：Claude Code 从 macOS 钥匙串中的 `Claude Code-credentials`（或 `~/.claude/.credentials.json`）读取；Grok Build 从 `~/.grok/auth.json` 读取。Claude access token 过期时会使用官方 OAuth refresh 流程，并把轮换后的 access/refresh token 写回原凭证存储，保持 Claude Code 登录有效。
- **手动添加**：先选择 Agent 类型，再粘贴 Bearer token。输入框也接受完整的 `Authorization: Bearer ...` 文本，以及 Claude/Grok 的本地 auth JSON。
- **Claude 网页 token**：登录 Claude 后，在开发者工具 Network 中打开 usage 请求，复制 `Authorization` 请求头中的 Bearer token。
- **Grok token**：可从 Grok CLI 请求的 `Authorization` 请求头复制 Bearer token，或直接把 `~/.grok/auth.json` 内容粘贴到 Grok 类型的 token 输入框。
- **Grok 网页登录态**：打开 `https://grok.com/?_s=usage`，在开发者工具 Network 中选择 `GetGrokCreditsConfig` 请求，复制完整的 `Cookie` 请求头并粘贴。网页模式读取与设置页面一致的共享周额度。

Claude 额度来自 `https://api.anthropic.com/api/oauth/usage`；Grok 本地模式读取 CLI billing，网页模式读取 `GetGrokCreditsConfig` 的共享周额度。应用会尝试自动刷新本地 Claude/Grok 凭证；刷新凭证无效时，再运行 `claude` 或 `grok login` 重新登录。

## 使用说明

1. 从应用程序文件夹启动 **CodexMonitor**
2. 点击菜单栏图标查看账户
3. 启动时自动检测账户 — 或点击 **+** 手动添加
4. 在设置里选择自动刷新间隔，默认是 5 分钟
5. 如果希望自动启动新的周额度周期，请在设置里开启 **每周额度周期**
6. 在账户卡片中展开重置 credit 行，可以查看每次 credit 的发放时间和到期时间

## 状态颜色

| 颜色 | 含义 |
|------|------|
| 🟢 绿色 | 剩余额度 > 50% |
| 🟡 黄色 | 剩余额度 20-50% |
| 🔴 红色 | 剩余额度 < 20% |

当达到限额（5 小时或周限额）时，状态区域会显示 "Limit Reached" 遮罩和预计重置时间。
开启额度恢复提醒后，CodexMonitor 会直接为该重置时间预约系统通知，而不是等下一次用量刷新后再提醒。

可用的重置 credit 会显示在额度卡片下方。展开后可以查看每个 credit 的发放时间和到期时间。

## 常见问题

**菜单栏图标不显示？**
- 打开活动监视器检查 — 应用可能已在运行。强制退出后重新启动。

**首次启动时"未找到账户"？**
- 确保你已经在本地使用过 Codex 至少一次，或通过 **+** 按钮手动添加 token。

**周额度周期启动没有执行？**
- 确认已开启 **每周额度周期** 和 **自动账户同步**，本机能找到 Codex CLI，并且该账号已经保存完整 Codex 登录凭证。CodexMonitor 会按账号去重主动请求，同一账号 5 分钟内也不会重复执行。

**DMG 打不开 / "未识别的开发者"？**
- 请从官方 [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest) 页面下载最新 notarized DMG 后重新安装。

## 开源协议

[GPLv3](LICENSE) — © 2026 Ryan Hansen
