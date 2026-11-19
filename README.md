# NWU 校园网与晚点名自动化工具

> 西北大学（NWU）校园网 Dr.COM 自动登录 + 晚点名自动签到，一套工具，多端可用。

## 功能

### 1. 晚点名签到（`nwu-attendance.py`）

- Python 标准库实现，**无需 pip 安装任何依赖**
- 与网页版一致：`/__rc/meta` → `/__rc/bind` 绑定令牌 → `/__rc/checkin` 提交
- 未到时段自动等待，开放后随机延迟提交（降低整点集中）
- 签到结果推送 Bark（支持 `--init` 交互式配置）
- 设备指纹稳定复用，多用户不冲突
- 支持 Mac（launchd）、Linux（crontab）、Windows（任务计划程序）

### 2. 校园网自动登录（`nwunet-autologin`）

- Shell 脚本，仅依赖 curl
- 断网自动重登，认证服务器自动探测
- 多账号容错：失败自动尝试下一个
- OpenWrt procd 守护，开机自启

### 3. LuCI 网页版（`luci-app-nwu-toolkit`）

- 纯 Shell + curl + jsonfilter，**不需要 Python**
- 集成「校园网自动登录」和「晚点名打卡」到 LuCI 页面
- 多用户独立配置（学号/姓名/位置/UA/Bark）
- 支持 OpenWrt / ImmortalWrt，apk / opkg 双包管理器

## 快速开始

### 一键配置

```bash
bash setup.sh
```

运行后会出现菜单：

```
=== NWU 校园网与晚点名自动化工具 ===
  1) 安装/配置 晚点名签到
  2) 安装/配置 校园网自动登录
  3) 安装/配置 LuCI 网页版（OpenWrt 路由器）
  4) 查看当前状态
  5) 卸载
  6) 帮助
  7) 退出
```

选择对应数字，按提示输入学号、姓名、Bark key 等即可。

### 手动部署

**Mac**

```bash
# 1. 复制脚本
cp nwu-attendance.py ~/Library/Application\ Support/nwu-toolkit/
cp config.example.json ~/Library/Application\ Support/nwu-toolkit/config.json

# 2. 初始化（终端里填学号、姓名、Bark key）
python3 ~/Library/Application\ Support/nwu-toolkit/nwu-attendance.py --init

# 3. 安装定时任务
bash install-nwu-attendance.sh
```

**Linux**

```bash
# 1. 复制脚本
cp nwu-attendance.py /opt/nwu-toolkit/
cp config.example.json /opt/nwu-toolkit/config.json

# 2. 初始化
python3 /opt/nwu-toolkit/nwu-attendance.py --init

# 3. 安装 crontab
bash install-cron.sh
```

**Windows**

```powershell
# 1. 复制脚本到 C:\nwu-toolkit
# 2. 初始化
python3 C:\nwu-toolkit\nwu-attendance.py --init
# 3. 使用任务计划程序（见 install-schtasks.sh）
```

**OpenWrt 路由器（LuCI 网页版）**

```bash
# 直接部署
sh install.sh root@192.168.5.1

# 或编译 ipk
make package/luci-app-nwu-toolkit/compile V=s
```

## 配置说明

### 晚点名签到

`config.json`

```json
{
  "student_id": "YOUR_STUDENT_ID",
  "name": "YOUR_NAME",
  "phone": "",
  "id_card": "",
  "lat": 34.14522,
  "lng": 108.87618,
  "bark_key": "YOUR_BARK_KEY",
  "bark_server": "https://api.day.app"
}
```

| 字段 | 说明 |
|---|---|
| `student_id` | 学号（必填） |
| `name` | 姓名（必填，须与学籍一致） |
| `phone` | 手机号（选填） |
| `id_card` | 身份证号（选填） |
| `lat`, `lng` | 签到位置（默认长安校区，支持自定义） |
| `bark_key` | Bark 推送 key（选填） |

### 校园网自动登录

`nwunet.conf`

```
USERNAME="YOUR_STUDENT_ID"
PASSWORD="YOUR_PASSWORD"
PORTAL="http://172.30.9.18:801"
PORTAL_DOMAIN="http://calogin.nwu.edu.cn:801"
INTERVAL=30
```

## 命令参考

### 晚点名签到

```bash
python3 nwu-attendance.py --init        # 交互式初始化
python3 nwu-attendance.py               # 立即签到
python3 nwu-attendance.py --wait        # 等待开放后签到
python3 nwu-attendance.py --wait --jitter 600   # 开放后随机延迟 0~600 秒
python3 nwu-attendance.py --status      # 只查看状态，不签到
python3 nwu-attendance.py --config a.json   # 指定配置文件
```

### 校园网自动登录

```bash
./nwunet-autologin                      # 常驻运行，断网自动重登
./nwunet-autologin once                 # 只检测并尝试登录一次
```

## 文件说明

```
nwu-toolkit/
├── nwu-attendance.py           # 晚点名签到（Python）
├── config.example.json         # 签到配置示例
├── config.json                 # 签到配置（生成）
├── state.json                  # 运行状态（生成）
├── nwunet-autologin            # 校园网自动登录（Shell）
├── nwunet.conf.example         # 校园网配置示例
├── nwunet-autologin.init       # OpenWrt init 脚本
├── setup.sh                    # 一键配置脚本
├── install-nwu-attendance.sh   # Mac launchd 安装
├── install-cron.sh             # Linux crontab 安装
├── install-schtasks.sh         # Windows 任务计划安装
├── install.sh                  # LuCI 直接部署
├── README.md                   # 说明文档
├── LICENSE
├── .gitignore
└── luci-app-nwu-toolkit/       # LuCI 网页版
    ├── Makefile
    ├── README.md
    ├── install.sh
    ├── root/                   # 程序文件
    └── htdocs/                 # 前端文件
```

## 注意事项

- **IP 与位置**：签到时上报的坐标是长安校区，但服务端会记录来源 IP。在家庭宽带运行意味着 IP 为本地宽带，与服务端记录的「长安校区」不一致，这是固有限制。
- **设备指纹**：脚本使用固定 UA + 随机串生成设备号，换电脑/删 `state.json` 会生成新设备号。
- **同一 IP 每天只能为一人打卡**，多人使用请确保各自 IP 不同。
- 配置文件权限必须 600，避免被其他进程读取。

## 许可

MIT License