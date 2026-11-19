include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nwu-toolkit
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=miniguo

LUCI_TITLE:=LuCI 校园网自动登录与晚点名自动打卡
LUCI_DESCRIPTION:=Dr.COM 校园网多账号自动认证（定期检测、失败切换、按周期换号）+ 晚点名多用户自动打卡（独立位置/UA/推送，支持汇总推送）。
LUCI_DEPENDS:=+curl +ca-bundle +jsonfilter
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/nwu-toolkit
endef

# 源文件在部分开发环境下不带可执行位，安装后统一修正
define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod +x /usr/bin/nwu-netlogin /usr/bin/nwu-daka \
	/usr/libexec/rpcd/nwu-toolkit \
	/etc/init.d/nwu-netlogin /etc/init.d/nwu-daka \
	/etc/uci-defaults/90_luci-app-nwu-toolkit 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
