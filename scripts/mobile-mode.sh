#!/bin/bash
# Version: 1.0.0 | Updated: 2026-05-09
# Mobile Mode ON: バッテリー駆動でも蓋を閉じて動作し続ける状態にする

set -u

# pmset 設定変更（バッテリー駆動時）
if ! sudo /usr/bin/pmset -b sleep 0; then
  osascript -e 'display notification "pmset -b sleep 0 に失敗しました" with title "⚠️ Mobile Mode 失敗"'
  exit 1
fi

if ! sudo /usr/bin/pmset -b disablesleep 1; then
  osascript -e 'display notification "pmset -b disablesleep 1 に失敗しました" with title "⚠️ Mobile Mode 失敗"'
  exit 1
fi

# 完了通知
osascript -e 'display notification "バッテリーでも蓋を閉じて動作します" with title "🔋 Mobile Mode ON"'

exit 0
