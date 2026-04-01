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
	entry({"admin", "services", "clawpanel", "wait_running"},
		call("action_wait_running"), nil).leaf = true
	entry({"admin", "services", "clawpanel", "wait_stopped"},
		call("action_wait_stopped"), nil).leaf = true
	entry({"admin", "services", "clawpanel", "uninstall"},
		call("action_uninstall"), nil).leaf = true
end

-- Check if a process is running by PID
local function is_running(pid)
	if not pid or pid == "" then return false end
	return trim(sh("kill -0 " .. pid .. " 2>/dev/null && echo yes || echo no")) == "yes"
end

-- Get port status: returns { listening=true/false, pid="", samples=0 }
local function check_port(port)
	local listening = false
	local pid = ""
	-- Try netstat first (available on iStoreOS)
	local line = trim(sh("netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1"))
	if line and line ~= "" then
		listening = true
		-- Extract PID from netstat output like "tcp 0 0 :::19527 :::* LISTEN 32531/clawpanel"
		local p = line:match("(%d+)%/")
		if p then pid = p end
	end
	return { listening = listening, pid = pid }
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

	-- ClawPanel version from binary
	if cp_bin ~= "" and install_path ~= "" then
		local v = trim(sh(cp_bin .. " --version 2>/dev/null"))
		if v and v ~= "" then
			result.panel_version = v
		end
		local vf = io.open(install_path .. "/clawpanel/.version", "r")
		if vf then
			result.installed_version = trim(vf:read("*a"))
			vf:close()
		end
	end

	-- Port check: netstat is available on iStoreOS
	local port_info = check_port(port)
	result.panel_running = port_info.listening
	result.pid = port_info.pid

	-- Memory and uptime from PID
	if result.panel_running and result.pid ~= "" then
		local rss = trim(sh("awk '/VmRSS/{print $2}' /proc/" .. result.pid .. "/status 2>/dev/null"))
		result.memory_kb = tonumber(rss) or 0
		local ts = tonumber(trim(sh("stat -c %Y /proc/" .. result.pid .. "/status 2>/dev/null"))) or 0
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

	-- Disk free space
	if install_path ~= "" then
		local disk = trim(sh("df -h '" .. install_path .. "' | tail -1 | awk '{print $4}'"))
		if disk and disk ~= "" then result.disk_free = disk end
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

-- Wait for port to become LISTEN (for install confirmation)
function action_wait_running()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local port = uci:get("clawpanel", "main", "port") or "19527"

	local max_wait = 90  -- max 90 seconds
	local waited = 0
	local interval = 3   -- check every 3 seconds

	while waited < max_wait do
		local info = check_port(port)
		if info.listening then
			http.prepare_content("application/json")
			http.write_json({ state = "running", pid = info.pid, waited = waited })
			return
		end
		-- Sleep using shell
		sh("sleep " .. tostring(interval))
		waited = waited + interval
	end

	-- Timeout - port never came up
	http.prepare_content("application/json")
	http.write_json({ state = "timeout", pid = "", waited = waited })
end

-- Wait for port to stop listening (for stop/restart confirmation)
function action_wait_stopped()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local port = uci:get("clawpanel", "main", "port") or "19527"

	local max_wait = 30
	local waited = 0
	local interval = 1

	while waited < max_wait do
		local info = check_port(port)
		if not info.listening then
			http.prepare_content("application/json")
			http.write_json({ state = "stopped", waited = waited })
			return
		end
		sh("sleep " .. tostring(interval))
		waited = waited + interval
	end

	http.prepare_content("application/json")
	http.write_json({ state = "timeout", waited = waited })
end

function action_service_ctl()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local action = http.formvalue("action") or ""

	if action == "start" then
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Starting..." })

	elseif action == "stop" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Stopped" })

	elseif action == "restart" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 2")
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Restarting..." })

	elseif action == "enable" then
		sh("/etc/init.d/clawpanel enable 2>/dev/null")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Enabled" })

	elseif action == "disable" then
		sh("/etc/init.d/clawpanel disable 2>/dev/null")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Disabled" })

	elseif action == "setup" then
		-- Clean up old state files
		sh("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")

		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or ""
		-- Sanitize path - remove dangerous chars
		install_path = install_path:gsub("[`$;&|<>]", ""):gsub("/+$", "")

		-- Save install path to UCI immediately
		sh("uci set clawpanel.main.install_path='" .. install_path .. "'; uci commit clawpanel 2>/dev/null")

		local env_prefix = ""
		if version ~= "" and version ~= "latest" then
			env_prefix = "CP_VERSION=" .. version .. " "
		end

		-- Run installation in background, log to /tmp/clawpanel-setup.log
		sh("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' /usr/bin/clawpanel-env setup >> /tmp/clawpanel-setup.log 2>&1; echo $? > /tmp/clawpanel-setup.exit ) & echo $! > /tmp/clawpanel-setup.pid")

		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Installation started, please wait..." })

	else
		http.prepare_content("application/json")
		http.write_json({ status = "error", message = "Unknown action: " .. action })
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
	local stored_pid = ""

	local pidf = io.open("/tmp/clawpanel-setup.pid", "r")
	if pidf then
		stored_pid = trim(pidf:read("*a"))
		pidf:close()
		if stored_pid ~= "" then
			running = is_running(stored_pid)
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

	-- State determination:
	-- If still running: check if install success message appears in log
	-- If exited with 0: success
	-- If exited with non-zero: failed
	local state = "idle"

	if running then
		-- Check if log contains success indicators
		if log:match("success") or log:match("successful") or log:match("installed") or log:match("瀹夎鎴愬姛") or log:match("瀹屾垚") then
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

	if cp_path ~= "" and cp_path ~= "/" then
		sh("rm -rf " .. cp_path)
	end
	sh("rm -f /tmp/clawpanel-setup.* /var/run/clawpanel.pid")

	http.prepare_content("application/json")
	http.write_json({ status = "ok", message = "ClawPanel fully uninstalled" })
end
