'use strict';
'require view';
'require rpc';
'require dom';
'require poll';
'require ui';

var callStatus = rpc.declare({
	object: 'nwu-toolkit',
	method: 'status',
	expect: {}
});

var callLog = rpc.declare({
	object: 'nwu-toolkit',
	method: 'log',
	params: [ 'lines' ],
	expect: {}
});

var callNetloginNow = rpc.declare({
	object: 'nwu-toolkit',
	method: 'netlogin_now',
	expect: {}
});

var callDakaNow = rpc.declare({
	object: 'nwu-toolkit',
	method: 'daka_now',
	params: [ 'section' ],
	expect: {}
});

var callRestart = rpc.declare({
	object: 'nwu-toolkit',
	method: 'restart',
	params: [ 'service' ],
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callLog(200) ]);
	},

	render: function(data) {
		var self = this;

		this.status = data[0] || {};
		this.logtext = (data[1] || {}).log || '';

		this.statusBox = E('div', {}, this.renderStatus(this.status));
		this.logBox = E('pre', {
			'style': 'max-height:360px;overflow:auto;white-space:pre-wrap;font-size:12px;margin:0'
		}, this.logtext);

		poll.add(L.bind(function() {
			return Promise.all([ callStatus(), callLog(200) ]).then(L.bind(function(res) {
				this.status = res[0] || {};
				this.logtext = (res[1] || {}).log || '';
				dom.content(this.statusBox, this.renderStatus(this.status));
				dom.content(this.logBox, this.logtext);
			}, this));
		}, this), 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('运行状态')),
			E('div', { 'class': 'cbi-map-descr' }, _('每 5 秒自动刷新。手动操作会在后台执行，结果见下方日志。')),
			this.statusBox,
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, _('运行日志')),
				this.logBox
			])
		]);
	},

	row: function(label, value) {
		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td', 'style': 'width:32%' }, label),
			E('td', { 'class': 'td' }, value)
		]);
	},

	badge: function(ok, on, off) {
		return E('span', { 'style': ok ? 'color:#2ca02c;font-weight:600' : 'color:#c0392b;font-weight:600' },
			ok ? on : off);
	},

	btn: function(text, style, handler) {
		return E('button', {
			'class': 'btn cbi-button cbi-button-' + style,
			'click': handler
		}, text);
	},

	renderStatus: function(d) {
		var self = this;
		var nl = d.netlogin || {}, dk = d.daka || {};
		var users = dk.user || [];

		var netResult = '-';
		if (nl.result === 'ok')
			netResult = [ this.badge(true, '✓ ', ''), nl.msg || '在线', '  ', nl.time || '' ];
		else if (nl.result === 'fail')
			netResult = [ this.badge(false, '✗ ', ''), nl.msg || '认证失败', '  ', nl.time || '' ];

		var userRows = [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('姓名')),
				E('th', { 'class': 'th' }, _('学号')),
				E('th', { 'class': 'th' }, _('最近打卡')),
				E('th', { 'class': 'th' }, _('结果')),
				E('th', { 'class': 'th' }, '')
			])
		];

		users.forEach(function(u) {
			userRows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, u.name || u.section),
				E('td', { 'class': 'td' }, u.sid || '-'),
				E('td', { 'class': 'td' }, u.last_time || '-'),
				E('td', { 'class': 'td' }, u.last_result || '-'),
				E('td', { 'class': 'td' }, this.btn(_('立即打卡'), 'action',
					ui.createHandlerFn(this, function() {
						return this.runAction(function() { return callDakaNow(u.section); },
							_('已触发打卡：') + (u.name || u.section));
					})))
			]));
		}, this);

		return E('div', {}, [
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, _('校园网自动登录')),
				E('table', { 'class': 'table' }, [
					this.row(_('服务状态'), this.badge(nl.running == 1, _('运行中'), _('未运行'))),
					this.row(_('功能开关'), nl.enabled == 1 ? _('已启用') : _('已停止')),
					this.row(_('当前账号'), (nl.account || '-') + (nl.user ? '（' + nl.user + '）' : '')),
					this.row(_('最近认证'), netResult),
					this.row(_('检测间隔'), (nl.interval || 60) + _(' 秒') +
						(nl.switch_interval > 0 ? _('，每 ') + nl.switch_interval + _(' 分钟换号') : _('，不换号'))),
					this.row(_('账号数量'), String(nl.accounts || 0))
				]),
				E('div', { 'style': 'margin-top:10px' }, [
					this.btn(_('立即认证'), 'action', ui.createHandlerFn(this, function() {
						return this.runAction(callNetloginNow, _('已触发校园网认证'));
					})),
					' ',
					this.btn(_('重启服务'), 'reset', ui.createHandlerFn(this, function() {
						return this.runAction(function() { return callRestart('netlogin'); }, _('校园网服务已重启'));
					}))
				])
			]),

			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, _('晚点名自动打卡')),
				E('table', { 'class': 'table' }, [
					this.row(_('服务状态'), this.badge(dk.running == 1, _('运行中'), _('未运行'))),
					this.row(_('功能开关'), dk.enabled == 1 ? _('已启用') : _('已停止')),
					this.row(_('每日计划'), (dk.time || '20:55') + _('，随机延迟 0–') + (dk.jitter || 0) + _(' 秒')),
					this.row(_('推送方式'), this.pushModeText(dk.push_mode)),
					this.row(_('今日已执行'), dk.today_done == 1 ? _('是') : _('否')),
					this.row(_('用户数量'), String(dk.users || 0))
				]),
				E('table', { 'class': 'table', 'style': 'margin-top:10px' }, userRows),
				E('div', { 'style': 'margin-top:10px' }, [
					this.btn(_('全部立即打卡'), 'action', ui.createHandlerFn(this, function() {
						return this.runAction(function() { return callDakaNow(''); }, _('已触发全部用户打卡'));
					})),
					' ',
					this.btn(_('重启服务'), 'reset', ui.createHandlerFn(this, function() {
						return this.runAction(function() { return callRestart('daka'); }, _('打卡服务已重启'));
					}))
				])
			])
		]);
	},

	pushModeText: function(mode) {
		switch (mode) {
		case 'each': return _('每人单独推送');
		case 'unified': return _('全部完成后汇总推送');
		case 'both': return _('两者都推');
		case 'off': return _('不推送');
		default: return mode || '-';
		}
	},

	runAction: function(fn, okmsg) {
		ui.showModal(_('请稍候…'), [
			E('p', { 'class': 'spinning' }, _('正在执行…'))
		]);

		return fn().then(L.bind(function() {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, okmsg), 'info');
			return this.refresh();
		}, this)).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, (e && e.message) || String(e)), 'danger');
		});
	},

	refresh: function() {
		return callStatus().then(L.bind(function(d) {
			this.status = d || {};
			dom.content(this.statusBox, this.renderStatus(this.status));
		}, this));
	}
});
