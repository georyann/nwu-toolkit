# luci-app-nwu-toolkit

把「校园网 Dr.COM 自动登录」和「晚点名自动打卡」整合到一个 LuCI 页面里，跑在 OpenWrt / ImmortalWrt 路由器上。

- 纯 shell + curl + jsonfilter 实现，**不需要 Python**，不占闪存
- procd 守护进程，开机自启、异常退出自动拉起
- 配置改动自动生效（守护进程每轮重新读取 UCI）

## 功能

### 校园网自动登录
- 按 `检测间隔` 定期调用 Dr.COM 认证接口，断线自动重登（接口幂等，重复登录不会踢掉会话）
- 多账号：任一账号失败可自动尝试下一个
- 定期换号：每 N 分钟轮换启用的账号，切换前先尝试注销旧会话
- 认证服务器自动探测：配置 IP → 被劫持响应 → 网关/校内已知地址

### 晚点名自动打卡
- 每天固定时间等待打卡开放，开放后随机延迟再提交
- 多用户：每人独立学号、姓名、经纬度、UA、Bark 推送
- 每人独立设备指纹（`dev_rand`），互不影响
- 推送：每人单独推送 / 全部完成后汇总推送 / 两者都推 / 不推送
- 自动绑定身份并缓存令牌，失败也会尝试直接打卡

## 安装

### 方式一：直接部署（推荐）

需要本机能 ssh 到路由器：

```sh
sh install.sh root@192.168.1.1
```

部署完成后退出并重新登录 LuCI，在「服务 → 校园网助手」中使用。

### 方式二：编译 ipk

把整个目录放进 OpenWrt SDK 的 `package/` 下：

```sh
make package/luci-app-nwu-toolkit/compile V=s
```

生成的包在 `bin/packages/*/base/`，上传到路由器后安装：

- apk 系统（ImmortalWrt 25.x / OpenWrt 24.10 之后的 snapshot）：`apk add --allow-untrusted luci-app-nwu-toolkit-*.apk`
- opkg 系统（23.05 / 24.10 正式版）：`opkg install luci-app-nwu-toolkit_*.ipk`

用哪个 SDK 编译，就得到对应格式的包，Makefile 不用改。

依赖：`curl`、`ca-bundle`、`jsonfilter`（一般均已安装，缺哪个装哪个）。

## 使用

### 1. 校园网自动登录
「校园网自动登录」页：

| 项 | 说明 |
| --- | --- |
| 启用自动登录 | 总开关 |
| 检测间隔 | 建议 60 秒 |
| 换号间隔 | 0 = 固定账号；>0 = 每 N 分钟轮换 |
| 登录失败时自动尝试下一个账号 | 多账号容错 |
| 认证服务器地址 | 默认 `http://172.30.9.18:801`（IP 直连，避免 DNS 被 Tailscale 等接管后解析失败） |
| 账号列表 | 可添加多个，勾选启用 |

### 2. 晚点名打卡
「晚点名打卡」页：

| 项 | 说明 |
| --- | --- |
| 每日执行时间 | 建议略早于开放时间，例如 20:55 |
| 随机延迟 | 开放后等 0–N 秒再提交，默认 600 |
| 推送方式 | 每人单独 / 汇总 / 两者 / 不推 |
| 打卡前切换校园网账号 | 默认开。按用户逐个注销→登录，等出口 IP 变化后再打卡 |
| 打卡后恢复默认账号 | 默认开。全部完成后用自动登录当前选中的账号重新上线 |
| 用户列表 | 姓名、学号、位置（校区 50m 漂移 / 自填经纬度）、UA、校园网账号/密码、Bark Key、是否单独推送 |

**重要：不同用户必须使用不同 UA。** 服务器按「设备随机数 + UA」生成设备指纹，如果多人共用同一 UA 会触发「一台设备一天只能为一人打卡」。用户没有手动填写 UA 时，程序会从内置的 10 个真实浏览器 UA 中随机分配一个并保存到 `/etc/nwu-toolkit/daka/<节名>.ua`，之后固定复用，且会尽量避开其他用户已占用的 UA。

**多人打卡必须切号。** 不同人登录校园网拿到的出口 IP 不同，服务端会按 IP 校验；同一 IP 连续为多人打卡会被拒绝。所以每位用户要填自己的校园网账号与密码，脚本在提交前会：注销当前账号 → 断开并重连 WAN 拿新 IP → 用本人账号登录 → 确认 IP 变化 → 打卡。切换期间会置位 `/var/run/nwu-toolkit/netlogin.hold`，自动重登守护进程暂停，避免把账号抢回去；全部完成后按需恢复默认账号。

> 改 MAC 必须用无线配置里的 `wireless.<wifi-iface>.macaddr`（LuCI：网络 → 无线 → 修改 → 高级设置 → MAC 地址），`network.<iface>.macaddr` 对 mt76 的 STA 接口无效。实测两者配合后每次都能拿到不同的 MAC 与 IP；全部完成后脚本会删除该选项、恢复原始 MAC 并重连。

### 3. 运行状态
「运行状态」页每 5 秒刷新，可查看当前账号、最近认证结果、每位用户的最近打卡结果与日志，并提供「立即认证 / 立即打卡 / 重启服务」按钮。

## 配置示例

`/etc/config/nwu-toolkit`：

```
config netlogin 'netlogin'
	option enabled '1'
	option interval '60'
	option switch_interval '90'
	option failover '1'

config account 'acc1'
	option enabled '1'
	option name '主账号'
	option username '20230001'
	option password '******'

config daka 'daka'
	option enabled '1'
	option time '20:55'
	option jitter '600'
	option push_mode 'unified'
	option unified_bark '你的BarkKey'

config user 'u1'
	option enabled '1'
	option name '张三'
	option sid '20230001'
	option lat '34.14522'
	option lng '108.87618'
	option push '1'
	option bark '张三的BarkKey'
	option wifi_user '张三的校园网账号'
	option wifi_pass '张三的校园网密码'
```

## 注意事项

- **时间**：路由器时区需为 `Asia/Shanghai`（`系统 → 系统 → 时区`），否则打卡时间会偏移。
- **DNS**：打卡服务使用 `https://xddz.nwu.edu.cn`，需要能正常解析域名；校园网认证默认走 IP 直连不受影响。
- **凭据**：账号密码与 Bark Key 保存在 `/etc/config/nwu-toolkit`，请确保路由器管理密码足够强，不要开启 LuCI 公网访问。
- **状态文件**：`/etc/nwu-toolkit/daka/*.json` 保存设备随机数与绑定令牌；删除后下次会重新绑定（可能被服务器判定为新设备）。
- **日志**：`/var/log/nwu-toolkit.log`，超过 256 KB 自动截断；也可 `logread -e nwu-toolkit`。
- 本工具仅在你自己的账号上执行登录与打卡，请遵守学校网络与考勤管理规定。
