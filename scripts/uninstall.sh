#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexVisual"
EXECUTABLE_NAME="CodexVisual"
OLD_EXECUTABLE_NAME="CodexQuotaBar"
INSTALL_APP="$HOME/Applications/$APP_NAME.app"
OLD_INSTALL_APP="$HOME/Applications/CodexQuotaBar.app"
SPACED_INSTALL_APP="$HOME/Applications/Codex Visual.app"
CACHE_DIR="$HOME/Library/Application Support/CodexVisual"
OLD_CACHE_DIR="$HOME/Library/Application Support/CodexQuotaBar"

/usr/bin/pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
/usr/bin/pkill -x "$OLD_EXECUTABLE_NAME" 2>/dev/null || true
/bin/rm -rf "/Applications/$APP_NAME.app" 2>/dev/null || true
/bin/rm -rf "/Applications/CodexQuotaBar.app" 2>/dev/null || true
/bin/rm -rf "/Applications/Codex Visual.app" 2>/dev/null || true
/bin/rm -rf "$INSTALL_APP"
/bin/rm -rf "$OLD_INSTALL_APP"
/bin/rm -rf "$SPACED_INSTALL_APP"
/bin/rm -rf "$CACHE_DIR"
/bin/rm -rf "$OLD_CACHE_DIR"
/bin/rm -f "$HOME/Library/Preferences/com.orangeshushu.CodexVisual.plist" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/Caches/com.orangeshushu.CodexVisual" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/Caches/CodexVisual" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/HTTPStorages/com.orangeshushu.CodexVisual" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/WebKit/com.orangeshushu.CodexVisual" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/Containers/com.orangeshushu.CodexVisual" 2>/dev/null || true

echo "已卸载 $APP_NAME"
