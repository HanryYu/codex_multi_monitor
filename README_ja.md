# CodexMonitor

<div align="right">

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

</div>

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/)[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/)[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE)[![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

ChatGPT Codex の使用量をリアルタイムで監視する macOS メニューバーアプリ。

<p align="center">
  <img src="https://raw.githubusercontent.com/HanryYu/codex_multi_monitor/main/assets/codexmonitor-screenshot.png" alt="CodexMonitor スクリーンショット" width="420">
</p>

---

## 目次

- [機能](#機能)
- [要件](#要件)
- [インストール](#インストール)
- [API Token の取得](#api-token-の取得)
- [使い方](#使い方)
- [ステータスカラー](#ステータスカラー)
- [自動化と CI/CD](#自動化と-cicd)
- [トラブルシューティング](#トラブルシューティング)
- [ライセンス](#ライセンス)

---

## 機能

- 🎯 **メニューバーアプリ** — macOS メニューバーに常駐、Dock アイコンなし
- 📊 **リアルタイム監視** — 5時間および週間の使用制限を追跡
- 🔐 **安全なストレージ** — AES-256 暗号化ローカル Token 保存
- 🔄 **自動更新** — 設定可能な更新間隔（1〜60分、デフォルト5分）
- 🎨 **ステータス表示** — 使用量に基づくカラーコードアイコン（緑/黄/赤）
- 👥 **マルチアカウント** — 複数の ChatGPT アカウントを同時に監視
- 🤖 **アカウント自動同期** — `~/.codex/auth.json` からアカウントを自動検出・インポート — [cc-switch](https://github.com/HanryYu/cc-switch) や手動 Token 切り替えに対応
- ⚙️ **統合設定** — タブ式の設定ウィンドウ
- 📐 **表示モード** — 残量または使用済みパーセンテージを表示
- ⏱️ **リセット時間フォーマット** — 相対時間（「3時間20分後」）または絶対時間（「15:06」）
- 🔔 **スマート通知** — 閾値超過時のアラート、制限回復時の通知
- 🌐 **多言語対応** — English、简体中文、繁體中文、日本語

## 要件

- macOS 15.0 (Sequoia) 以降
- Swift 6.0+
- ChatGPT Plus / Pro / Enterprise サブスクリプション

## インストール

### DMG ダウンロード（推奨）

1. [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest) にアクセス
2. `.dmg` ファイルをダウンロード
3. 開いて **CodexMonitor** を Applications にドラッグ

### ソースからビルド

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
swift build -c release
```

バイナリは `.build/release/CodexMonitor` に出力されます。

## API Token の取得

### 方法 1：Codex CLI 認証ファイル（推奨）

[Codex CLI](https://github.com/openai/codex) をインストールしている場合、Token はローカルに保存されています：

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

出力をコピーして CodexMonitor に貼り付けます。

### 方法 2：ブラウザのネットワークタブ

1. ブラウザで [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) を開いて**ログイン**
2. 開発者ツール（Mac では `⌘⌥I`）→ **ネットワーク** タブ
3. ページが自動的に使用データを読み込み — `wham/usage` リクエストを探す
4. リクエストをクリック → **ヘッダー** → `Authorization: Bearer *** の値をコピー
5. Token（`Bearer ` プレフィックスなし）を CodexMonitor に貼り付け

## 使い方

1. **起動** — ゲージアイコンがメニューバーに表示されます
2. **クリック** — 全アカウントの監視パネルを開きます
3. **アカウント追加** — "+" をクリック（または設定を開いて）Token を貼り付け
4. **監視** — アカウントごとのリアルタイム使用統計を確認

### 設定

歯車アイコンから開く：

- **アカウント管理** — 追加、編集、削除、ドラッグで並べ替え
- **環境設定** — 表示モード、リセット時間フォーマット、更新間隔、ログイン時起動、通知設定

## ステータスカラー

| 色 | 意味 |
|---|------|
| 🟢 緑 | 使用量健全（< 60%） |
| 🟡 黄 | 制限に近づき中（60〜80%） |
| 🔴 赤 | 制限到達または接近（> 80%） |

## 自動化と CI/CD

GitHub Actions による自動リリースビルド：

- **Release ワークフロー** — バージョンタグのプッシュでトリガー（`v*`）
- `swift build -c release` でリリースバイナリをビルド
- Developer ID によるコード署名（GitHub Secrets 経由）
- DMG インストーラーを作成
- DMG を添付した GitHub Release を公開

新しいリリースを作成：

```bash
git tag v1.0.0
git push origin v1.0.0
```

ワークフローが自動的にビルド、署名、公開します。

## トラブルシューティング

**「Unauthorized」エラー**
- Token の有効期限が切れている可能性があります — 上記のコマンドで新しい Token を取得

**データが表示されない**
- インターネット接続を確認
- Token が有効であることを確認
- ポップアップの更新ボタンをクリック

**アプリが表示されない**
- 実行中か確認：`ps aux | grep CodexMonitor`
- メニューバーでゲージアイコンを探す
- アプリは Dock に表示されません（仕様）

## ライセンス

[GPLv3](LICENSE)
