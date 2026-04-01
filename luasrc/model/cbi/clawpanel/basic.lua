-- luci-app-clawpanel — 基本设置 CBI Model
local sys = require "luci.sys"

m = Map("clawpanel", "ClawPanel AI 管理面板",
	"ClawPanel 是一个 OpenClaw 智能管理面板，支持进程管理、通道配置、插件管理等功能。")

m.pageaction = false

-- 状态面板
m:section(SimpleSection).template = "clawpanel/status"

-- 快捷操作
s3 = m:section(SimpleSection, nil, "快捷操作")
s3.template = "cbi/nullsection"

act = s3:option(DummyValue, "_actions")
act.rawhtml = true
act.cfgvalue = function(self, section)
	local ctl_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "service_ctl")
	local log_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "setup_log")
	local check_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "check_update")
	local uninstall_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "uninstall")
	local check_system_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "check_system")
	local mounts_url = luci.dispatcher.build_url("admin", "services", "clawpanel", "mounts")

	local q = "'"

	local html = {}
	html[#html+1] = '<div style="display:flex;gap:10px;flex-wrap:wrap;margin:10px 0;">'
	html[#html+1] = '<button class="btn cbi-button cbi-button-apply" type="button" onclick="cpShowSetupDialog()" id="btn-setup" title="下载并安装 ClawPanel">📦 安装/重装</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(' .. q .. 'restart' .. q .. ')">🔄 重启服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(' .. q .. 'stop' .. q .. ')">⏹️ 停止服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(' .. q .. 'start' .. q .. ')">▶️ 启动服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpCheckUpdate()">🔍 检测升级</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-remove" type="button" onclick="cpUninstall()" id="btn-uninstall" title="卸载 ClawPanel">🗑️ 卸载</button>'
	html[#html+1] = '</div>'
	html[#html+1] = '<div id="action-result" style="margin-top:8px;"></div>'

	-- 安装对话框
	html[#html+1] = '<div id="cp-setup-dialog" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);z-index:10000;align-items:center;justify-content:center;">'
	html[#html+1] = '<div style="background:#fff;border-radius:12px;padding:24px 28px;max-width:520px;width:92%;box-shadow:0 8px 32px rgba(0,0,0,0.2);">'
	html[#html+1] = '<h3 style="margin:0 0 16px 0;font-size:16px;color:#333;">📦 安装 ClawPanel</h3>'

	-- 版本选项
	html[#html+1] = '<div style="display:flex;flex-direction:column;gap:12px;margin-bottom:16px;">'
	html[#html+1] = '<label style="display:flex;align-items:flex-start;gap:10px;padding:14px 16px;border:2px solid #4a90d9;border-radius:8px;cursor:pointer;background:#f0f7ff;">'
	html[#html+1] = '<input type="radio" name="cp-ver-choice" value="latest" checked style="margin-top:2px;">'
	html[#html+1] = '<div><strong>🆕 最新版 (推荐)</strong><div style="font-size:12px;color:#666;margin-top:4px;">自动获取 GitHub 最新版本</div></div>'
	html[#html+1] = '</label>'
	html[#html+1] = '<label style="display:flex;align-items:flex-start;gap:10px;padding:14px 16px;border:2px solid #e0e0e0;border-radius:8px;cursor:pointer;">'
	html[#html+1] = '<input type="radio" name="cp-ver-choice" value="custom" style="margin-top:2px;">'
	html[#html+1] = '<div><strong>🔢 指定版本</strong>'
	html[#html+1] = '<div style="margin-top:4px;"><input type="text" id="cp-custom-version" placeholder="如: 5.3.3" style="padding:6px 10px;border:1px solid #d0d7de;border-radius:4px;font-size:13px;width:100%;"></div></div>'
	html[#html+1] = '</label>'
	html[#html+1] = '</div>'

	-- 安装路径
	html[#html+1] = '<div style="border-top:1px solid #eee;padding-top:14px;">'
	html[#html+1] = '<div style="font-weight:600;font-size:13px;color:#333;margin-bottom:8px;">📂 安装路径 <span style="color:#cf222e;font-weight:normal;">（必须选择外置存储）</span></div>'
	html[#html+1] = '<div id="cp-mount-list" style="display:flex;flex-direction:column;gap:8px;margin-bottom:8px;">'
	html[#html+1] = '<div style="color:#888;font-size:12px;">⏳ 正在检测可用存储...</div>'
	html[#html+1] = '</div>'
	html[#html+1] = '<div id="cp-custom-path-wrap" style="display:none;margin-top:8px;">'
	html[#html+1] = '<div style="font-size:12px;color:#666;margin-bottom:4px;">📝 自定义路径:</div>'
	html[#html+1] = '<input type="text" id="cp-install-path" value="" style="width:100%;padding:8px 12px;border:1px solid #d0d7de;border-radius:6px;font-size:13px;" placeholder="/mnt/sda1">'
	html[#html+1] = '</div>'
	html[#html+1] = '<div id="cp-path-warning" style="font-size:11px;color:#cf222e;margin-top:6px;display:none;"></div>'
	html[#html+1] = '</div>'

	-- 按钮
	html[#html+1] = '<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:20px;">'
	html[#html+1] = '<button class="btn cbi-button" type="button" onclick="cpCloseSetupDialog()">取消</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-apply" type="button" onclick="cpConfirmSetup()" id="cp-confirm-btn">开始安装</button>'
	html[#html+1] = '</div></div></div>'

	-- 安装日志
	html[#html+1] = '<div id="setup-log-panel" style="display:none;margin-top:12px;">'
	html[#html+1] = '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">'
	html[#html+1] = '<span id="setup-log-title" style="font-weight:600;font-size:14px;">📋 安装日志</span>'
	html[#html+1] = '<span id="setup-log-status" style="font-size:12px;color:#999;"></span>'
	html[#html+1] = '</div>'
	html[#html+1] = '<pre id="setup-log-content" style="background:#1a1b26;color:#a9b1d6;padding:14px 16px;border-radius:6px;font-size:12px;line-height:1.6;max-height:400px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;border:1px solid #2d333b;margin:0;"></pre>'
	html[#html+1] = '<div id="setup-log-result" style="margin-top:10px;display:none;"></div>'
	html[#html+1] = '</div>'

	-- JS
	html[#html+1] = '<script type="text/javascript">'

	html[#html+1] = 'function cpShowSetupDialog(){'
	html[#html+1] = 'document.getElementById(' .. q .. 'cp-setup-dialog' .. q .. ').style.display=' .. q .. 'flex' .. q .. ';'
	html[#html+1] = 'cpLoadMounts();'
	html[#html+1] = '}'
	html[#html+1] = 'function cpCloseSetupDialog(){'
	html[#html+1] = 'document.getElementById(' .. q .. 'cp-setup-dialog' .. q .. ').style.display=' .. q .. 'none' .. q .. ';'
	html[#html+1] = '}'

	-- 加载挂载点
	html[#html+1] = 'var _cpSelectedMount=' .. q .. q .. ';'
	html[#html+1] = 'function cpLoadMounts(){'
	html[#html+1] = 'var el=document.getElementById(' .. q .. 'cp-mount-list' .. q .. ');'
	html[#html+1] = 'if(!el)return;'
	html[#html+1] = "el.innerHTML='<div style=\"color:#888;font-size:12px;\">⏳ 正在检测存储设备...</div>';"
	html[#html+1] = "(new XHR()).get(" .. q .. mounts_url .. q .. ",null,function(x){"
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(!r.mounts||r.mounts.length===0){'
	html[#html+1] = "el.innerHTML='<div style=\"color:#e36209;font-size:12px;\">⚠️ 未检测到外置存储<br/><span style=\"color:#888;font-size:11px;\">请先在「系统 → 挂载点」中挂载 USB 硬盘后重试。</span></div>';"
	html[#html+1] = 'document.getElementById(' .. q .. 'cp-custom-path-wrap' .. q .. ').style.display=' .. q .. 'block' .. q .. ';'
	html[#html+1] = '}else{'
	html[#html+1] = "var h='<div style=\"font-size:12px;color:#888;margin-bottom:6px;\">⬇️ 选择安装位置（推荐第一个）：</div>';"
	html[#html+1] = 'r.mounts.forEach(function(m,i){'
	html[#html+1] = 'var chk=i===0?' .. q .. 'checked' .. q .. ':' .. q .. q .. ';'
	html[#html+1] = 'var rec=i===0?' .. q .. ' <span style=\"background:#1a7f37;color:#fff;padding:1px 6px;border-radius:3px;font-size:10px;\">推荐</span>' .. q .. ':' .. q .. q .. ';'
	html[#html+1] = 'var bg=i===0?' .. q .. '#f0f7ff' .. q .. ':' .. q .. '#fff' .. q .. ';'
	html[#html+1] = 'var bdr=i===0?' .. q .. '#4a90d9' .. q .. ':' .. q .. '#e0e0e0' .. q .. ';'
	html[#html+1] = 'var ac=m.avail_mb>=500?' .. q .. '#1a7f37' .. q .. ':' .. q .. '#e36209' .. q .. ';'
	html[#html+1] = "h+='<label style=\"display:flex;align-items:flex-start;gap:8px;padding:10px 12px;border:2px solid '+bdr+';border-radius:8px;cursor:pointer;background:'+bg+';margin-bottom:8px;\">';"
	html[#html+1] = "h+='<input type=\"radio\" name=\"cp-mount\" value=\"'+m.mount+'\" style=\"margin-top:2px;\" '+chk+' onclick=\"cpSelectMount(\\'\\'+m.mount+'\\'\\)\">';"
	html[#html+1] = "h+='<div><strong>'+m.mount+'</strong>'+rec+'<div style=\"font-size:11px;color:#666;margin-top:2px;\">可用: <span style=\"color:'+ac+';font-weight:600;\">'+m.size+'</span> | '+m.fs+'</div></div>';"
	html[#html+1] = "h+='</label>';"
	html[#html+1] = '});'
	html[#html+1] = 'el.innerHTML=h;'
	html[#html+1] = 'if(r.mounts.length>0){_cpSelectedMount=r.mounts[0].mount;document.getElementById(' .. q .. 'cp-install-path' .. q .. ').value=_cpSelectedMount;}';
	html[#html+1] = 'document.getElementById(' .. q .. 'cp-custom-path-wrap' .. q .. ').style.display=' .. q .. 'block' .. q .. ';'
	html[#html+1] = '}'
	html[#html+1] = '}catch(e){'
	html[#html+1] = "el.innerHTML='<div style=\"color:#cf222e;font-size:12px;\">⚠️ 检测失败</div>';"
	html[#html+1] = '}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	html[#html+1] = 'function cpSelectMount(p){_cpSelectedMount=p;document.getElementById(' .. q .. 'cp-install-path' .. q .. ').value=p;}'

	-- 确认安装
	html[#html+1] = 'function cpConfirmSetup(){'
	html[#html+1] = 'var path=document.getElementById(' .. q .. 'cp-install-path' .. q .. ').value.trim();'
	html[#html+1] = 'if(!path){alert(' .. q .. '请选择或输入安装路径' .. q .. ');return;}'
	html[#html+1] = 'var dangerous=[' .. q .. '/overlay' .. q .. ',' .. q .. '/rom' .. q .. ',' .. q .. '/boot' .. q .. ',' .. q .. '/proc' .. q .. ',' .. q .. '/sys' .. q .. ',' .. q .. '/dev' .. q .. ',' .. q .. '/opt' .. q .. ',' .. q .. '/tmp' .. q .. ',' .. q .. '/var' .. q .. ',' .. q .. '/etc' .. q .. ',' .. q .. '/root' .. q .. ',' .. q .. '/usr' .. q .. ',' .. q .. '/bin' .. q .. ',' .. q .. '/sbin' .. q .. ',' .. q .. '/lib' .. q .. ',' .. q .. '/' '  .. q .. '];'
	html[#html+1] = 'var isSys=false;'
	html[#html+1] = 'dangerous.forEach(function(d){if(path===d||path.indexOf(d+'/')===0)isSys=true;});'
	html[#html+1] = 'if(isSys){alert(' .. q .. '错误：禁止安装到系统分区！请选择外置存储挂载点。' .. q .. ');return;}'
	html[#html+1] = 'var radios=document.getElementsByName(' .. q .. 'cp-ver-choice' .. q .. ');'
	html[#html+1] = 'var choice=' .. q .. 'latest' .. q .. ';'
	html[#html+1] = 'for(var i=0;i<radios.length;i++){if(radios[i].checked){choice=radios[i].value;break;}}'
	html[#html+1] = 'var version=' .. q .. q .. ';'
	html[#html+1] = 'if(choice===' .. q .. 'custom' .. q .. '){version=document.getElementById(' .. q .. 'cp-custom-version' .. q .. ').value.trim();}'
	html[#html+1] = "var btn=document.getElementById('cp-confirm-btn');"
	html[#html+1] = "btn.disabled=true;btn.textContent='⏳ 准备安装...';"
	html[#html+1] = "document.getElementById('setup-log-panel').style.display='block';"
	html[#html+1] = "var logEl=document.getElementById('setup-log-content');"
	html[#html+1] = "var statusEl=document.getElementById('setup-log-status');"
	html[#html+1] = "var resultEl=document.getElementById('setup-log-result');"
	html[#html+1] = "resultEl.style.display='none';"
	html[#html+1] = "logEl.textContent='════════════════════════════════════════\\n🔍 系统检测\\n════════════════════════════════════════\\n安装路径: '+path+'\\n⏳ 检测中...\\n';"
	html[#html+1] = "statusEl.innerHTML='<span style=\"color:#7aa2f7;\">⏳ 系统检测中...</span>';"
	html[#html+1] = 'cpCloseSetupDialog();'
	html[#html+1] = "(new XHR()).get(" .. q .. check_system_url .. "?install_path=" .. "'+encodeURIComponent(path),null,function(x){"
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = "var memOk=r.memory_ok?'✅':'❌';"
	html[#html+1] = "var diskOk=r.disk_ok?'✅':'❌';"
	html[#html+1] = "logEl.textContent+='内存: '+r.memory_mb+' MB (需≥256MB) — '+memOk+'\\n';"
	html[#html+1] = "logEl.textContent+='磁盘: '+r.disk_mb+' MB 可用 (需≥500MB) — '+diskOk+'\\n';"
	html[#html+1] = 'if(!r.pass){'
	html[#html+1] = "btn.disabled=false;btn.textContent='开始安装';"
	html[#html+1] = "statusEl.innerHTML='<span style=\"color:#cf222e;\">❌ 不满足条件</span>';"
	html[#html+1] = "logEl.textContent+='❌ 系统不满足安装条件\\n';"
	html[#html+1] = 'return;'
	html[#html+1] = '}'
	html[#html+1] = "logEl.textContent+='✅ 检测通过，开始安装...\\n\\n';"
	html[#html+1] = 'var vp=version?' .. q .. '&version=' .. "'+encodeURIComponent(version):'';"
	html[#html+1] = "(new XHR()).get(" .. q .. ctl_url .. "?action=setup&install_path=" .. "'+encodeURIComponent(path)+vp,null,function(x){try{JSON.parse(x.responseText);}catch(e){}});"
	html[#html+1] = 'cpPollSetupLog();'
	html[#html+1] = '}catch(e){btn.disabled=false;btn.textContent=' .. q .. '开始安装' .. q .. ';}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	-- 轮询日志
	html[#html+1] = 'var _t=null;var _lastLen=0;'
	html[#html+1] = 'function cpPollSetupLog(){'
	html[#html+1] = 'if(_t)clearInterval(_t);'
	html[#html+1] = '_t=setInterval(function(){'
	html[#html+1] = "(new XHR()).get(" .. q .. log_url .. q .. ",null,function(x){"
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = "var logEl=document.getElementById('setup-log-content');"
	html[#html+1] = "var statusEl=document.getElementById('setup-log-status');"
	html[#html+1] = 'if(r.log){logEl.textContent=r.log;logEl.scrollTop=logEl.scrollHeight;}'
	html[#html+1] = 'if(r.state===' .. q .. 'running' .. q .. '){'
	html[#html+1] = "statusEl.innerHTML='<span style=\"color:#7aa2f7;\">⏳ 安装进行中...</span>';"
	html[#html+1] = '}else if(r.state===' .. q .. 'success' .. q .. '){'
	html[#html+1] = 'clearInterval(_t);_t=null;'
	html[#html+1] = "statusEl.innerHTML='<span style=\"color:#1a7f37;\">✅ 安装完成</span>';"
	html[#html+1] = "var resultEl=document.getElementById('setup-log-result');resultEl.style.display='block';"
	html[#html+1] = "resultEl.innerHTML='<div style=\"border:1px solid #c6e9c9;background:#e6f7e9;padding:12px 16px;border-radius:6px;\"><strong style=\"color:#1a7f37;\">🎉 安装成功！</strong><br/><span style=\"color:#555;\">请刷新页面，访问 http://IP:19527 开始使用。</span><br/><button class=\"btn cbi-button cbi-button-apply\" onclick=\"location.reload()\" style=\"margin-top:8px;\">🔄 刷新页面</button></div>';"
	html[#html+1] = '}else if(r.state===' .. q .. 'failed' .. q .. '){'
	html[#html+1] = 'clearInterval(_t);_t=null;'
	html[#html+1] = "statusEl.innerHTML='<span style=\"color:#cf222e;\">❌ 安装失败</span>';"
	html[#html+1] = '}'
	html[#html+1] = '}catch(e){}'
	html[#html+1] = '},2000);'
	html[#html+1] = '}'

	-- 服务控制
	html[#html+1] = 'function cpServiceCtl(a){'
	html[#html+1] = "var el=document.getElementById('action-result');"
	html[#html+1] = "el.innerHTML='<span style=\"color:#999\">⏳ 正在执行...</span>';"
	html[#html+1] = "(new XHR()).get(" .. q .. ctl_url .. "?action='+a,null,function(x){"
	html[#html+1] = 'try{if(JSON.parse(x.responseText).status===' .. q .. 'ok' .. q .. '){el.innerHTML=' .. q .. '<span style="color:green">✅ 已提交</span>' .. q .. ';}}catch(e){}'
	html[#html+1] = '});'
	html[#html+1] = 'setTimeout(' .. q .. 'location.reload()' .. q .. ',2000);'
	html[#html+1] = '}'

	-- 检测升级
	html[#html+1] = 'function cpCheckUpdate(){'
	html[#html+1] = "var el=document.getElementById('action-result');"
	html[#html+1] = "el.innerHTML='<span style=\"color:#999\">⏳ 检测中...</span>';"
	html[#html+1] = "(new XHR()).get(" .. q .. check_url .. q .. ",null,function(x){"
	html[#html+1] = 'try{var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(r.plugin_has_update){'
	html[#html+1] = "el.innerHTML='<span style=\"color:#e36209\">🔌 v'+r.plugin_current+' → v'+r.plugin_latest+' (有新版本)</span>';"
	html[#html+1] = '}else if(r.plugin_current){'
	html[#html+1] = "el.innerHTML='<span style=\"color:#1a7f37\">✅ 已是最快版本: v'+r.plugin_current+'</span>';"
	html[#html+1] = '}else{el.innerHTML='<span style=\"color:#999\">无法获取版本</span>';}'
	html[#html+1] = '}catch(e){el.innerHTML='<span style=\"color:red\">检测失败</span>';}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	-- 卸载
	html[#html+1] = 'function cpUninstall(){'
	html[#html+1] = 'if(!confirm(' .. q .. '确定卸载 ClawPanel？所有数据将被删除！' .. q .. '))return;'
	html[#html+1] = "var btn=document.getElementById('btn-uninstall');var el=document.getElementById('action-result');"
	html[#html+1] = "btn.disabled=true;btn.textContent='⏳ 卸载中...';"
	html[#html+1] = "el.innerHTML='<span style=\"color:#999\">正在清理...</span>';"
	html[#html+1] = "(new XHR()).get(" .. q .. uninstall_url .. q .. ",null,function(x){"
	html[#html+1] = 'try{var r=JSON.parse(x.responseText);'
	html[#html+1] = "btn.disabled=false;btn.textContent='🗑️ 卸载';"
	html[#html+1] = "el.innerHTML='<div style=\"border:1px solid #d0d7de;background:#f6f8fa;padding:12px 16px;border-radius:6px;\"><strong style=\"color:#1a7f37;\">✅ "+r.message+"</strong><br/><button class=\"btn cbi-button cbi-button-apply\" onclick=\"location.reload()\" style=\"margin-top:8px;\">🔄 刷新</button></div>';"
	html[#html+1] = '}catch(e){btn.disabled=false;btn.textContent='🗑️ 卸载';}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	html[#html+1] = '</script>'

	return table.concat(html, "")
end

-- 快捷入口
s4 = m:section(SimpleSection, nil)
s4.template = "cbi/nullsection"
guide = s4:option(DummyValue, "_guide")
guide.rawhtml = true
guide.cfgvalue = function()
	return '<div style="border:1px solid #d0e8ff;background:#f0f7ff;padding:14px 18px;border-radius:6px;margin-top:12px;line-height:1.8;font-size:13px;">' ..
		'<strong>📖 使用指南</strong><br/>' ..
		'① 点击上方 <b>「安装/重装」</b> 下载并安装 ClawPanel<br/>' ..
		'② 安装完成后访问 <b>http://路由器IP:19527</b><br/>' ..
		'③ 默认账号: <b>admin</b>，默认密码: <b>clawpanel</b></div>'
end

return m
