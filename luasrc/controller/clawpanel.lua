-- luci-app-clawpanel controller
module("luci.controller.clawpanel", package.seeall)

local function sh(cmd)
	local f = io.popen(cmd .. " 2>/dev/null")
	if not f then return "" end
	local out = f:read("*a")
	f:close()
	return out or ""
end

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function index()
	entry({"admin", "services", "clawpanel"},
		template("clawpanel/main"), _("ClawPanel"), 85).dependent = false
	entry({"admin", "services", "clawpanel", "status_api"},
		call("action_status"), nil).leaf = true
	entry({"admin", "services", "clawpanel", "service_ctl"},
		call("action_service_ctl"), nil).leaf = true
	entry({"admin", "services", "clawpanel", "setup_log"},
		call("action_setup_log"), nil).leaf = true
	entry({"admin", "services", "clawpanel", "uninstall"},
		call("action_uninstall"), nil).leaf = true
end

function action_status()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()

	local port = uci:get("clawpanel", "main", "port") or "19527"
	local enabled = uci:get("clawpanel", "main", "enabled") or "0"
	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local cp_bin = install_path ~= "" and (install_path .. "/clawpanel/clawpanel") or ""

	local result = {
		enabled = enabled,
		port = port,
		install_path = install_path,
		panel_running = false,
		pid = "",
		memory_kb = 0,
		uptime = "",
		panel_version = "",
		installed_version = "",
		disk_free = ""
	}

	-- ClawPanel 版本
	if cp_bin ~= "" and install_path ~= "" then
		local v = trim(sh(cp_bin .. " --version"))
		result.panel_version = v
		local vf = io.open(install_path .. "/clawpanel/.version", "r")
		if vf then
			result.installed_version = trim(vf:read("*a"))
			vf:close()
		end
	end

	-- 端口检测
	local cnt = trim(sh("netstat -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || echo 0"))
	result.panel_running = (tonumber(cnt) or 0) > 0

	-- PID
	if result.panel_running then
		local pid = trim(sh("netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1 | sed -n 's|.* \\([0-9]*\\)/.*|\\1|p'"))
		if pid == "" then pid = trim(sh("pgrep -f 'clawpanel' 2>/dev/null | head -1")) end
		if pid ~= "" then
			result.pid = pid
			local rss = trim(sh("awk '/VmRSS/{print $2}' /proc/" .. pid .. "/status 2>/dev/null"))
			result.memory_kb = tonumber(rss) or 0
			local ts = tonumber(trim(sh("stat -c %Y /proc/" .. pid .. "/status 2>/dev/null"))) or 0
			if ts > 0 then
				local up = os.time() - ts
				local h = math.floor(up / 3600)
				local m = math.floor((up % 3600) / 60)
				local s = up % 60
				if h > 0 then result.uptime = string.format("%dh %dm %ds", h, m, s)
				elseif m > 0 then result.uptime = string.format("%dm %ds", m, s)
				else result.uptime = s .. "s" end
			end
		end
	end

	-- 磁盘剩余
	if install_path ~= "" then
		local disk = trim(sh("df -h '" .. install_path .. "' | tail -1 | awk '{print $4}'"))
		if disk ~= "" then result.disk_free = disk end
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

function action_service_ctl()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local action = http.formvalue("action") or ""

	if action == "start" then
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "启动中..." })
	elseif action == "stop" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "已停止" })
	elseif action == "restart" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 2")
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "重启中..." })
	elseif action == "enable" then
		sh("/etc/init.d/clawpanel enable 2>/dev/null")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "已启用开机启动" })
	elseif action == "disable" then
		sh("/etc/init.d/clawpanel disable 2>/dev/null")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "已禁用开机启动" })
	elseif action == "setup" then
		sh("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")
		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or ""
		install_path = install_path:gsub("[`$;&|<>]", ""):gsub("/+$", "")

		sh("uci set clawpanel.main.install_path='" .. install_path .. "'; uci commit clawpanel 2>/dev/null")

		local env_prefix = ""
		if version ~= "" and version ~= "latest" then
			env_prefix = "CP_VERSION=" .. version .. " "
		end

		sh("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' /usr/bin/clawpanel-env setup >> /tmp/clawpanel-setup.log 2>&1; echo $? > /tmp/clawpanel-setup.exit ) & echo $! > /tmp/clawpanel-setup.pid")

		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "安装已启动，请等待..." })
	else
		http.prepare_content("application/json")
		http.write_json({ status = "error", message = "未知操作: " .. action })
	end
end

function action_setup_log()
	local http = require "luci.http"
	local log = ""
	local f = io.open("/tmp/clawpanel-setup.log", "r")
	if f then
		log = f:read("*a") or ""
		f:close()
	end

	local running = false
	local pidf = io.open("/tmp/clawpanel-setup.pid", "r")
	local stored_pid = ""
	if pidf then
		stored_pid = trim(pidf:read("*a"))
		pidf:close()
		if stored_pid ~= "" then
			running = trim(sh("kill -0 " .. stored_pid .. " 2>/dev/null && echo yes || echo no")) == "yes"
		end
	end

	local exit_code = -1
	if not running then
		local ef = io.open("/tmp/clawpanel-setup.exit", "r")
		if ef then
			local code = trim(ef:read("*a"))
			ef:close()
			exit_code = tonumber(code) or -1
		end
	end

	-- 如果超过120秒还在 running，且已有日志输出，认为已成功（超时视同成功）
	local state = "idle"
	if running then
		-- 检查日志里是否有"安装成功"关键字
		if log:match("安装成功") or log:match("安装完成") then
			state = "success"
		else
			state = "running"
		end
	elseif exit_code == 0 then
		state = "success"
	elseif exit_code > 0 then
		state = "failed"
	end

	http.prepare_content("application/json")
	http.write_json({ state = state, exit_code = exit_code, log = log })
end

function action_uninstall()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()

	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local cp_path = install_path ~= "" and (install_path .. "/clawpanel") or ""

	sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
	sh("/etc/init.d/clawpanel disable 2>/dev/null")
	sh("uci set clawpanel.main.enabled=0; uci commit clawpanel 2>/dev/null")

	if cp_path ~= "" then
		sh("rm -rf " .. cp_path)
	end
	sh("rm -f /tmp/clawpanel-setup.* /var/run/clawpanel.pid")

	http.prepare_content("application/json")
	http.write_json({ status = "ok", message = "ClawPanel 已完全卸载" })
end
