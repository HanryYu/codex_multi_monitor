#!/usr/bin/env bash
set -euo pipefail

LABEL="com.henry.codex-monitor"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

# ── unload ───────────────────────────────────────────────────────────
if launchctl list "$LABEL" &>/dev/null; then
    echo "⏹  卸载 LaunchAgent..."
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || \
        launchctl unload "$PLIST_DST" 2>/dev/null || true
    echo "✅ 已卸载"
else
    echo "ℹ️  LaunchAgent 未在运行"
fi

# ── remove plist ─────────────────────────────────────────────────────
if [[ -f "$PLIST_DST" ]]; then
    rm "$PLIST_DST"
    echo "🗑  已删除 $PLIST_DST"
else
    echo "ℹ️  plist 文件不存在"
fi

echo "✅ LaunchAgent 已完全移除"
