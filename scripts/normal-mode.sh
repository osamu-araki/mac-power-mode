#!/bin/bash
# Version: 1.0.0 | Updated: 2026-05-09
# Normal Mode ON: macOS 標準のスリープ動作に戻す

set -u

# pmset 設定変更（バッテリー駆動時）
if ! sudo /usr/bin/pmset -b sleep 1; then
  osascript -e 'display notification "pmset -b sleep 1 に失敗しました" with title "⚠️ Normal Mode 失敗"'
  exit 1
fi

if ! sudo /usr/bin/pmset -b disablesleep 0; then
  osascript -e 'display notification "pmset -b disablesleep 0 に失敗しました" with title "⚠️ Normal Mode 失敗"'
  exit 1
fi

# 完了通知
osascript -e 'display notification "バッテリー時はスリープします" with title "🏠 Normal Mode ON"'

exit 0
