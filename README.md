# Power Mode

> macOS のメニューバーから「バッテリー駆動でも蓋を閉じて動作させ続けるモード」をワンクリックで切り替えるアプリ。

カバンの中など、バッテリー駆動かつ蓋を閉じた状態で MacBook 上のジョブ（長時間ビルド、リモートエージェント、Claude Code など）を継続実行したい時のための小さなユーティリティです。

## 特徴

- **メニューバー常駐**：`🔋 Mobile` / `💤 Normal` で現在のモードを一目で確認
- **ワンクリック切替**：`Mobile Mode に切替` / `Normal Mode に切替` をメニューから選ぶだけ
- **sudo パスワードなし**：`/etc/sudoers.d/pmset` 経由で `pmset` のみパスワード省略
- **Dock を汚さない**：`LSUIElement=true` で Dock アイコン非表示

## モード仕様

| モード | `pmset -g` の値 | 挙動 |
|---|---|---|
| **🔋 Mobile** | `sleep=0`, `SleepDisabled=1` | バッテリー駆動でも蓋を閉じて動作継続 |
| **💤 Normal** | `sleep=1`, `SleepDisabled=0` | macOS 標準のスリープ動作（蓋を閉じればスリープ） |

`pmset` のバッテリー駆動時 `sleep` とシステム全体の `SleepDisabled`（clamshell sleep）の2つを切り替えています。

## 動作環境

- macOS 11 (Big Sur) 以降
- Apple Silicon / Intel どちらも可
- Xcode Command Line Tools（`swiftc` が必要）

```bash
xcode-select --install  # 未インストールの場合
```

## インストール

```bash
git clone https://github.com/osamu-araki/mac-power-mode.git
cd mac-power-mode
./install.sh
```

`install.sh` は以下を自動実行します:

1. `swiftc` で `Power Mode.app` をビルド
2. `~/Applications/Power Mode.app` に配置
3. `/etc/sudoers.d/pmset` を設定（**sudo パスワードが必要**）

インストール後、Spotlight (`Cmd + Space`) で `Power Mode` と入力するか、`~/Applications/Power Mode.app` を直接ダブルクリックして起動します。

### ログイン時に自動起動させる

**システム設定 → 一般 → ログイン項目とアクセス権 → 「ログイン時に開く」** で `+` ボタンから `~/Applications/Power Mode.app` を追加。

## 使い方

メニューバーのアイコンをクリックすると以下のメニューが表示されます:

```
現在: Mobile Mode    （情報表示）
─────────────────
Mobile Mode に切替  ⌘M
Normal Mode に切替  ⌘N
─────────────────
終了                 ⌘Q
```

切替直後、macOS の通知センターに結果が表示されます（要：通知許可）。

## アンインストール

```bash
./uninstall.sh
```

以下を実行します:
- アプリのプロセス終了
- `~/Applications/Power Mode.app` をゴミ箱へ
- `pmset -b restoredefaults` で電源設定をデフォルトに戻す
- `/etc/sudoers.d/pmset` を削除

## リポジトリ構成

```
mac-power-mode/
├── PowerMode/
│   ├── main.swift        # メニューバーアプリ本体（Swift + Cocoa）
│   └── Info.plist        # LSUIElement=true でDock非表示
├── scripts/
│   ├── mobile-mode.sh    # pmset で Mobile Mode に切替
│   ├── normal-mode.sh    # pmset で Normal Mode に切替
│   └── check-mode.sh     # 現在のモードを判定して通知表示
├── sudoers.d/
│   └── pmset             # %admin に pmset のみパスワード省略を許可
├── build.sh              # アプリをビルドするだけ
├── install.sh            # ビルド + ~/Applications/ 配置 + sudoers 設定
└── uninstall.sh          # アンインストール
```

## 開発

### ビルドのみ

```bash
./build.sh
# build/Power Mode.app が生成される
```

### スクリプトの場所をカスタマイズ

アプリは以下の優先順位でシェルスクリプトを探します:

1. 環境変数 `POWER_MODE_SCRIPTS_DIR`
2. アプリバンドル内 `Contents/Resources/scripts/`（`install.sh` 経由のデフォルト）
3. `~/scripts/`

## 注意事項

### バッテリー消費

- Mobile Mode で蓋を閉じて CPU 稼働させると、1時間で 20〜40% ほどバッテリーを消費する可能性があります
- 移動時はモバイルバッテリー（PD対応）の併用を推奨

### 発熱対策

- 蓋を閉じて CPU 稼働させると放熱効率が落ちます
- 鞄の中で長時間運用するとサーマルスロットリングや周辺機器への影響に注意
- 可能であれば蓋を少し開けた状態で鞄に入れる、または通気性のあるバッグを使用

### caffeinate との関係

このアプリは `pmset` の設定変更のみを行います。Claude Code 起動時の `caffeinate -dimsu claude` 等の運用とは独立して動作します。`caffeinate` のみでは蓋閉じスリープを防げないため、Mobile Mode が必要です。

## ライセンス

MIT License — [LICENSE](LICENSE) を参照。
