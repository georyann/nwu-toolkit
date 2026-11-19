#!/bin/bash
# 把晚点名签到加入 crontab（Linux）
# 用法: bash install-cron.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${NWU_TOOLKIT_DIR:-/opt/nwu-toolkit}"
PY="${NWU_PYTHON:-python3}"
CRON_SPEC="0 21 * * *"

# 验证文件存在
for f in "$TARGET_DIR/nwu-attendance.py"; do
    [ -f "$f" ] || { echo "错误: $f 不存在"; exit 1; }
done

# 验证 python3
command -v "$PY" >/dev/null 2>&1 || { echo "错误: $PY 不可用"; exit 1; }

# 备份现有 crontab
CRON_FILE=$(mktemp)
crontab -l 2>/dev/null > "$CRON_FILE" || true

# 添加新任务
if ! crontab -l 2>/dev/null | grep -q "nwu-attendance"; then
    echo "$CRON_SPEC $PY $TARGET_DIR/nwu-attendance.py --wait --jitter 600 >> $TARGET_DIR/nwu-attendance.log 2>&1" >> "$CRON_FILE"
    crontab "$CRON_FILE"
    echo "已添加 crontab 任务: $CRON_SPEC"
    echo "$PY $TARGET_DIR/nwu-attendance.py --wait --jitter 600"
else
    echo "crontab 中已存在 nwu-attendance 任务"
fi

rm -f "$CRON_FILE"
echo "日志: $TARGET_DIR/nwu-attendance.log"
