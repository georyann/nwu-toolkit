'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return uci.load('nwu-toolkit');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('nwu-toolkit', _('晚点名自动打卡'),
			_('每天到点后自动等待打卡开放并提交。每位用户可独立设置位置、UA 与推送方式；服务器按 UA 生成设备指纹，请勿与他人共用同一 UA。'));

		s = m.section(form.NamedSection, 'daka', 'daka', _('全局设置'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('启用自动打卡'));
		o.rmempty = false;

		o = s.option(form.Value, 'time', _('每日执行时间'));
		o.placeholder = '20:55';
		o.validate = function(section_id, value) {
			if (/^([01]\d|2[0-3]):[0-5]\d$/.test(value))
				return true;
			return _('格式应为 HH:MM，例如 20:55');
		};
		o.description = _('建议略早于开放时间（如 21:00 开放则填 20:55），脚本会自动等待开放。');

		o = s.option(form.Value, 'jitter', _('随机延迟（秒）'));
		o.datatype = 'uinteger';
		o.placeholder = '600';
		o.description = _('开放后随机等待 0–N 秒再提交，避免整点集中。');

		o = s.option(form.ListValue, 'push_mode', _('推送方式'));
		o.value('each', _('每人单独推送'));
		o.value('unified', _('全部完成后汇总推送'));
		o.value('both', _('两者都推'));
		o.value('off', _('不推送'));
		o.default = 'unified';

		o = s.option(form.Flag, 'switch_wifi', _('打卡前切换校园网账号'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('按每位用户填写的校园网账号先注销再登录，等出口 IP 变化后再打卡，避免多人共用同一 IP 被拒。切换期间暂停自动重登，结束后恢复。');

		o = s.option(form.Flag, 'switch_mac', _('按用户更换 WAN MAC'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('切号时把校园网 WiFi 的 MAC 临时改成该用户固定的随机地址（写入无线配置），确保服务器看到不同设备；全部完成后自动恢复原始 MAC。');

		o = s.option(form.Flag, 'reconnect', _('切号时重连 WiFi 换 IP'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('注销后先断开再重连 WAN，重新获取 DHCP 租约，确保出口 IP 变化后再打卡。每次约断网 10–20 秒。');

		o = s.option(form.Flag, 'restore', _('打卡后恢复默认账号'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('全部用户完成后，用“校园网自动登录”当前选中的账号重新登录。');

		o = s.option(form.Value, 'unified_bark', _('汇总推送 Bark Key'));
		o.placeholder = 'api.day.app 后的一串 key';
		o.description = _('“汇总推送”模式下，所有用户完成后发一条汇总消息。');

		o = s.option(form.Value, 'bark_server', _('Bark 服务器'));
		o.placeholder = 'https://api.day.app';
		o.default = 'https://api.day.app';

		o = s.option(form.Value, 'base', _('打卡服务地址'));
		o.placeholder = 'https://xddz.nwu.edu.cn';
		o.default = 'https://xddz.nwu.edu.cn';

		s = m.section(form.GridSection, 'user', _('打卡用户'),
			_('每位用户使用独立的设备随机数与 UA，互不影响。'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;

		o = s.option(form.Value, 'name', _('姓名'));
		o.rmempty = false;
		o.placeholder = '与学籍一致';

		o = s.option(form.Value, 'sid', _('学号'));
		o.rmempty = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'phone', _('手机号'));
		o.placeholder = '选填';
		o.modalonly = true;

		o = s.option(form.Value, 'idc', _('身份证号'));
		o.placeholder = '选填，仅辅导员联络用';
		o.modalonly = true;

		o = s.option(form.ListValue, 'loc_mode', _('打卡位置'));
		o.value('school', _('默认（西北大学长安校区附近 50m 漂移）'));
		o.value('custom', _('自行填写经纬度'));
		o.default = 'school';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('默认会在校区中心 50 米范围内随机偏移，避免每次坐标完全相同；选择“自行填写”后才使用下面的经纬度。');

		o = s.option(form.Value, 'lat', _('纬度'));
		o.placeholder = '34.14522';
		o.datatype = 'float';
		o.modalonly = true;
		o.depends('loc_mode', 'custom');

		o = s.option(form.Value, 'lng', _('经度'));
		o.placeholder = '108.87618';
		o.datatype = 'float';
		o.modalonly = true;
		o.depends('loc_mode', 'custom');

		o = s.option(form.Value, 'ua', _('User-Agent'));
		o.placeholder = '留空使用内置 UA';
		o.modalonly = true;
		o.description = _('同时用于生成设备指纹。留空则首次从内置 UA 池随机分配一个并固定保存，每个用户各不相同；也可手动填写。');

		o = s.option(form.Value, 'wifi_user', _('校园网账号'));
		o.placeholder = '本人的上网账号/学号';
		o.modalonly = true;
		o.description = _('打卡前会用此账号重新登录校园网，确保提交请求来自本人 IP。留空则沿用当前登录的账号。');

		o = s.option(form.Value, 'wifi_pass', _('校园网密码'));
		o.password = true;
		o.modalonly = true;
		o.description = _('与上面的账号配套；仅保存在本机 /etc/config/nwu-toolkit。');

		o = s.option(form.Flag, 'push', _('单独推送'));
		o.default = '1';
		o.modalonly = true;
		o.description = _('仅“每人单独推送 / 两者都推”模式下生效。');

		o = s.option(form.Value, 'bark', _('Bark Key'));
		o.placeholder = '每位用户各自的 key';
		o.modalonly = true;

		return m.render();
	}
});
