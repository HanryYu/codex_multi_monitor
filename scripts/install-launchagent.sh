#!/usr/bin/env bash
set -euo pipefail

# ── locate project root ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LABEL="com.henry.codex-monitor"
PLIST_SRC="$PROJECT_ROOT/launchagents/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

# ── resolve executable path ──────────────────────────────────────────
# priority:
#   1. /Applications/CodexMonitor.app  (DMG / drag-install)
#   2. $PROJECT_ROOT/.build/CodexMonitor.app  (local swift build)
#   3. $PROJECT_ROOT/.build/release/CodexMonitor  (CLI binary)
resolve_executable() {
    local app="/Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor"
    if [[ -x "$app" ]]; then
        echo "$app"
        return
    fi

    local build_app="$PROJECT_ROOT/.build/CodexMonitor.app/Contents/MacOS/CodexMonitor"
    if [[ -x "$build_app" ]]; then
        echo "$build_app"
        return
    fi

    local cli="$PROJECT_ROOT/.build/release/CodexMonitor"
    if [[ -x "$cli" ]]; then
        echo "$cli"
        return
    fi

    echo ""
}

EXEC_PATH="$(resolve_executable)"

if [[ -z "$EXEC_PATH" ]]; then
    echo "❌ 找不到 CodexMonitor 可执行文件。请先构建项目或安装到 /Applications。"
    echo "   尝试过的路径:"
    echo "     /Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor"
    echo "     $PROJECT_ROOT/.build/CodexMonitor.app/Contents/MacOS/CodexMonitor"
    echo "     $PROJECT_ROOT/.build/release/CodexMonitor"
    exit 1
fi

echo "✅ 可执行文件: $EXEC_PATH"

# ── uninstall existing (if loaded) ───────────────────────────────────
if launchctl list "$LABEL" &>/dev/null; then
    echo "⏹  卸载已有 LaunchAgent..."
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || \
        launchctl unload "$PLIST_DST" 2>/dev/null || true
fi

# ── write plist ──────────────────────────────────────────────────────
sed "s|__EXECUTABLE_PATH__|$EXEC_PATH|g" "$PLIST_SRC" > "$PLIST_DST"
echo "📄 plist 已写入 $PLIST_DST"

# ── load ─────────────────────────────────────────────────────────────
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || \
    launchctl load "$PLIST_DST"

echo "✅ LaunchAgent 已加载 — 下次登录自动启动 CodexMonitor"
echo "   立即启动: launchctl start $LABEL"
