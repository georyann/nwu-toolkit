#!/bin/bash
# ============================================================================
# NWU 校园网与晚点名自动化工具 · 一键配置脚本
#
# 功能：
#   1) 晚点名签到（Python，Mac/Linux 本机或路由器）
#   2) 校园网自动登录（Shell，OpenWrt / Mac / Linux）
#   3) LuCI 网页版（OpenWrt 路由器）
#   4) 查看当前状态
#   5) 卸载
#   6) 帮助
#   7) 退出
#
# 用法: bash setup.sh
# 依赖: git（可选，用于拉取更新）
# ============================================================================

set -u

# ---------- 基础环境 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="nwu-toolkit"
REPO_URL="https://github.com/miniguo/nwu-toolkit"

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${GREEN}[nwu-toolkit]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[nwu-toolkit]${NC} %s\n" "$*"; }
err()  { printf "${RED}[nwu-toolkit]${NC} %s\n" "$*"; }

# ---------- 检测操作系统 ----------
detect_os() {
    local os
    if [[ "$(uname)" == "Darwin" ]]; then
        os="mac"
    elif [[ "$(uname)" == "Linux" ]]; then
        os="linux"
    elif [[ "$(uname)" == "CYGWIN"* || "$(uname)" == "MSYS"* ]]; then
        os="windows"
    else
        os="unknown"
    fi
    echo "$os"
}

OS=$(detect_os)
HOME_DIR="$HOME"

# ---------- 菜单 ----------
show_menu() {
    echo ""
    echo -e "${CYAN}=== NWU 校园网与晚点名自动化工具 ===${NC}"
    echo -e "  1) 安装/配置 晚点名签到"
    echo -e "  2) 安装/配置 校园网自动登录"
    echo -e "  3) 安装/配置 LuCI 网页版（OpenWrt 路由器）"
    echo -e "  4) 查看当前状态"
    echo -e "  5) 卸载"
    echo -e "  6) 帮助"
    echo -e "  7) 退出"
    echo -n -e "  请选择 [1-7]: ${NC}"
    read -r choice
    echo "$choice"
}

# ---------- 问问题（支持默认值） ----------
ask() {
    local prompt="$1"
    local default="$2"
    local value
    echo -n -e "  ${prompt} [默认: ${default}]: ${NC}"
    read -r value
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    echo "$value"
}

# ---------- 1) 晚点名签到 ----------
setup_attendance() {
    echo ""
    echo -e "${CYAN}--- 晚点名签到 ---${NC}"
    echo -e "  将 $PROJECT_NAME/nwu-attendance.py 复制到本机并配置定时任务"
    echo ""

    # 目标目录
    case "$OS" in
        mac)
            TARGET_DIR=$(ask "签到脚本存放目录（Mac 推荐 ~/Library/Application Support/nwu-toolkit）" \
                "$HOME_DIR/Library/Application Support/nwu-toolkit")
            ;;
        linux)
            TARGET_DIR=$(ask "签到脚本存放目录（Linux 推荐 /opt/nwu-toolkit）" "/opt/nwu-toolkit")
            ;;
        windows)
            TARGET_DIR=$(ask "签到脚本存放目录（Windows 推荐 C:\nwu-toolkit）" "C:\nwu-toolkit")
            ;;
        *)
            TARGET_DIR=$(ask "签到脚本存放目录" "$HOME_DIR/nwu-toolkit")
            ;;
    esac

    mkdir -p "$TARGET_DIR"

    # 复制脚本
    cp "$SCRIPT_DIR/nwu-attendance.py" "$TARGET_DIR/nwu-attendance.py"
    cp "$SCRIPT_DIR/config.example.json" "$TARGET_DIR/config.example.json"

    # 交互式初始化
    echo ""
    echo -e "  开始交互式配置..."
    python3 "$TARGET_DIR/nwu-attendance.py" --init || {
        err "初始化失败，请检查 python3 是否可用"
        return 1
    }

    # 配置定时任务
    echo ""
    echo -e "  是否配置定时任务（每天 21:00 自动签到）？"
    echo -e "  1) 是"
    echo -e "  2) 否（稍后手动执行）"
    echo -n -e "  请选择 [1-2]: ${NC}"
    read -r schedule
    case "$schedule" in
        1)
            case "$OS" in
                mac)
                    echo "  使用 launchd，请运行："
                    echo "    bash $SCRIPT_DIR/install-nwu-attendance.sh"
                    log "已生成安装脚本，请运行 bash $SCRIPT_DIR/install-nwu-attendance.sh"
                    ;;
                linux)
                    echo "  使用 crontab，请运行："
                    echo "    bash $SCRIPT_DIR/install-cron.sh"
                    log "已生成安装脚本，请运行 bash $SCRIPT_DIR/install-cron.sh"
                    ;;
                windows)
                    echo "  使用 Windows 任务计划程序，请运行："
                    echo "    bash $SCRIPT_DIR/install-schtasks.sh"
                    log "已生成安装脚本，请运行 bash $SCRIPT_DIR/install-schtasks.sh"
                    ;;
                *)
                    warn "暂不支持该系统的定时任务配置"
                    ;;
            esac
            ;;
        2)
            log "跳过定时任务配置，可随时手动执行：python3 $TARGET_DIR/nwu-attendance.py"
            ;;
        *)
            warn "无效选择"
            ;;
    esac

    log "签到脚本已安装到 $TARGET_DIR"
    log "配置文件：$TARGET_DIR/config.json"
}

