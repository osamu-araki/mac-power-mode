#!/bin/bash
# Power Mode のアンインストールスクリプト

set -euo pipefail

APP_NAME="Power Mode"
APPLICATIONS_DIR="$HOME/Applications"
SUDOERS_FILE="/etc/sudoers.d/pmset"

echo "==> Power Mode.app を終了"
pkill -f "${APP_NAME}.app/Contents/MacOS/PowerMode" 2>/dev/null || true
sleep 1

echo "==> ~/Applications/ から削除"
DEST="$APPLICATIONS_DIR/${APP_NAME}.app"
if [ -e "$DEST" ]; then
  # ゴミ箱に移動（Finderで復元可能）
  osascript -e "tell application \"Finder\" to delete (POSIX file \"$DEST\" as alias)" >/dev/null 2>&1 || rm -rf "$DEST"
  echo "   削除完了: $DEST"
else
  echo "   見つかりません: $DEST"
fi

echo "==> 電源設定をデフォルトに戻す"
sudo /usr/bin/pmset -b restoredefaults || true

echo "==> sudoers 設定を削除"
if [ -f "$SUDOERS_FILE" ]; then
  sudo rm -f "$SUDOERS_FILE"
  echo "   削除完了: $SUDOERS_FILE"
else
  echo "   見つかりません: $SUDOERS_FILE"
fi

echo ""
echo "アンインストール完了"
