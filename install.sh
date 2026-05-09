#!/bin/bash
# Power Mode のインストールスクリプト
# 1. アプリをビルド
# 2. ~/Applications/ に配置
# 3. /etc/sudoers.d/pmset を設定（pmset のパスワード省略）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Power Mode"
APPLICATIONS_DIR="$HOME/Applications"
SUDOERS_FILE="/etc/sudoers.d/pmset"
BUILD_DIR="$REPO_ROOT/build.noindex"

echo "================================================"
echo "  Power Mode インストーラ"
echo "================================================"
echo ""

# Step 1: アプリをビルド
echo "[1/3] アプリをビルドします"
"$REPO_ROOT/build.sh" "$BUILD_DIR"
echo ""

# Step 2: ~/Applications/ にコピー
echo "[2/3] ~/Applications/ に配置します"
mkdir -p "$APPLICATIONS_DIR"
DEST="$APPLICATIONS_DIR/${APP_NAME}.app"

if [ -e "$DEST" ]; then
  # 既存アプリは終了させてから上書き
  pkill -f "${APP_NAME}.app/Contents/MacOS/PowerMode" 2>/dev/null || true
  sleep 1
fi

rm -rf "$DEST"
cp -R "$BUILD_DIR/${APP_NAME}.app" "$DEST"
echo "   配置完了: $DEST"
echo ""

# Step 3: sudoers 設定
echo "[3/3] sudoers 設定（pmset のパスワード省略）"
if [ -f "$SUDOERS_FILE" ] && sudo grep -q "pmset" "$SUDOERS_FILE" 2>/dev/null; then
  echo "   既に設定済み: $SUDOERS_FILE"
else
  echo "   /etc/sudoers.d/pmset を作成します（sudo パスワードが必要）"
  TMP_FILE="$(mktemp)"
  cp "$REPO_ROOT/sudoers.d/pmset" "$TMP_FILE"

  if /usr/sbin/visudo -cf "$TMP_FILE" >/dev/null; then
    sudo install -m 0440 -o root -g wheel "$TMP_FILE" "$SUDOERS_FILE"
    rm -f "$TMP_FILE"
    echo "   配置完了: $SUDOERS_FILE"
  else
    rm -f "$TMP_FILE"
    echo "   ERROR: sudoers ファイルの構文チェックに失敗しました" >&2
    exit 1
  fi
fi
echo ""

echo "================================================"
echo "  インストール完了"
echo "================================================"
echo ""
echo "起動方法:"
echo "  open \"$DEST\""
echo ""
echo "Spotlight (Cmd+Space) で \"Power Mode\" と入力しても起動できます。"
echo ""
echo "ログイン時に自動起動させたい場合:"
echo "  システム設定 → 一般 → ログイン項目とアクセス権 → \"+\" で Power Mode.app を追加"
