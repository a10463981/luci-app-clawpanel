-- luci-app-clawpanel — LuCI Controller
module("luci.controller.clawpanel", package.seeall)

function index()
	-- 主入口: 服务 → ClawPanel
	local page = entry({"admin", "services", "clawpanel"},
		alias("admin", "services", "clawpanel", "basic"),
		_("ClawPanel"), 85)
	page.dependent = false

	-- 基本设置
	entry({"admin", "services", "clawpanel", "basic"},
		cbi("clawpanel/basic"), _("状态与设置"), 10).leaf = true

	-- 状态 API
	entry({"admin", "services", "clawpanel", "status_api"},
		call("action_status"), nil).leaf = true

	-- 服务控制 API
	entry({"admin", "services", "clawpanel", "service_ctl"},
		call("action_service_ctl"), nil).leaf = true

	-- 安装日志 API
	entry({"admin", "services", "clawpanel", "setup_log"},
		call("action_setup_log"), nil).leaf = true

	-- 版本检查 API
	entry({"admin", "services", "clawpanel", "check_update"},
		call("action_check_update"), nil).leaf = true

	-- 卸载 API
	entry({"admin", "services", "clawpanel", "uninstall"},
		call("action_uninstall"), nil).leaf = true

	-- 系统检测 API
	entry({"admin", "services", "clawpanel", "check_system"},
		call("action_check_system"), nil).leaf = true
end

-- ═══════════════════════════════════════════
-- 状态查询 API: 返回 JSON
-- ═══════════════════════════════════════════
function action_status()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()

	local port = uci:get("clawpanel", "main", "port") or "19527"
	local enabled = uci:get("clawpanel", "main", "enabled") or "0"
	local install_path = uci:get("clawpanel", "main", "install_path") or "/opt"
	local edition = uci:get("clawpanel", "main", "edition") or "pro"
	install_path = install_path .. "/clawpanel"

	-- 端口值安全校验
	if not port:match("^%d+$") then port = "19527" end

	local result = {
		enabled = enabled,
		port = port,
		edition = edition,
		install_path = install_path,
		panel_running = false,
		panel_starting = false,
		pid = "",
		memory_kb = 0,
		uptime = "",
		panel_version = "",
		openclaw_version = "",
		disk_free = "",
		nodejs_version = "",
	}

	-- 插件版本
	local pvf = io.open("/usr/share/clawpanel/VERSION", "r")
	if pvf then
		result.plugin_version = pvf:read("*a"):gsub("%s+", "")
		pvf:close()
	end

	-- ClawPanel 版本（二进制 --version）
	local cp_bin = install_path .. "/clawpanel"
	local f = io.open(cp_bin, "r")
	if f then
		f:close()
		local ver = sys.exec(cp_bin .. " --version 2>/dev/null"):gsub("%s+", "")
		result.panel_version = ver
	end

	-- OpenClaw 版本（从工作区读取）
	local openclaw_ver_file = install_path .. "/data/.openclaw/VERSION"
	local ovf = io.open(openclaw_ver_file, "r")
	if ovf then
		result.openclaw_version = ovf:read("*a"):gsub("%s+", "")
		ovf:close()
	end

	-- 端口检测
	local gw_check
	if command -v ss >/dev/null 2>&1; then
		gw_check = sys.exec("ss -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || echo 0"):gsub("%s+", "")
	else
		gw_check = sys.exec("netstat -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || echo 0"):gsub("%s+", "")
	end
	result.panel_running = (tonumber(gw_check) or 0) > 0

	-- 正在启动中（端口未监听但进程存在）
	if not result.panel_running and enabled == "1" then
		local procd_pid = sys.exec("pgrep -f 'clawpanel' 2>/dev/null | head -1"):gsub("%s+", "")
		if procd_pid ~= "" then
			result.panel_starting = true
		end
	end

	-- PID、内存、运行时长
	if result.panel_running then
		local pid_cmd
		if command -v ss >/dev/null 2>&1; then
			pid_cmd = "ss -tulnp 2>/dev/null | awk '/:" .. port .. " /{split($NF,a,\"/\");print a[1];exit}'"
		else
			pid_cmd = "netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | sed -n 's|.* \\([0-9]*\\)/.*|\\1|p' | head -1"
		end
		local pid = sys.exec(pid_cmd):gsub("%s+", "")
		if pid and pid ~= "" then
			result.pid = pid
			local rss = sys.exec("awk '/VmRSS/{print $2}' /proc/" .. pid .. "/status 2>/dev/null"):gsub("%s+", "")
			result.memory_kb = tonumber(rss) or 0
			local stat_time = sys.exec("stat -c %Y /proc/" .. pid .. " 2>/dev/null"):gsub("%s+", "")
			local start_ts = tonumber(stat_time) or 0
			if start_ts > 0 then
				local uptime_s = os.time() - start_ts
				local hours = math.floor(uptime_s / 3600)
				local mins = math.floor((uptime_s % 3600) / 60)
				local secs = uptime_s % 60
				if hours > 0 then
					result.uptime = string.format("%dh %dm %ds", hours, mins, secs)
				elseif mins > 0 then
					result.uptime = string.format("%dm %ds", mins, secs)
				else
					result.uptime = string.format("%ds", secs)
				end
			end
		end
	end

	-- 磁盘剩余空间
	local parent_dir = install_path:match("^(.*)/[^/]*$") or "/"
	local df_out = sys.exec("df -h " .. parent_dir .. " 2>/dev/null | tail -1 | awk '{print $4}'"):gsub("%s+", "")
	if df_out and df_out ~= "" then
		result.disk_free = df_out
	end

	-- OpenClaw 版本
	local oc_ver = sys.exec("cat " .. install_path .. "/data/.openclaw/VERSION 2>/dev/null"):gsub("%s+", "")
	if oc_ver ~= "" then
		result.openclaw_version = oc_ver
	end

	-- Node.js 版本（如果 OpenClaw Lite 内嵌了 Node.js）
	local node_bin = install_path .. "/runtime/node/bin/node"
	if io.open(node_bin, "r") then
		result.nodejs_version = sys.exec(node_bin .. " --version 2>/dev/null"):gsub("%s+", "")
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

