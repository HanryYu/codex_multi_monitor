# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/) [![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE) [![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest) [![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

ChatGPT Codex の使用量、リセットクレジット、週間サイクル開始状態をリアルタイムで監視する macOS メニューバーアプリ。

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
- [トラブルシューティング](#トラブルシューティング)
- [ライセンス](#ライセンス)

## 機能

- **リアルタイム監視** — macOS メニューバーから直接 Codex の使用状況を追跡
- **マルチアカウント対応** — 複数の Codex アカウントを簡単に切り替えながら監視
- **使用量の可視化** — 5時間クォータと週間クォータを、リセットのカウントダウンまたは絶対時刻とともに表示
- **制限到達アラート** — 5時間または週間制限到達時にビジュアルオーバーレイとリセットカウントダウンを表示
- **リセットクレジット表示** — 各アカウントカードに利用可能なリセット回数、付与時刻、有効期限を表示
- **スマート通知** — クォータが低下した時やアカウントが制限から回復した時に通知
- **週間サイクル開始 (Beta)** — 週間クォータ回復後、またはサーバー側リセットで週間クォータが残り100%になったことを検出した時に、短い Codex リクエストを1回送信して新しい週間サブスクリプションサイクルを開始
- **アカウント自動同期** — 起動時にローカルの Codex アカウントを自動検出・追加
- **多言語対応** — English、中文、日本語
- **更新通知** — GitHub で新しいバージョンが利用可能になったら自動通知

> 週間サイクル開始で全アカウントを対象にするには、アカウント自動同期を有効にして、[cc-switch](https://github.com/HanryYu/cc-switch) などで切り替えた各 Codex ログイン情報を保存してください。無効の場合は、現在サインイン中の Codex アカウントのみ開始できます。開始リクエストはアカウントと週間 reset key ごとに重複排除されます。

## 要件

- macOS 15.0+
- Xcode 16+（ソースからビルドする場合）
- Swift 6.0+

## インストール

### Homebrew（推奨）

```bash
brew install --cask HanryYu/tap/codex-multi-monitor
```

上記の完全修飾 tap token を使用してください。Homebrew 公式 cask
リポジトリにも別の `codexmonitor` cask があるため、
`brew install --cask codexmonitor` では違うアプリがインストールされる可能性があります。

アップグレード：
```bash
brew upgrade --cask HanryYu/tap/codex-multi-monitor
```

以前の tap token をインストール済みの場合：
```bash
brew uninstall --cask HanryYu/tap/codexmonitor
brew install --cask HanryYu/tap/codex-multi-monitor
```

### DMG ダウンロード

1. [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest) にアクセス
2. `CodexMonitor-x.x.x.dmg` ファイルをダウンロード
3. DMG を開いて **CodexMonitor** を **Applications** フォルダにドラッグ
4. CodexMonitor を起動 — メニューバーに表示されます

公式リリースビルドは Developer ID で署名され、Apple notarization 済みで、Apple Silicon と Intel Mac の両方に対応する Universal Binary です。

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

### 方法 1：アカウント自動管理（推奨）

CodexMonitor は Codex アカウントを自動検出・管理できます。アプリを起動するだけで、ローカル認証データをスキャンし、アカウントをインポートし、トークンのリフレッシュと重複排除を自動で処理します。

> [cc-switch](https://github.com/HanryYu/cc-switch) を使用している場合やトークンを手動で切り替えている場合は、アカウント自動同期を有効にしておくと、全アカウントの週間サイクル開始に必要なログイン情報を保存できます。

### 方法 2：ブラウザの Network タブ

1. ブラウザで [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) を開いて**ログイン**
2. 開発者ツール（Mac では `⌘⌥I`）→ **Network** タブ
3. ページが自動的に使用データを読み込み — `wham/usage` リクエストを探す
4. リクエストをクリック → **ヘッダー** → `Authorization: Bearer ***` の値をコピー
5. トークン（`Bearer ` プレフィックスなし）を CodexMonitor に貼り付け

### 方法 3：コマンドラインから取得

[Codex CLI](https://github.com/openai/codex) をインストールしている場合、ローカルからトークンを取得できます：

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

出力をコピーして CodexMonitor に貼り付けます。

## 使い方

1. Applications フォルダから **CodexMonitor** を起動
2. メニューバーのアイコンをクリックしてアカウントを表示
3. 起動時にアカウントを自動検出 — または **+** をクリックして手動追加
4. 設定で自動更新間隔を選択します。デフォルトは5分です
5. 週間クォータの新しいサイクルを自動開始したい場合は、設定で **週間上限サイクル** を有効にします
6. アカウントカードのリセットクレジット行を展開すると、各クレジットの付与時刻と有効期限を確認できます

## ステータスカラー

| 色 | 意味 |
|---|------|
| 🟢 緑 | 残りクォータ > 50% |
| 🟡 黄 | 残りクォータ 20〜50% |
| 🔴 赤 | 残りクォータ < 20% |

制限（5時間または週間）に達すると、ステータスエリアに「Limit Reached」オーバーレイと推定リセット時間が表示されます。

利用可能なリセットクレジットはクォータカードの下に表示されます。行を展開すると、各クレジットの付与時刻と有効期限を確認できます。

## トラブルシューティング

**メニューバーにアイコンが表示されない？**
- アクティビティモニターを確認 — アプリがすでに実行中の可能性があります。強制終了して再起動してください。

**初回起動時に「アカウントが見つかりません」？**
- ローカルで Codex を少なくとも1回使用していることを確認するか、**+** ボタンからトークンを手動で追加してください。

**週間サイクル開始が実行されない？**
- **週間上限サイクル** と **アカウント自動同期** が有効であること、Codex CLI がインストールされていること、対象アカウントの完全な Codex ログイン情報が保存されていることを確認してください。CodexMonitor は開始リクエストをアカウントごとに重複排除し、同じアカウントでは5分以内の再実行もスキップします。

**DMG が開かない / 「未確認の開発元」？**
- 公式 [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest) ページから最新の notarized DMG をダウンロードして再インストールしてください。

## ライセンス

[GPLv3](LICENSE) — © 2026 Ryan Hansen