# ---------- 2) 校园网自动登录 ----------
setup_netlogin() {
    echo ""
    echo -e "${CYAN}--- 校园网自动登录 ---${NC}"
    echo -e "  将 $PROJECT_NAME/nwunet-autologin 复制到本机并配置"
    echo ""

    # 目标目录
    case "$OS" in
        mac)
            TARGET_DIR=$(ask "登录脚本存放目录（Mac 推荐 ~/Library/Application Support/nwu-toolkit）" \
                "$HOME_DIR/Library/Application Support/nwu-toolkit")
            ;;
        linux)
            TARGET_DIR=$(ask "登录脚本存放目录（Linux 推荐 /usr/local/bin）" "/usr/local/bin")
            ;;
        windows)
            TARGET_DIR=$(ask "登录脚本存放目录（Windows 推荐 C:\nwu-toolkit）" "C:\nwu-toolkit")
            ;;
        *)
            TARGET_DIR=$(ask "登录脚本存放目录" "$HOME_DIR/nwu-toolkit")
            ;;
    esac

    mkdir -p "$TARGET_DIR"

    # 复制脚本
    cp "$SCRIPT_DIR/nwunet-autologin" "$TARGET_DIR/nwunet-autologin"
    cp "$SCRIPT_DIR/nwunet-autologin.init" "$TARGET_DIR/nwunet-autologin.init"
    cp "$SCRIPT_DIR/nwunet.conf.example" "$TARGET_DIR/nwunet.conf"
    chmod +x "$TARGET_DIR/nwunet-autologin"

    # 配置
    echo ""
    echo -e "  开始配置 $TARGET_DIR/nwunet.conf"
    sed -i "s/^USERNAME=.*/USERNAME=$(ask '校园网账号（学号）' 'YOUR_STUDENT_ID')/" "$TARGET_DIR/nwunet.conf"
    sed -i "s/^PASSWORD=.*/PASSWORD=$(ask '校园网密码（身份证后6位）' 'YOUR_PASSWORD')/" "$TARGET_DIR/nwunet.conf"
    sed -i "s/^INTERVAL=.*/INTERVAL=$(ask '检测间隔（秒）' '30')/" "$TARGET_DIR/nwunet.conf"

    chmod 600 "$TARGET_DIR/nwunet.conf"

    # 验证
    echo ""
    echo -e "  测试登录（不修改配置，只验证连通性）"
    if command -v curl &>/dev/null; then
        if curl -s -m 5 --connect-timeout 3 "$PORTAL/eportal/portal/page/loadConfig?callback=dr1" 2>/dev/null | grep -q '"code"'; then
            log "认证服务器可达"
        else
            warn "认证服务器不可达，请检查网络或 PORTAL 地址"
        fi
    fi

    log "校园网登录脚本已安装到 $TARGET_DIR"
    log "配置文件：$TARGET_DIR/nwunet.conf"
}