-- ═══════════════════════════════════════════
-- 服务控制 API: start/stop/restart/setup
-- ═══════════════════════════════════════════
function action_service_ctl()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local action = http.formvalue("action") or ""

	if action == "start" then
		sys.exec("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
	elseif action == "stop" then
		sys.exec("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sys.exec("sleep 2")
	elseif action == "restart" then
		sys.exec("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sys.exec("sleep 2")
		sys.exec("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
	elseif action == "enable" then
		sys.exec("/etc/init.d/clawpanel enable 2>/dev/null")
	elseif action == "disable" then
		sys.exec("/etc/init.d/clawpanel disable 2>/dev/null")
	elseif action == "setup" then
		-- 后台安装
		sys.exec("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")
		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or "/opt"
		install_path = install_path:gsub("[`$;&|<>]", "")
		install_path = install_path:gsub("/+$", "")
		if install_path == "" then install_path = "/opt" end

		-- 保存安装路径到 UCI
		sys.exec("uci set clawpanel.main.install_path='" .. install_path .. "'; uci commit clawpanel 2>/dev/null")

		local env_prefix = ""
		if version ~= "" and version ~= "latest" then
			if version:match("^[%d%.%-a-zA-Z]+$") then
				env_prefix = "CP_VERSION=" .. version .. " "
			end
		end

		sys.exec("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' /usr/bin/clawpanel-env setup > /tmp/clawpanel-setup.log 2>&1; RC=$?; echo $RC > /tmp/clawpanel-setup.exit; if [ $RC -eq 0 ]; then uci set clawpanel.main.enabled=1; uci commit clawpanel; /etc/init.d/clawpanel enable 2>/dev/null; fi ) & echo $! > /tmp/clawpanel-setup.pid")

		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "安装已启动，请查看安装日志..." })
		return
	else
		http.prepare_content("application/json")
		http.write_json({ status = "error", message = "未知操作: " .. action })
		return
	end

	http.prepare_content("application/json")
	http.write_json({ status = "ok", action = action })
end

-- ═══════════════════════════════════════════
-- 安装日志轮询 API
-- ═══════════════════════════════════════════
function action_setup_log()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local log = ""
	local f = io.open("/tmp/clawpanel-setup.log", "r")
	if f then
		log = f:read("*a") or ""
		f:close()
	end

	local running = false
	local pid_file = io.open("/tmp/clawpanel-setup.pid", "r")
	if pid_file then
		local pid = pid_file:read("*a"):gsub("%s+", "")
		pid_file:close()
		if pid ~= "" then
			local check = sys.exec("kill -0 " .. pid .. " 2>/dev/null && echo yes || echo no"):gsub("%s+", "")
			running = (check == "yes")
		end
	end

	local exit_code = -1
	if not running then
		local exit_file = io.open("/tmp/clawpanel-setup.exit", "r")
		if exit_file then
			local code = exit_file:read("*a"):gsub("%s+", "")
			exit_file:close()
			exit_code = tonumber(code) or -1
		end
	end

	local state = "idle"
	if running then
		state = "running"
	elseif exit_code == 0 then
		state = "success"
	elseif exit_code > 0 then
		state = "failed"
	end

	http.prepare_content("application/json")
	http.write_json({
		state = state,
		exit_code = exit_code,
		log = log
	})
end

-- ═══════════════════════════════════════════
-- 版本检查 API
-- ═══════════════════════════════════════════
function action_check_update()
	local http = require "luci.http"
	local sys = require "luci.sys"

	-- 插件版本（当前安装的）
	local plugin_current = ""
	local pf = io.open("/usr/share/clawpanel/VERSION", "r")
	if pf then
		plugin_current = pf:read("*a"):gsub("%s+", "")
		pf:close()
	end

	local plugin_latest = ""
	local release_notes = ""
	local plugin_has_update = false

	-- GitHub API 获取最新 release
	local gh_json = sys.exec("curl -sf --connect-timeout 5 --max-time 10 'https://api.github.com/repos/zhaoxinyi02/ClawPanel/releases/latest' 2>/dev/null")
	if gh_json and gh_json ~= "" then
		local tag = gh_json:match('"tag_name"%s*:%s*"([^"]+)"')
		if tag and tag ~= "" then
			plugin_latest = tag:gsub("^v", ""):gsub("%s+", "")
		end
		local body = gh_json:match('"body"%s*:%s*"(.-)"[,}%\n ]')
		if body and body ~= "" then
			body = body:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\\\", "\\")
			release_notes = body
		end
	end

	if plugin_current ~= "" and plugin_latest ~= "" and plugin_current ~= plugin_latest then
		plugin_has_update = true
	end

	http.prepare_content("application/json")
	http.write_json({
		status = "ok",
		plugin_current = plugin_current,
		plugin_latest = plugin_latest,
		plugin_has_update = plugin_has_update,
		release_notes = release_notes
	})
end

-- ═══════════════════════════════════════════
-- 卸载 API
-- ═══════════════════════════════════════════
function action_uninstall()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()

	local install_path_uci = uci:get("clawpanel", "main", "install_path") or "/opt"
	local install_path = install_path_uci .. "/clawpanel"

	-- 停止服务
	sys.exec("/etc/init.d/clawpanel stop >/dev/null 2>&1")
	sys.exec("/etc/init.d/clawpanel disable 2>/dev/null")

	-- 禁用
	sys.exec("uci set clawpanel.main.enabled=0; uci commit clawpanel 2>/dev/null")

	-- 删除安装目录
	sys.exec("rm -rf " .. install_path)

	-- 清理临时文件
	sys.exec("rm -f /tmp/clawpanel-setup.* /var/run/clawpanel.pid")
	sys.exec("rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null")

	http.prepare_content("application/json")
	http.write_json({
		status = "ok",
		message = "ClawPanel 已完全卸载。安装目录 (" .. install_path .. ") 和服务均已清除。"
	})
end

-- ═══════════════════════════════════════════
-- 系统检测 API (安装前检测硬件)
-- 要求: 内存 > 256MB, 磁盘可用空间 > 500MB
-- ═══════════════════════════════════════════
function action_check_system()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local install_path = http.formvalue("install_path") or "/opt"
	install_path = install_path:gsub("[`$;&|<>]", "")
	install_path = install_path:gsub("/+$", "")
	if install_path == "" then install_path = "/opt" end

	local MIN_MEMORY_MB = 256
	local MIN_DISK_MB = 500

	local result = {
		memory_mb = 0,
		memory_ok = false,
		disk_mb = 0,
		disk_ok = false,
		disk_path = "",
		install_path = install_path,
		disk_free_str = "",
		pass = false,
		message = ""
	}

	-- 读取总内存
	local meminfo = io.open("/proc/meminfo", "r")
	if meminfo then
		for line in meminfo:lines() do
			local mem_total = line:match("MemTotal:%s+(%d+)%s+kB")
			if mem_total then
				result.memory_mb = math.floor(tonumber(mem_total) / 1024)
				break
			end
		end
		meminfo:close()
	end
	result.memory_ok = result.memory_mb >= MIN_MEMORY_MB

	-- 查找挂载点
	local function find_mount_point(path)
		if nixio.fs and nixio.fs.stat(path, "type") then
			return path
		end
		while path ~= "/" and path ~= "" do
			path = path:match("^(.*)/[^/]*$") or "/"
			if path == "" then path = "/" end
			if os.execute("test -d '" .. path .. "' 2>/dev/null") == 0 then
				return path
			end
		end
		return "/"
	end

	local disk_check_path = find_mount_point(install_path)

	-- 获取磁盘空间
	local df_output = sys.exec("df -m " .. disk_check_path .. " 2>/dev/null | tail -1 | awk '{print $4}'"):gsub("%s+", "")
	if df_output and df_output ~= "" and tonumber(df_output) then
		result.disk_mb = tonumber(df_output)
		result.disk_path = disk_check_path
		result.disk_free_str = sys.exec("df -h " .. disk_check_path .. " 2>/dev/null | tail -1 | awk '{print $4}'"):gsub("%s+", "")
	end
	result.disk_ok = result.disk_mb >= MIN_DISK_MB

	result.pass = result.memory_ok and result.disk_ok

	if result.pass then
		result.message = "系统检测通过"
	else
		local issues = {}
		if not result.memory_ok then
			table.insert(issues, string.format("内存不足: 当前 %d MB，需要 ≥ %d MB", result.memory_mb, MIN_MEMORY_MB))
		end
		if not result.disk_ok then
			table.insert(issues, string.format("磁盘空间不足: 当前 %d MB 可用，需要 ≥ %d MB", result.disk_mb, MIN_DISK_MB))
		end
		result.message = table.concat(issues, "；")
	end

	http.prepare_content("application/json")
	http.write_json(result)
end
