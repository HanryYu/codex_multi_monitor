# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/) [![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE) [![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest) [![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

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
- [更新通知](#更新通知)
- [自動化と CI/CD](#自動化と-cicd)
- [トラブルシューティング](#トラブルシューティング)
- [ライセンス](#ライセンス)

## 機能

- **リアルタイム監視** — macOS メニューバーから直接 Codex の使用状況を追跡
- **マルチアカウント対応** — 複数の Codex アカウントを簡単に切り替えながら監視
- **使用量の可視化** — カラーコード付きステータスインジケーターでクォータ使用量を表示
- **制限到達アラート** — 5時間または週間制限到達時にビジュアルオーバーレイとリセットカウントダウンを表示
- **スマート通知** — クォータが低下した時やアカウントが制限から回復した時に通知
- **アカウント自動同期** — 起動時にローカルの Codex アカウントを自動検出・追加
- **多言語対応** — English、中文、日本語
- **更新通知** — GitHub で新しいバージョンが利用可能になったら自動通知

## 要件

- macOS 15.0+
- Xcode 16+（ソースからビルドする場合）
- Swift 6.0+

## インストール

### DMG ダウンロード（推奨）

1. [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest) にアクセス
2. `CodexMonitor-x.x.x.dmg` ファイルをダウンロード
3. DMG を開いて **CodexMonitor** を **Applications** フォルダにドラッグ
4. CodexMonitor を起動 — メニューバーに表示されます

> **注意:** アプリは Apple Development 証明書で署名されています。初回起動時に macOS がセキュリティ警告を表示する場合、アプリを右クリックして「開く」を選択してください。

### ソースからビルド

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
make install
```

または手動で：

```bash
swift build -c release
cp -f .build/release/CodexMonitor /Applications/CodexMonitor.app/Contents/MacOS/
open /Applications/CodexMonitor.app
```

## API Token の取得

1. [chatgpt.com/codex](https://chatgpt.com/codex) にアクセス
2. ChatGPT アカウントでログイン
3. 開発者ツール → **Network** タブを開く
4. `ab.chatgpt.com` または `chatgpt.com` への API リクエストを探す
5. **Authorization** ヘッダーを探す — UUID 形式のトークンが含まれています（例: `3f8c2b1a-...`）
6. このトークンをコピー

> **ヒント:** すでにローカルで Codex を使用している場合、初回起動時にアプリがアカウントを自動検出します。

## 使い方

1. Applications フォルダから **CodexMonitor** を起動
2. メニューバーのアイコンをクリックしてアカウントを表示
3. **+** をクリックしてアカウントを追加し、API トークンを貼り付け
4. アプリは30秒ごとに自動的にデータを更新

### キーボードショートカット

| ショートカット | アクション |
|--------------|-----------|
| `⌘ + N` | 新しいアカウントを追加 |
| `⌘ + ,` | 環境設定を開く |
| `⌘ + Q` | 終了 |

### アカウントトークンの検出

初回起動時、アプリは `~/Library/Application Support/codex/` 内の既存の Codex アカウントを検索し、インポートを促します — トークンを手動でコピーする必要はありません。

## ステータスカラー

| 色 | 意味 |
|---|------|
| 🟢 緑 | 残りクォータ > 50% |
| 🟡 黄 | 残りクォータ 20〜50% |
| 🔴 赤 | 残りクォータ < 20% |

制限（5時間または週間）に達すると、ステータスエリアに「Limit Reached」オーバーレイと推定リセット時間が表示されます。

## 更新通知

CodexMonitor は GitHub Releases の新しいバージョンを自動的にチェックします。新しいバージョンが利用可能な場合、メニューバーに通知が表示され、リリースページを直接開くことができます。

## 自動化と CI/CD

CodexMonitor は OpenAI の Codex GitHub ボットとシームレスに連携するよう設計されており、自動化されたコードレビューと PR 管理が可能です。

### 仕組み

1. **Codex ボット** は `codex.yaml` ワークフローで GitHub 上で実行
2. **CodexMonitor** は全アカウントの API 使用状況とクォータを追跡
3. あるアカウントが制限に達したら、別のアカウントに切り替えて Codex を稼働し続ける

### リポジトリの設定

リポジトリに `.github/workflows/codex.yaml` を追加：

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

## トラブルシューティング

**メニューバーにアイコンが表示されない？**
- アクティビティモニターを確認 — アプリがすでに実行中の可能性があります。強制終了して再起動してください。

**初回起動時に「アカウントが見つかりません」？**
- ローカルで Codex を少なくとも1回使用していることを確認するか、**+** ボタンからトークンを手動で追加してください。

**DMG が開かない / 「未確認の開発元」？**
- 右クリック → 開く、またはシステム設定 → プライバシーとセキュリティ → 「許可」をクリック。

## ライセンス

[GPLv3](LICENSE) — © 2025 Henry Yu
