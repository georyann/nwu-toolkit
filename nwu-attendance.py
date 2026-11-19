#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""西北大学地质学系 · 晚点名自动签到（仅依赖 Python 标准库）

用法:
    python3 nwu-attendance.py --init         # 交互式初始化：终端里输入学号、姓名、Bark key 等
    python3 nwu-attendance.py                # 立刻签到一次
    python3 nwu-attendance.py --wait         # 若未到时段，等到 21:00 开放后自动签到
    python3 nwu-attendance.py --wait --jitter 600   # 开放后随机延迟 0–600 秒再提交（定时任务用）
    python3 nwu-attendance.py --status       # 只查看签到状态，不提交
    python3 nwu-attendance.py --config a.json

配置文件 config.json（与本脚本同目录，或用 --config 指定）:
{
  "student_id": "学号",
  "name": "姓名",
  "phone": "",          // 选填
  "id_card": "",        // 选填（身份证号）
  "lat": 34.14522,      // 签到时留痕的位置（默认西北大学长安校区）
  "lng": 108.87618,
  "bark_key": ""        // Bark 推送 key（App 里 https://api.day.app/xxxx 的 xxxx）
}

旧版字段名（sid / idc / bark）仍可兼容读取。
"""

import argparse
import json
import random
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

BASE = "https://xddz.nwu.edu.cn"
UA_HINT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) nwu-attendance"
TZ = timezone(timedelta(hours=8))
HERE = Path(__file__).resolve().parent
CAMPUS = {"name": "西北大学长安校区", "lat": 34.14522, "lng": 108.87618}


def log(msg):
    print(f"[{datetime.now(TZ):%Y-%m-%d %H:%M:%S}] {msg}", flush=True)


_SSL_CTX = None


# 常见 CA 证书包位置：OpenWrt/Debian、Alpine、RHEL 系
_CA_FILES = ("/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/cert.pem",
             "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/ca-bundle.pem")


def ssl_context():
    """按可用性挑 CA：certifi → 常见系统证书包 → 系统默认；
    全都为空时（常见于未装 ca-bundle 的 OpenWrt）降级为不校验并告警。"""
    global _SSL_CTX
    if _SSL_CTX is not None:
        return _SSL_CTX
    candidates = []
    try:
        import certifi
        candidates.append(certifi.where())
    except Exception:
        pass
    candidates.extend(_CA_FILES)
    for path in candidates:
        try:
            ctx = ssl.create_default_context(cafile=path)
            if ctx.get_ca_certs():
                _SSL_CTX = ctx
                return _SSL_CTX
        except Exception:
            continue
    ctx = ssl.create_default_context()
    if not ctx.get_ca_certs():
        log("警告：未找到 CA 证书，HTTPS 不校验（建议安装 ca-bundle）")
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    _SSL_CTX = ctx
    return _SSL_CTX


def open_url(target, timeout):
    return urllib.request.urlopen(target, timeout=timeout, context=ssl_context())


def http_json(path, body=None, timeout=20, retries=3):
    """请求 JSON 接口，网络异常时有限次重试。"""
    data = None
    headers = {"Accept": "application/json", "Cache-Control": "no-store"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    last_err = None
    for i in range(retries):
        req = urllib.request.Request(BASE + path, data=data, headers=headers,
                                     method="POST" if data else "GET")
        try:
            with open_url(req, timeout) as r:
                raw = r.read().decode("utf-8", "replace")
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                raise RuntimeError(f"服务端返回非 JSON（HTTP {r.status}）: {raw[:200]}")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, RuntimeError) as e:
            last_err = e
            if i < retries - 1:
                time.sleep(2 * (i + 1))
    raise RuntimeError(f"无法连接打卡服务：{last_err}")


def load_json(path, default):
    try:
        return json.loads(path.read_text("utf-8"))
    except FileNotFoundError:
        return default
    except json.JSONDecodeError:
        raise SystemExit(f"配置文件格式有误：{path}")


def save_json(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), "utf-8")


def compat(cfg):
    """兼容旧版字段名（sid / idc / bark），迁移到新版后删除。"""
    if cfg.get("sid") and not cfg.get("student_id"):
        cfg["student_id"] = cfg["sid"]
    if cfg.get("idc") and not cfg.get("id_card"):
        cfg["id_card"] = cfg["idc"]
    if cfg.get("bark") and not cfg.get("bark_key"):
        cfg["bark_key"] = cfg["bark"]
    if cfg.get("dev_rand") and not cfg.get("device_rand"):
        cfg["device_rand"] = cfg["dev_rand"]
        del cfg["dev_rand"]
    return cfg


def describe_location(lat, lng):
    """把经纬度翻译成人能读的位置描述。"""
    if not (isinstance(lat, (int, float)) and isinstance(lng, (int, float))):
        return "未上报位置"
    dy = (lat - CAMPUS["lat"]) * 111.0
    dx = (lng - CAMPUS["lng"]) * 111.0 * 0.829  # 34°N 处经度每度的距离
    dist = (dx * dx + dy * dy) ** 0.5 * 1000
    where = CAMPUS["name"] if dist <= 3000 else "自定义位置"
    return f"{where}（{lat:.5f}, {lng:.5f}，±50m）"


def config_summary(cfg, meta=None):
    """把本次使用的配置整理成推送里好读的文本。"""
    sid = str(cfg.get("student_id", cfg.get("sid", ""))).strip()
    name = str(cfg.get("name", "")).strip()
    lines = [f"签到人：{name}（{sid}）",
             f"位置：{describe_location(cfg.get('lat'), cfg.get('lng'))}"]
    win = (meta or {}).get("win")
    if win:
        lines.append(f"时段：{win[0]}–{win[1]}（北京时间）")
    if cfg.get("phone") or cfg.get("id_card"):
        lines.append("联系方式：已随卡提交（不在推送中显示）")
    return "\n".join(lines)


def interactive_init(cfg_path):
    """终端交互式初始化配置，直接回车保留旧值/默认值。"""
    old = load_json(cfg_path, {})
    print("=== 西北大学晚点名签到 · 初始化 ===")
    print("提示：直接回车 = 保留当前值或使用默认值\n")

    def ask(label, default=""):
        cur = f" [{default}]" if default not in ("", None) else ""
        val = input(f"{label}{cur}：").strip()
        return val if val else str(default or "")

    while True:
        sid = ask("学号", old.get("student_id", old.get("sid", "")))
        if len(sid) >= 4:
            break
        print("  学号至少 4 位，请重新输入")
    while True:
        name = ask("姓名（须与学籍一致）", old.get("name", ""))
        if len(name) >= 2:
            break
        print("  姓名至少 2 个字，请重新输入")

    phone = ask("手机号（选填）", old.get("phone", ""))
    idc = ask("身份证号（选填，仅辅导员联络用）", old.get("id_card", old.get("idc", "")))
    bark = ask("Bark 推送 key（选填，api.day.app/<key> 里的 key）",
               old.get("bark_key", old.get("bark", "")))

    print("\n签到位置：1) 西北大学长安校区（默认）  2) 自定义经纬度")
    sel = ask("选择", "1")
    if sel == "2":
        def ask_float(label, default):
            while True:
                raw = ask(label, f"{default:.5f}" if isinstance(default, (int, float)) else "")
                try:
                    return float(raw)
                except ValueError:
                    print("  请输入数字，例如 34.14522")
        lat = ask_float("纬度", old.get("lat"))
        lng = ask_float("经度", old.get("lng"))
    else:
        lat, lng = CAMPUS["lat"], CAMPUS["lng"]

    cfg = {
        "student_id": sid, "name": name, "phone": phone, "id_card": idc,
        "lat": lat, "lng": lng, "bark_key": bark,
        "bark_server": str(old.get("bark_server") or "https://api.day.app"),
    }
    save_json(cfg_path, cfg)
    cfg_path.chmod(0o600)
    print(f"\n已写入 {cfg_path}（权限 600）")
    print("-" * 40)
    print(config_summary(cfg))
    print("推送：" + ("已配置 Bark" if bark else "未配置，将不推送"))
    print("-" * 40)
    print("下一步：python3 nwu-attendance.py --status 查看状态，python3 nwu-attendance.py 立即签到")


def bark_notify(cfg, title, body):
    """用 Bark 推送到手机；未配置 key 或推送失败都不影响签到本身。"""
    key = str(cfg.get("bark_key") or cfg.get("bark") or "").strip().strip("/")
    if not key:
        log("未配置 Bark key，跳过推送")
        return
    server = str(cfg.get("bark_server") or "https://api.day.app").rstrip("/")
    q = urllib.parse.quote
    url = (f"{server}/{key}/{q(title)}/{q(body)}"
           f"?group={q('晚点名签到')}&level=active&isArchive=1")
    for i in range(3):
        try:
            with open_url(url, 12) as r:
                j = json.loads(r.read().decode("utf-8", "replace"))
            if j.get("code") == 200:
                log("Bark 推送已送达")
            else:
                log(f"Bark 推送返回异常：{j}")
            return
        except Exception as e:
            if i < 2:
                log(f"Bark 推送第 {i + 1} 次失败，{2 * (i + 1)} 秒后重试：{e}")
                time.sleep(2 * (i + 1))
            else:
                log(f"Bark 推送失败（不影响签到）：{e}")


def device_id(state, state_path): #稳定的设备号
    rand = state.get("device_rand")
    if not rand:
        rand = uuid.uuid4().hex[:14]
        state["device_rand"] = rand
        save_json(state_path, state)
    s = f"{rand}|{UA_HINT}|0x0|24|zh-CN|-480"
    h = 5381
    for ch in s:
        h = ((h << 5) + h + ord(ch)) & 0xFFFFFFFF
    return format(h, "x")


def get_meta():
    return http_json("/__rc/meta")


def phase_text(meta):
    return {
        "open": "签到进行中",
        "before": "尚未开始",
        "after": "今日签到已结束",
        "day": "今日无需签到",
    }.get(meta.get("phase"), "晚点名未开启")


def show_status(meta, state):
    log(f"服务端状态：{phase_text(meta)}（{meta.get('now')} 北京时间）")
    log(f"签到时段：{meta.get('win', ['?', '?'])[0]} – {meta.get('win', ['?', '?'])[1]}"
        f" · 模式：{'全域（不限地点）' if meta.get('mode') == 'open' else '围栏（须在校区）'}")
    last = state.get("last")
    if last:
        log(f"本机上次签到：{last.get('time')} · {last.get('result')}")


def wait_for_window():
    """阻塞到签到开放；期间每 5 分钟复查一次服务端状态。"""
    while True:
        meta = get_meta()
        if meta.get("phase") == "open":
            return meta
        if not meta.get("on"):
            log("晚点名当前未开启，10 分钟后复查…")
            time.sleep(600)
            continue
        target = meta.get("startTs")
        delay = max(0, int(target / 1000 - time.time())) if target else 0
        if not target or delay <= 0:
            log("尚未到开放时间，10 分钟后复查…")
            time.sleep(600)
            continue
        log(f"距签到开放还有 {delay // 60} 分钟，等待中…")
        # 分段睡，保证中途配置/服务状态变化能及时反映
        while delay > 0:
            step = min(delay, 300)
            time.sleep(step)
            delay -= step
            if delay > 0:
                m = get_meta()
                if m.get("phase") == "open":
                    return m
                if not m.get("on"):
                    break
        # 循环回到顶部重新判断


def do_checkin(cfg, state, state_path, meta):
    sid = str(cfg.get("student_id", cfg.get("sid", "")).strip())
    name = str(cfg.get("name", "")).strip()
    if not sid or not name:
        raise SystemExit("请先在 config.json 里填写 student_id（学号）和 name（姓名）")

    dev = device_id(state, state_path)

    # 1) 绑定：已有同一学号的有效令牌就跳过
    saved = state.get("bind") or {}
    tok = saved.get("tok") if saved.get("sid") == sid else None
    if not tok:
        body = {"sid": sid, "name": name, "dev": dev}
        if meta.get("collect"):
            if cfg.get("phone"):
                body["phone"] = str(cfg["phone"]).strip()
            if cfg.get("id_card"):
                body["id_card"] = str(cfg["id_card"]).strip()
            if body.get("phone") or body.get("id_card"):
                body["consent"] = True
        try:
            j = http_json("/__rc/bind", body)
        except RuntimeError as e:
            log(f"绑定请求失败：{e}")
            j = None
        if j and j.get("ok"):
            tok = j.get("tok")
            state["bind"] = {"sid": sid, "tok": tok}
            save_json(state_path, state)
            log("身份绑定成功" + ("（已绑定过本机）" if j.get("rebind") else ""))
        else:
            # 与网页「无法绑定？仍然直接打卡」一致：绑定失败仍尝试提交
            code = (j or {}).get("code", "net")
            log(f"绑定未通过（{code}：{(j or {}).get('msg', '')}），尝试直接打卡…")

    # 2) 打卡
    body = {"sid": sid, "name": name, "dev": dev, "ua": "other"}
    if tok:
        body["tok"] = tok
    lat, lng = cfg.get("lat"), cfg.get("lng")
    if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
        body.update({"lat": lat, "lng": lng, "acc": 50})

    j = http_json("/__rc/checkin", body)

    if j.get("ok"):
        loc = f" · 定位 {lat:.5f},{lng:.5f}（±50m）" if body.get("lat") is not None else ""
        log(f"✓ 打卡成功 · {j.get('ms', '')} · 核验方式 {j.get('v', '')}"
            + (f" · 区域 {j['zone']}" if j.get("zone") else "") + loc)
        ok = True
        result = f"成功（{j.get('ms', '')}）"
        notify_body = (f"{j.get('ms', '')} · {j.get('v', '')}"
                       + (f" · {j['zone']}" if j.get("zone") else "")
                       + "\n" + config_summary(cfg, meta))
        bark_notify(cfg, "✓ 晚点名打卡成功", notify_body)
    else:
        code = j.get("code", "")
        msg = j.get("msg", "")
        if code == "dup":
            log("今日已打卡，无需重复提交")
            ok, result = True, "已打卡（重复提交）"
            bark_notify(cfg, "晚点名：今日已打卡",
                        "今日已打卡，无需重复提交\n" + config_summary(cfg, meta))
        else:
            hint = {
                "devonce": "一台设备一天只能为一人打卡，请换用自己的手机/网络",
                "out": f"不在有效区域（还差约 {j.get('dist', '?')} 米）",
                "acc": "定位精度不足，可稍后重试",
                "gps": "定位无效",
            }.get(code, "")
            log(f"✗ 打卡未通过（{code}）：{msg}" + (f" · {hint}" if hint else ""))
            ok, result = False, f"失败（{code}）"
            bark_notify(cfg, "✗ 晚点名打卡失败",
                        f"{msg}" + (f"\n{hint}" if hint else "")
                        + "\n" + config_summary(cfg, meta) + f"\n错误码：{code}")

    state["last"] = {"time": datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S"), "result": result}
    save_json(state_path, state)
    return ok


def main():
    ap = argparse.ArgumentParser(description="西北大学晚点名自动签到")
    ap.add_argument("--config", default=str(HERE / "config.json"), help="配置文件路径")
    ap.add_argument("--state", default=str(HERE / "state.json"), help="运行状态文件路径")
    ap.add_argument("--init", action="store_true", help="交互式初始化配置（输入学号、姓名等）")
    ap.add_argument("--status", action="store_true", help="只查看状态，不签到")
    ap.add_argument("--wait", action="store_true", help="未到时段时等待开放后签到")
    ap.add_argument("--jitter", type=int, default=0, metavar="SEC",
                    help="开放后随机延迟 0~SEC 秒再提交（降低整点集中，定时任务用）")
    args = ap.parse_args()

    cfg_path, state_path = Path(args.config), Path(args.state)
    if args.init:
        interactive_init(cfg_path)
        return 0

    cfg = load_json(cfg_path, {})
    state = load_json(state_path, {})
    if not cfg_path.exists() or not str(cfg.get("student_id", cfg.get("sid", "")).strip()):
        log(f"尚未配置：{cfg_path}，请先运行 python3 nwu-attendance.py --init")
        return 1

    meta = get_meta()
    if args.status:
        show_status(meta, state)
        return 0

    if meta.get("phase") != "open":
        if not args.wait:
            log(f"当前不可打卡：{phase_text(meta)}")
            return 0
        log(f"当前不可打卡：{phase_text(meta)}，等待开放…")
        meta = wait_for_window()

    if args.jitter > 0:
        delay = random.randint(0, args.jitter)
        if delay:
            log(f"随机延迟 {delay} 秒后提交")
            time.sleep(delay)

    ok = do_checkin(cfg, state, state_path, meta)
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except SystemExit:
        raise
    except Exception as e:  # 兜底，保证定时任务能看到明确原因
        log(f"运行出错：{e}")
        sys.exit(1)