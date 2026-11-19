#!/bin/sh
# 直接部署到已运行的 OpenWrt / ImmortalWrt 路由器
# 用法: sh install.sh root@192.168.1.1

set -e

HOST="${1:?用法: sh install.sh root@<路由器地址>}"
DIR=$(cd "$(dirname "$0")" && pwd)

echo "→ 上传程序到 $HOST"
# 用 tar 保持目录结构（不覆盖已有配置）
tar -C "$DIR/root" --exclude ./etc/config/nwu-toolkit -cf - . | ssh "$HOST" 'tar -xf - -C /'
tar -C "$DIR/htdocs" -cf - . | ssh "$HOST" 'tar -xf - -C /www'
scp "$DIR/root/etc/config/nwu-toolkit" "$HOST:/tmp/nwu-toolkit.default"

echo "→ 设置权限并启动服务"
ssh "$HOST" 'sh -s' <<'EOF'
set -e
chmod +x /usr/bin/nwu-netlogin /usr/bin/nwu-daka /usr/libexec/rpcd/nwu-toolkit
chmod +x /etc/init.d/nwu-netlogin /etc/init.d/nwu-daka
chmod +x /etc/uci-defaults/90_luci-app-nwu-toolkit
[ -f /etc/config/nwu-toolkit ] || cp /tmp/nwu-toolkit.default /etc/config/nwu-toolkit
mkdir -p /etc/nwu-toolkit/daka
chmod 700 /etc/nwu-toolkit
/etc/init.d/nwu-netlogin enable
/etc/init.d/nwu-daka enable
/etc/init.d/nwu-netlogin restart
/etc/init.d/nwu-daka restart
/etc/init.d/rpcd reload
rm -f /tmp/nwu-toolkit.default
echo "完成。请退出并重新登录 LuCI，菜单才会刷新。"
EOF
