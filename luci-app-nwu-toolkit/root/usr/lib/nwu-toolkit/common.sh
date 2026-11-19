#!/bin/sh
# luci-app-nwu-toolkit 公共函数（仅依赖 busybox / curl / jsonfilter）

NWU_LOG="${NWU_LOG:-/var/log/nwu-toolkit.log}"
NWU_STATE_DIR="${NWU_STATE_DIR:-/var/run/nwu-toolkit}"
NWU_DATA_DIR="${NWU_DATA_DIR:-/etc/nwu-toolkit}"
NWU_LOG_MAX="${NWU_LOG_MAX:-262144}"

nwu_init_dirs() {
	mkdir -p "$NWU_STATE_DIR/daka" "$NWU_DATA_DIR/daka" 2>/dev/null
	chmod 700 "$NWU_STATE_DIR" "$NWU_DATA_DIR" 2>/dev/null
}

# 写日志并按大小截断，避免长期运行撑爆 /var
nwu_log() {
	local ts size
	ts=$(date '+%Y-%m-%d %H:%M:%S')
	mkdir -p "${NWU_LOG%/*}" 2>/dev/null
	printf '[%s] %s\n' "$ts" "$*" >>"$NWU_LOG" 2>/dev/null
	logger -t nwu-toolkit "$*" 2>/dev/null
	size=$(wc -c <"$NWU_LOG" 2>/dev/null)
	if [ "${size:-0}" -gt "$NWU_LOG_MAX" ]; then
		tail -c $((NWU_LOG_MAX / 2)) "$NWU_LOG" >"$NWU_LOG.tmp" 2>/dev/null &&
			mv "$NWU_LOG.tmp" "$NWU_LOG"
	fi
}

nwu_get() { # key default
	local v
	v=$(uci -q get "nwu-toolkit.$1" 2>/dev/null)
	if [ -z "$v" ]; then printf '%s' "$2"; else printf '%s' "$v"; fi
}

nwu_bool() { # section.option
	case "$(uci -q get "nwu-toolkit.$1" 2>/dev/null)" in
		1|on|true|yes|enabled) return 0 ;;
	esac
	return 1
}

nwu_sections() { # type
	uci -q show nwu-toolkit 2>/dev/null |
		sed -n "s/^nwu-toolkit\.\([^.=]*\)=$1$/\1/p"
}

# 列表项（账号 / 打卡用户）的启用判断，未显式填写时默认启用
nwu_list_enabled() { # section
	local v
	v=$(uci -q get "nwu-toolkit.$1.enabled" 2>/dev/null)
	if [ -z "$v" ]; then return 0; fi
	case "$v" in
		1|on|true|yes|enabled) return 0 ;;
	esac
	return 1
}

# 转义成可直接放进 JSON 字符串的内容（换行压成空格）
nwu_json_escape() {
	printf '%s' "$1" | tr -d '\r' | tr '\n' ' ' |
		sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
		awk 'BEGIN { ORS = "" } { gsub(/\t/, "\\t"); print }'
}

nwu_uint() { # key default
	local v
	v=$(nwu_get "$1" "$2")
	case "$v" in
		''|*[!0-9]*) v="$2" ;;
	esac
	printf '%s' "$v"
}

nwu_is_number() {
	case "$1" in
		''|*[!0-9.eE+-]*) return 1 ;;
	esac
	printf '%s' "$1" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'
}

nwu_rand_hex() { # bytes
	od -An -N "${1:-7}" -tx1 -v /dev/urandom 2>/dev/null | tr -d ' \n'
}

nwu_rand_range() { # 0..max
	local n=0 b
	for b in $(od -An -N4 -tu1 -v /dev/urandom 2>/dev/null); do
		n=$(( (n * 256 + b) & 0x7FFFFFFF ))
	done
	[ "${1:-0}" -le 0 ] && { echo 0; return 0; }
	echo $(( n % ( $1 + 1 ) ))
}

# 与 daka.py 一致的 djb2（32 位）设备指纹
nwu_dev_hash() {
	local h=5381 b
	for b in $(printf '%s' "$1" | od -An -tu1 -v); do
		h=$(( (h * 33 + b) & 0xFFFFFFFF ))
	done
	printf '%x' "$h"
}

nwu_urlencode() {
	printf '%s' "$1" | od -An -tu1 -v | awk '
		{
			for (i = 1; i <= NF; i++) {
				b = $i + 0
				c = sprintf("%c", b)
				if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) ||
				    (b >= 97 && b <= 122) || c == "-" || c == "_" ||
				    c == "." || c == "~")
					printf "%s", c
				else
					printf "%%%02X", b
			}
		}'
}

# 请求 JSON 接口，失败重试 3 次；成功时把响应体输出到 stdout
nwu_http_json() { # url body ua [timeout]
	local url="$1" body="$2" ua="${3:-nwu-toolkit}" tmo="${4:-20}" i=1 resp
	while [ "$i" -le 3 ]; do
		if [ -n "$body" ]; then
			resp=$(curl -sS -f -m "$tmo" --connect-timeout 5 \
				-H 'Accept: application/json' \
				-H 'Cache-Control: no-store' \
				-H 'Content-Type: application/json; charset=utf-8' \
				-H "User-Agent: $ua" \
				--data-binary "$body" "$url" 2>/dev/null)
		else
			resp=$(curl -sS -f -m "$tmo" --connect-timeout 5 \
				-H 'Accept: application/json' \
				-H 'Cache-Control: no-store' \
				-H "User-Agent: $ua" "$url" 2>/dev/null)
		fi
		if [ -n "$resp" ]; then
			printf '%s' "$resp"
			return 0
		fi
		[ "$i" -lt 3 ] && sleep $((i * 2))
		i=$((i + 1))
	done
	return 1
}

nwu_json_get() { # jsonpath json
	printf '%s' "$2" | jsonfilter -e "$1" 2>/dev/null
}

nwu_file_json_get() { # file jsonpath
	[ -r "$1" ] || return 0
	jsonfilter -e "$2" <"$1" 2>/dev/null
}

# 目录锁，带陈旧锁清理
nwu_lock() { # lockdir
	local pid
	if mkdir "$1" 2>/dev/null; then
		echo $$ >"$1/pid"
		return 0
	fi
	pid=$(cat "$1/pid" 2>/dev/null)
	if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
		rm -rf "$1"
		if mkdir "$1" 2>/dev/null; then
			echo $$ >"$1/pid"
			return 0
		fi
	fi
	return 1
}

nwu_unlock() { # lockdir
	rm -rf "$1" 2>/dev/null
}

nwu_service_running() { # 关键字
	if command -v pgrep >/dev/null 2>&1; then
		pgrep -f "nwu-$1" >/dev/null 2>&1
		return $?
	fi
	ps w 2>/dev/null | grep -q "[n]wu-$1" ||
		ps 2>/dev/null | grep -q "[n]wu-$1"
}
