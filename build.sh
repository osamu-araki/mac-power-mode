#!/bin/bash
# Power Mode.app をビルドする
# 使い方: ./build.sh [出力先ディレクトリ]
# デフォルトの出力先: ./build.noindex/
# .noindex サフィックスにより Spotlight が成果物をインデックスしないため、
# ~/Applications/ にインストールしたものと重複表示されない。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$REPO_ROOT/build.noindex}"
APP_NAME="Power Mode"
APP="$OUT_DIR/${APP_NAME}.app"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "ERROR: swiftc が見つかりません。Xcode Command Line Tools をインストールしてください:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

echo "==> ビルドディレクトリを準備: $OUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts"

echo "==> Swift コードをコンパイル"
swiftc -O -o "$APP/Contents/MacOS/PowerMode" "$REPO_ROOT/PowerMode/main.swift" -framework Cocoa

echo "==> Info.plist を配置"
cp "$REPO_ROOT/PowerMode/Info.plist" "$APP/Contents/Info.plist"

echo "==> シェルスクリプトをアプリ内 Resources に同梱"
cp "$REPO_ROOT/scripts/"*.sh "$APP/Contents/Resources/scripts/"
chmod +x "$APP/Contents/Resources/scripts/"*.sh

echo "==> アドホック署名"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo ""
echo "ビルド完了: $APP"
echo ""
echo "次のステップ:"
echo "  ./install.sh         # ~/Applications/ にインストール"
echo "  open \"$APP\"  # 直接起動"
