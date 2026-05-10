#!/bin/bash
# Version: 1.1.0 | Updated: 2026-05-10
# Mobile Mode ON: バッテリー駆動でも蓋を閉じて動作し続ける状態にする
# [2026-05-10] caffeinate -u によるユーザーアクティブ・アサーションを追加。
#              蓋を閉じても OS が "ユーザーが離席した" と判定しないようにし、
#              Spotlight/Time Machine/iCloud などの重い背景タスクの自動起動を抑制する。

set -u

PIDFILE="/tmp/power-mode-caffeinate.pid"

# pmset 設定変更（バッテリー駆動時）
if ! sudo /usr/bin/pmset -b sleep 0; then
  osascript -e 'display notification "pmset -b sleep 0 に失敗しました" with title "⚠️ Mobile Mode 失敗"'
  exit 1
fi

if ! sudo /usr/bin/pmset -b disablesleep 1; then
  osascript -e 'display notification "pmset -b disablesleep 1 に失敗しました" with title "⚠️ Mobile Mode 失敗"'
  exit 1
fi

# 既存の Power Mode 由来の caffeinate を停止（多重起動防止）
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "${OLD_PID:-}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
fi

# UserIsActive アサーションを長時間維持（11.5日 ≒ 999999秒）。
# Normal Mode に戻すと PID 経由で停止される。
nohup /usr/bin/caffeinate -u -t 999999 > /dev/null 2>&1 &
CAFFEINATE_PID=$!
echo "$CAFFEINATE_PID" > "$PIDFILE"

# 完了通知
osascript -e 'display notification "バッテリーでも蓋を閉じて動作します（背景タスク抑制中）" with title "🔋 Mobile Mode ON"'

exit 0