# ---------- 3) LuCI 网页版 ----------
setup_luci() {
    echo ""
    echo -e "${CYAN}--- LuCI 网页版（OpenWrt 路由器） ---${NC}"
    echo -e "  将 $PROJECT_NAME/luci-app-nwu-toolkit 部署到路由器"
    echo ""

    echo -e "  请先确保："
    echo -e "    1) 路由器是 OpenWrt / ImmortalWrt"
    echo -e "    2) 能 SSH 登录路由器（ssh root@<路由器IP>）"
    echo -e "    3) 路由器上有 curl/ca-bundle/jsonfilter"
    echo ""

    echo -e "  部署方式："
    echo -e "  1) 直接部署（推荐）：sh install.sh root@<路由器IP>"
    echo -e "  2) 编译 ipk 包：把目录放进 OpenWrt SDK 的 package/ 下"
    echo ""
    echo -n -e "  请选择 [1-2]: ${NC}"
    read -r method

    case "$method" in
        1)
            echo -n -e "  请输入路由器地址（如 root@192.168.5.1）: ${NC}"
            read -r host
            if [[ -z "$host" ]]; then
                err "路由器地址不能为空"
                return 1
            fi
            if [[ ! -f "$SCRIPT_DIR/luci-app-nwu-toolkit/install.sh" ]]; then
                err "未找到 install.sh"
                return 1
            fi
            cp "$SCRIPT_DIR/luci-app-nwu-toolkit/install.sh" "$TARGET_DIR/../install.sh" 2>/dev/null || true
            echo ""
            echo -e "  请手动在本地运行："
            echo -e "    sh $SCRIPT_DIR/luci-app-nwu-toolkit/install.sh $host"
            log "部署命令已生成"
            ;;
        2)
            echo -e "  请将 $SCRIPT_DIR/luci-app-nwu-toolkit 目录放入 OpenWrt SDK 的 package/ 下，然后运行："
            echo -e "    make package/luci-app-nwu-toolkit/compile V=s"
            log "编译说明已生成"
            ;;
        *)
            warn "无效选择"
            ;;
    esac
}

# ---------- 4) 查看状态 ----------
show_status() {
    echo ""
    echo -e "${CYAN}--- 当前状态 ---${NC}"
    echo ""

    # 签到
    echo "  [晚点名签到]"
    if [ -f "$HOME_DIR/Library/Application Support/nwu-toolkit/config.json" ]; then
        echo "    配置文件: $HOME_DIR/Library/Application Support/nwu-toolkit/config.json"
        python3 -c "
import json, sys
cfg = json.load(open('$HOME_DIR/Library/Application Support/nwu-toolkit/config.json'))
print(f'    学号: {cfg.get(\"student_id\", cfg.get(\"sid\", \"\"))}')
print(f'    姓名: {cfg.get(\"name\", \"\")}')
print(f'    位置: {cfg.get(\"lat\", \"\")}, {cfg.get(\"lng\", \"\")}')
print(f'    Bark: {\"已配置\" if cfg.get(\"bark_key\") else \"未配置\"}')
" 2>/dev/null || echo "    无法读取配置"
    elif [ -f "/opt/nwu-toolkit/config.json" ]; then
        echo "    配置文件: /opt/nwu-toolkit/config.json"
        python3 -c "
import json
cfg = json.load(open('/opt/nwu-toolkit/config.json'))
print(f'    学号: {cfg.get(\"student_id\", cfg.get(\"sid\", \"\"))}')
print(f'    姓名: {cfg.get(\"name\", \"\")}')
print(f'    位置: {cfg.get(\"lat\", \"\"), cfg.get(\"lng\", \"\")}')
print(f'    Bark: {\"已配置\" if cfg.get(\"bark_key\") else \"未配置\"}')
" 2>/dev/null || echo "    无法读取配置"
    else
        echo "    未安装"
    fi

    # 校园网
    echo ""
    echo "  [校园网自动登录]"
    if [ -f "$HOME_DIR/Library/Application Support/nwu-toolkit/nwunet.conf" ]; then
        echo "    配置文件: $HOME_DIR/Library/Application Support/nwu-toolkit/nwunet.conf"
        echo "    账号: $(grep '^USERNAME=' "$HOME_DIR/Library/Application Support/nwu-toolkit/nwunet.conf" | cut -d= -f2)"
    elif [ -f "/usr/local/bin/nwunet-autologin" ] || [ -f "/opt/nwu-toolkit/nwunet.conf" ]; then
        echo "    配置文件: /opt/nwu-toolkit/nwunet.conf"
        echo "    账号: $(grep '^USERNAME=' /opt/nwu-toolkit/nwunet.conf 2>/dev/null | cut -d= -f2)"
    else
        echo "    未安装"
    fi
}

