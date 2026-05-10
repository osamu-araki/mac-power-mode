#!/bin/bash
# Version: 1.1.0 | Updated: 2026-05-10
# Normal Mode ON: macOS 標準のスリープ動作に戻す
# [2026-05-10] mobile-mode.sh が起動した caffeinate -u を PID で停止する処理を追加

set -u

PIDFILE="/tmp/power-mode-caffeinate.pid"

# pmset 設定変更（バッテリー駆動時）
if ! sudo /usr/bin/pmset -b sleep 1; then
  osascript -e 'display notification "pmset -b sleep 1 に失敗しました" with title "⚠️ Normal Mode 失敗"'
  exit 1
fi

if ! sudo /usr/bin/pmset -b disablesleep 0; then
  osascript -e 'display notification "pmset -b disablesleep 0 に失敗しました" with title "⚠️ Normal Mode 失敗"'
  exit 1
fi

# Power Mode 由来の caffeinate を停止（PID 一致するもののみ）
if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
fi

# 完了通知
osascript -e 'display notification "バッテリー時はスリープします" with title "🏠 Normal Mode ON"'

exit 0
