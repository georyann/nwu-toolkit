#!/bin/sh
# 把 NWU 工具（晚点名签到 + 校园网登录）装到这台 Mac
# 用法: bash install-nwu-attendance.sh

set -e

DIR=$(cd "$(dirname "$0")" && pwd)
PLIST="com.miniguo.nwu-attendance.checkin.plist"
TARGET="~/Library/LaunchAgents/${PLIST}"

echo "→ 检查 Python 解释器"
PY=/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9
[ -x "$PY" ] || { echo "找不到 $PY，请先装 Xcode Command Line Tools"; exit 1; }

echo "→ 复制 plist 到 ~/Library/LaunchAgents/"
envsubst < "$DIR/$PLIST" > "$TARGET"

echo "→ 加载定时任务（每天 21:00）"
launchctl bootout gui/$(id -u)/com.miniguo.nwu-attendance.checkin 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$TARGET"
launchctl print gui/$(id -u)/com.miniguo.nwu-attendance.checkin | grep -E "state|last exit" || true

echo "→ 完成。每天 21:00 自动签到（开放后随机延迟）"
echo "   手动：python3 nwu-attendance.py --status"
echo "   卸载：launchctl bootout gui/$(id -u)/com.miniguo.nwu-attendance.checkin && rm $TARGET"
