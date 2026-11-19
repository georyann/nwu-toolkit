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

		m = new form.Map('nwu-toolkit', _('校园网自动登录'),
			_('定期检测并自动认证 Dr.COM 校园网。支持多账号、登录失败自动切换、按周期轮换账号。保存后一分钟内自动生效。'));

		s = m.section(form.NamedSection, 'netlogin', 'netlogin', _('全局设置'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('启用自动登录'));
		o.rmempty = false;

		o = s.option(form.Value, 'interval', _('检测间隔（秒）'));
		o.datatype = 'uinteger';
		o.placeholder = '60';
		o.description = _('每隔多少秒检测一次，断线会自动重新认证。建议 30–120 秒。');

		o = s.option(form.Value, 'switch_interval', _('换号间隔（分钟）'));
		o.datatype = 'uinteger';
		o.placeholder = '0';
		o.description = _('0 表示固定使用当前账号；大于 0 时按顺序轮换启用的账号。');

		o = s.option(form.Flag, 'failover', _('登录失败时自动尝试下一个账号'));
		o.default = '1';

		o = s.option(form.Value, 'portal', _('认证服务器地址'));
		o.placeholder = 'http://172.30.9.18:801';
		o.description = _('优先使用 IP 直连，避免路由器 DNS 被接管时解析失败。');

		o = s.option(form.Value, 'portal_domain', _('认证服务器域名'));
		o.placeholder = 'http://calogin.nwu.edu.cn:801';
		o.description = _('IP 地址不可用时的备用地址。');

		o = s.option(form.Value, 'ua', _('User-Agent'));
		o.placeholder = 'Mozilla/5.0 ...';

		s = m.section(form.GridSection, 'account', _('账号列表'),
			_('按顺序轮换。启用多个账号时会话按“换号间隔”切换。'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;

		o = s.option(form.Value, 'name', _('备注名'));
		o.placeholder = '主账号';

		o = s.option(form.Value, 'username', _('账号'));
		o.rmempty = false;
		o.placeholder = '学号或上网账号';

		o = s.option(form.Value, 'password', _('密码'));
		o.password = true;
		o.modalonly = true;
		o.rmempty = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		return m.render();
	}
});
