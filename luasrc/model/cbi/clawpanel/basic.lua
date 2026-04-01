-- luci-app-clawpanel — 基本设置 CBI Model
local sys = require "luci.sys"

m = Map("clawpanel", "ClawPanel AI 管理面板",
	"ClawPanel 是一个 OpenClaw 智能管理面板，支持进程管理、通道配置、插件管理等功能。")

m.pageaction = false

-- ═══════════════════════════════════════════
-- 状态面板
-- ═══════════════════════════════════════════
m:section(SimpleSection).template = "clawpanel/status"

-- ═══════════════════════════════════════════
-- 快捷操作
-- ═══════════════════════════════════════════
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
	local html = {}

	html[#html+1] = '<div style="display:flex;gap:10px;flex-wrap:wrap;margin:10px 0;">'
	html[#html+1] = '<button class="btn cbi-button cbi-button-apply" type="button" onclick="cpShowSetupDialog()" id="btn-setup" title="下载并安装 ClawPanel">📦 安装/重装</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(\'restart\')">🔄 重启服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(\'stop\')">⏹️ 停止服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpServiceCtl(\'start\')">▶️ 启动服务</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-action" type="button" onclick="cpCheckUpdate()">🔍 检测升级</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-remove" type="button" onclick="cpUninstall()" id="btn-uninstall" title="卸载 ClawPanel 及所有数据">🗑️ 卸载</button>'
	html[#html+1] = '</div>'
	html[#html+1] = '<div id="action-result" style="margin-top:8px;"></div>'

	-- 安装对话框
	html[#html+1] = '<div id="cp-setup-dialog" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);z-index:10000;align-items:center;justify-content:center;">'
	html[#html+1] = '<div style="background:#fff;border-radius:12px;padding:24px 28px;max-width:520px;width:92%;box-shadow:0 8px 32px rgba(0,0,0,0.2);">'
	html[#html+1] = '<h3 style="margin:0 0 16px 0;font-size:16px;color:#333;">📦 安装 ClawPanel</h3>'
	html[#html+1] = '<div style="display:flex;flex-direction:column;gap:12px;">'

	-- 最新版选项
	html[#html+1] = '<label style="display:flex;align-items:flex-start;gap:10px;padding:14px 16px;border:2px solid #4a90d9;border-radius:8px;cursor:pointer;background:#f0f7ff;" id="cp-opt-latest">'
	html[#html+1] = '<input type="radio" name="cp-ver-choice" value="latest" checked style="margin-top:2px;">'
	html[#html+1] = '<div><strong style="color:#333;">🆕 最新版 (推荐)</strong>'
	html[#html+1] = '<div style="font-size:12px;color:#666;margin-top:4px;">自动获取 GitHub 最新版本，涵盖最新功能与修复。</div>'
	html[#html+1] = '</div></label>'

	-- 指定版本选项
	html[#html+1] = '<label style="display:flex;align-items:flex-start;gap:10px;padding:14px 16px;border:2px solid #e0e0e0;border-radius:8px;cursor:pointer;background:#fff;" id="cp-opt-custom">'
	html[#html+1] = '<input type="radio" name="cp-ver-choice" value="custom" style="margin-top:2px;">'
	html[#html+1] = '<div><strong style="color:#333;">🔢 指定版本</strong>'
	html[#html+1] = '<div style="margin-top:4px;"><input type="text" id="cp-custom-version" placeholder="如: 5.3.3" style="padding:6px 10px;border:1px solid #d0d7de;border-radius:4px;font-size:13px;width:100%;"></div>'
	html[#html+1] = '</div></label>'

	html[#html+1] = '</div>'

	-- 安装路径
	html[#html+1] = '<div style="margin-top:16px;padding-top:14px;border-top:1px solid #eee;">'
	html[#html+1] = '<div style="font-weight:600;font-size:13px;color:#333;margin-bottom:8px;">📂 安装路径</div>'
	html[#html+1] = '<div style="display:flex;gap:8px;align-items:center;">'
	html[#html+1] = '<input type="text" id="cp-install-path" value="/opt" style="flex:1;padding:8px 12px;border:1px solid #d0d7de;border-radius:6px;font-size:13px;" placeholder="/opt">'
	html[#html+1] = '<button class="btn cbi-button" type="button" onclick="cpCheckDisk()" style="font-size:12px;padding:4px 10px;">检测空间</button>'
	html[#html+1] = '</div>'
	html[#html+1] = '<div id="cp-path-info" style="font-size:11px;color:#666;margin-top:6px;">💡 程序将在此路径下创建 clawpanel 目录。最小需要 500MB 可用空间。</div>'
	html[#html+1] = '</div>'

	-- 按钮
	html[#html+1] = '<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:20px;">'
	html[#html+1] = '<button class="btn cbi-button" type="button" onclick="cpCloseSetupDialog()" style="min-width:80px;">取消</button>'
	html[#html+1] = '<button class="btn cbi-button cbi-button-apply" type="button" onclick="cpConfirmSetup()" style="min-width:80px;">开始安装</button>'
	html[#html+1] = '</div>'
	html[#html+1] = '</div></div>'

	-- 安装日志面板
	html[#html+1] = '<div id="setup-log-panel" style="display:none;margin-top:12px;">'
	html[#html+1] = '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">'
	html[#html+1] = '<span id="setup-log-title" style="font-weight:600;font-size:14px;">📋 安装日志</span>'
	html[#html+1] = '<span id="setup-log-status" style="font-size:12px;color:#999;"></span>'
	html[#html+1] = '</div>'
	html[#html+1] = '<pre id="setup-log-content" style="background:#1a1b26;color:#a9b1d6;padding:14px 16px;border-radius:6px;font-size:12px;line-height:1.6;max-height:400px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;border:1px solid #2d333b;margin:0;"></pre>'
	html[#html+1] = '<div id="setup-log-result" style="margin-top:10px;display:none;"></div>'
	html[#html+1] = '</div>'

	-- JavaScript
	html[#html+1] = '<script type="text/javascript">'

	-- 版本选择对话框
	html[#html+1] = 'function cpShowSetupDialog(){'
	html[#html+1] = 'document.getElementById("cp-setup-dialog").style.display="flex";'
	html[#html+1] = 'var radios=document.getElementsByName("cp-ver-choice");'
	html[#html+1] = 'for(var i=0;i<radios.length;i++){if(radios[i].value==="latest")radios[i].checked=true;}'
	html[#html+1] = 'document.getElementById("cp-custom-version").value="";'
	html[#html+1] = '}'
	html[#html+1] = 'function cpCloseSetupDialog(){'
	html[#html+1] = 'document.getElementById("cp-setup-dialog").style.display="none";'
	html[#html+1] = '}'

	-- 检测磁盘空间
	html[#html+1] = 'function cpCheckDisk(){'
	html[#html+1] = 'var pathEl=document.getElementById("cp-install-path");'
	html[#html+1] = 'var infoEl=document.getElementById("cp-path-info");'
	html[#html+1] = 'var path=pathEl.value.trim()||"/opt";'
	html[#html+1] = 'infoEl.innerHTML="⏳ 正在检测空间...";'
	html[#html+1] = '(new XHR()).get("' .. check_system_url .. '?install_path="+encodeURIComponent(path),null,function(x){'
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(r.disk_ok){'
	html[#html+1] = 'infoEl.innerHTML="<span style=\"color:#1a7f37;\">✅ 可用空间: "+r.disk_free_str+" (检测路径: "+r.disk_path+")</span>";'
	html[#html+1] = '}else{'
	html[#html+1] = 'infoEl.innerHTML="<span style=\"color:#cf222e;\">❌ 空间不足: "+r.disk_mb+" MB 可用，需要 ≥ 500 MB (检测路径: "+r.disk_path+")</span>";'
	html[#html+1] = '}'
	html[#html+1] = '}catch(e){infoEl.innerHTML="<span style=\"color:#e36209;\">⚠️ 检测失败</span>";}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	-- 确认安装
	html[#html+1] = 'function cpConfirmSetup(){'
	html[#html+1] = 'var btn=document.getElementById("btn-setup");'
	html[#html+1] = 'var pathEl=document.getElementById("cp-install-path");'
	html[#html+1] = 'var installPath=pathEl.value.trim()||"/opt";'
	html[#html+1] = 'var radios=document.getElementsByName("cp-ver-choice");'
	html[#html+1] = 'var choice="latest";'
	html[#html+1] = 'for(var i=0;i<radios.length;i++){if(radios[i].checked){choice=radios[i].value;break;}}'
	html[#html+1] = 'var version="";'
	html[#html+1] = 'if(choice==="custom"){version=document.getElementById("cp-custom-version").value.trim();}'
	html[#html+1] = 'btn.disabled=true;btn.textContent="⏳ 准备安装...";'
	html[#html+1] = 'var panel=document.getElementById("setup-log-panel");'
	html[#html+1] = 'var logEl=document.getElementById("setup-log-content");'
	html[#html+1] = 'var statusEl=document.getElementById("setup-log-status");'
	html[#html+1] = 'var resultEl=document.getElementById("setup-log-result");'
	html[#html+1] = 'panel.style.display="block";resultEl.style.display="none";'
	html[#html+1] = 'logEl.textContent="";'
	html[#html+1] = 'statusEl.innerHTML="<span style=\"color:#7aa2f7;\">⏳ 系统检测中...</span>";'
	html[#html+1] = 'cpCloseSetupDialog();'
	html[#html+1] = '(new XHR()).get("' .. check_system_url .. '?install_path="+encodeURIComponent(installPath),null,function(x){'
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = 'logEl.textContent+="════════════════════════════════════════\\n";'
	html[#html+1] = 'logEl.textContent+="🔍 系统检测\\n";'
	html[#html+1] = 'logEl.textContent+="════════════════════════════════════════\\n";'
	html[#html+1] = 'logEl.textContent+="安装路径: "+installPath+"\\n";'
	html[#html+1] = 'logEl.textContent+="内存: "+r.memory_mb+" MB (需要 ≥ 256 MB) — "+(r.memory_ok?"✅":"❌")+"\\n";'
	html[#html+1] = 'logEl.textContent+="磁盘: "+r.disk_mb+" MB 可用 (需要 ≥ 500 MB) — "+(r.disk_ok?"✅":"❌")+"\\n";'
	html[#html+1] = 'logEl.textContent+="\\n";'
	html[#html+1] = 'if(!r.pass){'
	html[#html+1] = 'btn.disabled=false;btn.textContent="📦 安装/重装";'
	html[#html+1] = 'statusEl.innerHTML="<span style=\"color:#cf222e;\">❌ 不满足安装条件</span>";'
	html[#html+1] = 'logEl.textContent+="❌ 系统不满足安装条件，安装终止\\n";'
	html[#html+1] = 'return;'
	html[#html+1] = '}'
	html[#html+1] = 'logEl.textContent+="✅ 系统检测通过，开始安装...\\n\\n";'
	html[#html+1] = 'var verParam=version?"&version="+encodeURIComponent(version):"";'
	html[#html+1] = '(new XHR()).get("' .. ctl_url .. '?action=setup&install_path="+encodeURIComponent(installPath)+verParam,null,function(x){'
	html[#html+1] = 'try{JSON.parse(x.responseText);}catch(e){}'
	html[#html+1] = 'cpPollSetupLog();'
	html[#html+1] = '});'
	html[#html+1] = '}catch(e){'
	html[#html+1] = 'btn.disabled=false;btn.textContent="📦 安装/重装";'
	html[#html+1] = '}});'
	html[#html+1] = '}'

	-- 轮询安装日志
	html[#html+1] = 'var _cpSetupTimer=null;'
	html[#html+1] = 'var _lastLogLen=0;'
	html[#html+1] = 'function cpPollSetupLog(){'
	html[#html+1] = 'if(_cpSetupTimer)clearInterval(_cpSetupTimer);'
	html[#html+1] = '_lastLogLen=0;'
	html[#html+1] = '_cpSetupTimer=setInterval(function(){'
	html[#html+1] = '(new XHR()).get("' .. log_url .. '",null,function(x){'
	html[#html+1] = 'try{'
	html[#html+1] = 'var r=JSON.parse(x.responseText);'
	html[#html+1] = 'var logEl=document.getElementById("setup-log-content");'
	html[#html+1] = 'var statusEl=document.getElementById("setup-log-status");'
	html[#html+1] = 'if(r.log&&r.log.length>_lastLogLen){'
	html[#html+1] = 'var newLog=r.log.substring(_lastLogLen);'
	html[#html+1] = 'logEl.textContent+=newLog;'
	html[#html+1] = '_lastLogLen=r.log.length;'
	html[#html+1] = '}'
	html[#html+1] = 'logEl.scrollTop=logEl.scrollHeight;'
	html[#html+1] = 'if(r.state==="running"){'
	html[#html+1] = 'statusEl.innerHTML="<span style=\"color:#7aa2f7;\">⏳ 安装进行中...</span>";'
	html[#html+1] = '}else if(r.state==="success"){'
	html[#html+1] = 'clearInterval(_cpSetupTimer);_cpSetupTimer=null;'
	html[#html+1] = 'cpSetupDone(true);'
	html[#html+1] = '}else if(r.state==="failed"){'
	html[#html+1] = 'clearInterval(_cpSetupTimer);_cpSetupTimer=null;'
	html[#html+1] = 'cpSetupDone(false);'
	html[#html+1] = '}'
	html[#html+1] = '}catch(e){}'
	html[#html+1] = '});'
	html[#html+1] = '},2000);'
	html[#html+1] = '}'

	-- 安装完成处理
	html[#html+1] = 'function cpSetupDone(ok){'
	html[#html+1] = 'var btn=document.getElementById("btn-setup");'
	html[#html+1] = 'var statusEl=document.getElementById("setup-log-status");'
	html[#html+1] = 'var resultEl=document.getElementById("setup-log-result");'
	html[#html+1] = 'btn.disabled=false;btn.textContent="📦 安装/重装";'
	html[#html+1] = 'resultEl.style.display="block";'
	html[#html+1] = 'if(ok){'
	html[#html+1] = 'statusEl.innerHTML="<span style=\"color:#1a7f37;\">✅ 安装完成</span>";'
	html[#html+1] = 'resultEl.innerHTML="<div style=\"border:1px solid #c6e9c9;background:#e6f7e9;padding:12px 16px;border-radius:6px;\">"+"'
	html[#html+1] = '"<strong style=\"color:#1a7f37;font-size:14px;\">🎉 ClawPanel 安装成功！</strong><br/>"+"'
	html[#html+1] = '"<span style=\"color:#555;font-size:13px;\">请刷新页面查看最新状态，并访问 http://IP:19527 开始使用。</span><br/>"+"'
	html[#html+1] = '"<button class=\"btn cbi-button cbi-button-apply\" type=\"button\" onclick=\"location.reload()\" style=\"margin-top:10px;\">🔄 刷新页面</button></div>";'
	html[#html+1] = '}else{'
	html[#html+1] = 'statusEl.innerHTML="<span style=\"color:#cf222e;\">❌ 安装失败</span>";'
	html[#html+1] = 'resultEl.innerHTML="<div style=\"border:1px solid #f5c6cb;background:#ffeef0;padding:12px 16px;border-radius:6px;\">"+"'
	html[#html+1] = '"<strong style=\"color:#cf222e;font-size:14px;\">❌ 安装失败</strong><br/>"+"'
	html[#html+1] = '"<span style=\"color:#555;font-size:12px;\">请查看上方日志排查原因。完整日志: <code>cat /tmp/clawpanel-setup.log</code></span></div>";'
	html[#html+1] = '}'
	html[#html+1] = '}'

	-- 服务控制
	html[#html+1] = 'function cpServiceCtl(action){'
	html[#html+1] = 'var el=document.getElementById("action-result");'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#999\">⏳ 正在执行...</span>";'
	html[#html+1] = '(new XHR()).get("' .. ctl_url .. '?action="+action,null,function(x){'
	html[#html+1] = 'try{var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(r.status==="ok"){el.innerHTML="<span style=\"color:green\">✅ "+action+" 已提交</span>";}'
	html[#html+1] = 'else{el.innerHTML="<span style=\"color:red\">❌ "+(r.message||"失败")+"</span>";}'
	html[#html+1] = '}catch(e){el.innerHTML="<span style=\"color:red\">❌ 错误</span>";}'
	html[#html+1] = '});'
	html[#html+1] = 'setTimeout("location.reload()",2000);'
	html[#html+1] = '}'

	-- 检测升级
	html[#html+1] = 'function cpCheckUpdate(){'
	html[#html+1] = 'var el=document.getElementById("action-result");'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#999\">⏳ 正在检测...</span>";'
	html[#html+1] = '(new XHR()).get("' .. check_url .. '",null,function(x){'
	html[#html+1] = 'try{var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(r.plugin_current){'
	html[#html+1] = 'if(r.plugin_has_update){'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#e36209\">🔌 插件: v"+r.plugin_current+" → v"+r.plugin_latest+" (有新版本可用)</span>";'
	html[#html+1] = '}else{'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#1a7f37\">✅ 插件已是最新: v"+r.plugin_current+"</span>";'
	html[#html+1] = '}'
	html[#html+1] = '}else{'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#999\">无法获取版本信息</span>";'
	html[#html+1] = '}'
	html[#html+1] = '}catch(e){el.innerHTML="<span style=\"color:red\">❌ 检测失败</span>";}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	-- 卸载
	html[#html+1] = 'function cpUninstall(){'
	html[#html+1] = 'if(!confirm("确定要卸载 ClawPanel？\\n\\n将删除 ClawPanel 程序、数据及所有配置，服务将停止。\\n\\n此操作不可恢复！"))return;'
	html[#html+1] = 'var btn=document.getElementById("btn-uninstall");'
	html[#html+1] = 'var el=document.getElementById("action-result");'
	html[#html+1] = 'btn.disabled=true;btn.textContent="⏳ 正在卸载...";'
	html[#html+1] = 'el.innerHTML="<span style=\"color:#999\">正在停止服务并清理文件...</span>";'
	html[#html+1] = '(new XHR()).get("' .. uninstall_url .. '",null,function(x){'
	html[#html+1] = 'btn.disabled=false;btn.textContent="🗑️ 卸载";'
	html[#html+1] = 'try{var r=JSON.parse(x.responseText);'
	html[#html+1] = 'if(r.status==="ok"){'
	html[#html+1] = 'el.innerHTML="<div style=\"border:1px solid #d0d7de;background:#f6f8fa;padding:12px 16px;border-radius:6px;\">"+"'
	html[#html+1] = '"<strong style=\"color:#1a7f37;\">✅ 卸载完成</strong><br/>"+"'
	html[#html+1] = '"<span style=\"color:#555;font-size:13px;\">"+r.message+"</span><br/>"+"'
	html[#html+1] = '"<button class=\"btn cbi-button cbi-button-apply\" type=\"button\" onclick=\"location.reload()\" style=\"margin-top:8px;\">🔄 刷新页面</button></div>";'
	html[#html+1] = '}else{el.innerHTML="<span style=\"color:red\">❌ "+(r.message||"卸载失败")+"</span>";}'
	html[#html+1] = '}catch(e){el.innerHTML="<span style=\"color:red\">❌ 请求失败</span>";}'
	html[#html+1] = '});'
	html[#html+1] = '}'

	html[#html+1] = '</script>'

	return table.concat(html, "\n")
end

-- ═══════════════════════════════════════════
-- 快捷入口
-- ═══════════════════════════════════════════
s4 = m:section(SimpleSection, nil)
s4.template = "cbi/nullsection"
local http = require "luci.http"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local port = uci:get("clawpanel", "main", "port") or "19527"
local enabled = uci:get("clawpanel", "main", "enabled") or "0"
local install_path = uci:get("clawpanel", "main", "install_path") or "/opt"
local cp_bin = install_path .. "/clawpanel/clawpanel"

-- 检测是否已安装
local installed = false
if io.open(cp_bin, "r") then installed = true end

guide = s4:option(DummyValue, "_guide")
guide.rawhtml = true
guide.cfgvalue = function()
	if not installed or enabled ~= "1" then
		return '<div style="border:1px solid #d0e8ff;background:#f0f7ff;padding:14px 18px;border-radius:6px;margin-top:12px;line-height:1.8;font-size:13px;">' ..
			'<strong style="font-size:14px;">📖 使用指南</strong><br/>' ..
			'<span style="color:#555;">' ..
			'① 点击上方 <b>「安装/重装」</b> 按钮下载并安装 ClawPanel<br/>' ..
			'② 安装完成后访问 <b>http://路由器IP:' .. port .. '</b><br/>' ..
			'③ 默认账号: <b>admin</b>，默认密码: <b>clawpanel</b><br/>' ..
			'④ 首次登录后请修改默认密码</span></div>'
	end
	return '<div style="border:1px solid #c6e9c9;background:#e6f7e9;padding:14px 18px;border-radius:6px;margin-top:12px;line-height:1.8;font-size:13px;">' ..
		'<strong style="font-size:14px;">🎉 ClawPanel 已安装</strong><br/>' ..
		'<span style="color:#555;">' ..
		'访问地址: <b>http://路由器IP:' .. port .. '</b><br/>' ..
		'数据目录: <code>' .. install_path .. '/clawpanel/data</code></span></div>'
end

return m
