#!/bin/bash
# Version: 1.2.0 | Updated: 2026-05-10
# Mobile Mode ON: バッテリー駆動でも蓋を閉じて動作し続ける状態にする
# 注: UserIsActive アサーションは Swift アプリ側で IOPMAssertion を直接保持する。
#     v1.5.0 で本スクリプトに caffeinate -u を入れたが、PID ファイル方式の
#     脆弱性（symlink 攻撃・PID再利用・誤kill・競合）を Codex レビューで指摘されたため
#     v1.5.1 で Swift 側に移し、本スクリプトは pmset 操作のみに戻している。

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
