#!/bin/bash
# 把晚点名签到加入 Windows 任务计划程序
# 注意: 需要在 Git Bash 或 WSL 中运行，或自行转换为 PowerShell
# 用法: bash install-schtasks.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${NWU_TOOLKIT_DIR:-C:\nwu-toolkit}"
PY="${NWU_PYTHON:-python3}"

# 验证文件存在
for f in "$TARGET_DIR/nwu-attendance.py"; do
    [ -f "$f" ] || { echo "错误: $f 不存在"; exit 1; }
done

echo "请将以下 PowerShell 命令复制到 PowerShell 中执行："
echo ""
echo "schtasks /Create /TN 'NWUAttendance' /TR 'python3 $TARGET_DIR\nwu-attendance.py --wait --jitter 600' /SC DAILY /ST 21:00 /RL HIGHEST"
echo ""
echo "或使用计划任务向导："
echo "  1. 打开 '任务计划程序' (taskschd.msc)"
echo "  2. 创建基本任务 -> 每天 21:00 -> 启动程序 -> python3"
echo "  3. 参数: $TARGET_DIR\nwu-attendance.py --wait --jitter 600"
echo "  4. 勾选 '不管用户是否登录都要运行'"
echo ""
echo "日志将写入 $TARGET_DIR\nwu-attendance.log"
