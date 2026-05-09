#!/bin/bash
# Version: 1.0.1 | Updated: 2026-05-09
# 現在の電源モード（Mobile / Normal / Custom）を判定して通知する
# [2026-05-09] disablesleep は pmset -g の "SleepDisabled" 行から読むよう修正

set -u

# バッテリー駆動時の sleep 値（pmset -g custom の "Battery Power" セクション）
battery_section=$(/usr/bin/pmset -g custom | awk '/Battery Power:/{flag=1; next} /^[A-Za-z]/{flag=0} flag')
sleep_val=$(echo "$battery_section" | awk '$1=="sleep"{print $2; exit}')

# disablesleep はシステム全体設定。pmset -g の "SleepDisabled" 行から取得
disablesleep_val=$(/usr/bin/pmset -g | awk '$1=="SleepDisabled"{print $2; exit}')
disablesleep_val=${disablesleep_val:-0}
sleep_val=${sleep_val:-?}

# モード判定
if [ "$sleep_val" = "0" ] && [ "$disablesleep_val" = "1" ]; then
  mode="Mobile Mode"
  icon="🔋"
  body="バッテリーでも蓋を閉じて動作します"
elif [ "$sleep_val" = "1" ] && [ "$disablesleep_val" = "0" ]; then
  mode="Normal Mode"
  icon="🏠"
  body="バッテリー時はスリープします"
else
  mode="Custom"
  icon="⚙️"
  body="sleep=${sleep_val} / SleepDisabled=${disablesleep_val}"
fi

# 通知センターに表示
osascript -e "display notification \"$body\" with title \"$icon $mode\""

# 標準出力にも出す
echo "$mode (sleep=${sleep_val}, SleepDisabled=${disablesleep_val})"

exit 0