# ---------- 5) 卸载 ----------
uninstall() {
    echo ""
    echo -e "${CYAN}--- 卸载 ---${NC}"
    echo ""
    echo -n -e "  确定要卸载所有 NWU 工具吗？（y/N）: ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "取消卸载"
        return 0
    fi

    # 卸载签到
    case "$OS" in
        mac)
            launchctl bootout gui/$(id -u)/com.miniguo.nwu-attendance.checkin 2>/dev/null || true
            rm -f "$HOME_DIR/Library/LaunchAgents/com.miniguo.nwu-attendance.checkin.plist"
            ;;
        linux)
            crontab -l 2>/dev/null | grep -v "nwu-attendance" | crontab - 2>/dev/null || true
            ;;
    esac

    # 删除文件
    rm -rf "$HOME_DIR/Library/Application Support/nwu-toolkit"
    rm -rf "/opt/nwu-toolkit"
    rm -rf "$HOME_DIR/nwu-toolkit"

    log "已卸载"
}

# ---------- 6) 帮助 ----------
show_help() {
    echo ""
    echo -e "${CYAN}=== 帮助 ===${NC}"
    echo ""
    echo "  晚点名签到（nwu-attendance.py）"
    echo "    python3 nwu-attendance.py --init     交互式初始化"
    echo "    python3 nwu-attendance.py            立即签到"
    echo "    python3 nwu-attendance.py --wait     等待开放后签到"
    echo "    python3 nwu-attendance.py --status   查看状态"
    echo ""
    echo "  校园网自动登录（nwunet-autologin）"
    echo "    ./nwunet-autologin                   常驻运行，断网自动重登"
    echo "    ./nwunet-autologin once              只检测并尝试登录一次"
    echo ""
    echo "  配置文件"
    echo "    config.json          签到配置（学号、姓名、Bark key 等）"
    echo "    nwunet.conf          校园网配置（账号、密码、检测间隔）"
    echo ""
    echo "  更多说明请查看 README.md"
    echo "  仓库地址: $REPO_URL"
}

# ---------- 主循环 ----------
main() {
    echo -e "${CYAN}=== NWU 校园网与晚点名自动化工具 ===${NC}"
    echo -e "  系统: $OS | 目录: $SCRIPT_DIR"
    echo ""

    while true; do
        choice=$(show_menu)
        case "$choice" in
            1) setup_attendance ;;
            2) setup_netlogin ;;
            3) setup_luci ;;
            4) show_status ;;
            5) uninstall ;;
            6) show_help ;;
            7) echo -e "  ${GREEN}再见！${NC}"; exit 0 ;;
            *) err "无效选择，请重新输入" ;;
        esac
        echo ""
        echo -n -e "  ${CYAN}按回车键继续...${NC}"
        read -r _
    done
}

main
