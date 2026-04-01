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

-- 甯﹁秴鏃剁殑 shell 鎵ц锛岄伩鍏嶉樆濉烇紙clawpanel --version 浼氳仈缃戞娴嬫洿鏂帮紝蹇呴』鍔犺秴鏃讹級
local function sh_timed(cmd, timeout_sec)
	timeout_sec = timeout_sec or 5
	local f = io.popen("timeout -t " .. timeout_sec .. " " .. cmd .. " 2>/dev/null")
	if not f then return "" end
	local out = f:read("*a")
	f:close()
	return out or ""
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
	entry({"admin", "services", "clawpanel", "uninstall_log"},
		call("action_uninstall_log"), nil).leaf = true
end

local function is_running(pid)
	if not pid or pid == "" then return false end
	return trim(sh("kill -0 " .. pid .. " 2>/dev/null && echo yes || echo no")) == "yes"
end

local function check_port(port)
	local listening = false
	local pid = ""
	local line = trim(sh("netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1"))
	if line and line ~= "" then
		listening = true
		local p = line:match("(%d+)%/%S+")
		if p and p ~= "" then pid = p end
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

	if cp_bin ~= "" and install_path ~= "" then
		local v = trim(sh_timed(cp_bin .. " --version", 5))
		if v and v ~= "" then result.panel_version = v end
		local vf = io.open(install_path .. "/clawpanel/.version", "r")
		if vf then
			result.installed_version = trim(vf:read("*a"))
			vf:close()
		end
	end

	local port_info = check_port(port)
	result.panel_running = port_info.listening
	result.pid = port_info.pid

	if result.panel_running and result.pid and result.pid ~= "" then
		local pid_num = tonumber(result.pid)
		if pid_num and pid_num > 0 then
			local rss_raw = trim(sh("awk '/VmRSS/{print $2}' /proc/" .. result.pid .. "/status 2>/dev/null"))
			local ok1, rss_val = pcall(function() return tonumber(rss_raw) end)
			result.memory_kb = (ok1 and rss_val) and rss_val or 0
			local ts_raw = trim(sh("stat -c %Y /proc/" .. result.pid .. "/status 2>/dev/null"))
			local ok2, ts_val = pcall(function() return tonumber(ts_raw) end)
			if ok2 and ts_val and ts_val > 0 then
				local up = os.time() - ts_val
				local h = math.floor(up / 3600)
				local m = math.floor((up % 3600) / 60)
				local s = up % 60
				if h > 0 then result.uptime = string.format("%dh %dm %ds", h, m, s)
				elseif m > 0 then result.uptime = string.format("%dm %ds", m, s)
				else result.uptime = s .. "s" end
			end
		end
	end

	if install_path ~= "" then
		local disk = trim(sh("df -h '" .. install_path .. "' | tail -1 | awk '{print $4}'"))
		if disk and disk ~= "" then result.disk_free = disk end
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

function action_wait_running()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local port = uci:get("clawpanel", "main", "port") or "19527"
	local max_wait = 90
	local waited = 0
	local interval = 3

	while waited < max_wait do
		local info = check_port(port)
		if info.listening then
			http.prepare_content("application/json")
			http.write_json({ state = "running", pid = info.pid, waited = waited })
			return
		end
		sh("sleep " .. tostring(interval))
		waited = waited + interval
	end

	http.prepare_content("application/json")
	http.write_json({ state = "timeout", pid = "", waited = waited })
end

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
		sh("sleep 1; killall -9 clawpanel 2>/dev/null; sleep 1")
		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "Stopped" })

	elseif action == "restart" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 1; killall -9 clawpanel 2>/dev/null; sleep 1")
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
		sh("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")

		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or ""
		-- Sanitize: only allow safe chars
		install_path = install_path:gsub("[^%w%-%./]", ""):gsub("/+$", "")

		if install_path == "" then
			http.prepare_content("application/json")
			http.write_json({ status = "error", message = "瀹夎璺緞涓嶈兘涓虹┖" })
			return
		end

		-- 鐢ㄦ埛鍙€夎缃?OpenClaw 鏁版嵁鐩綍锛岀暀绌哄垯鑷姩鎺ㄥ涓?<install_path>/clawpanel/data
		local openclaw_dir = http.formvalue("openclaw_dir") or ""
		openclaw_dir = openclaw_dir:gsub("[^%w%-%./]", "")
		if openclaw_dir == "" then
			-- 鑷姩鎺ㄥ锛氳窡闅忓畨瑁呰矾寰?			openclaw_dir = install_path .. "/clawpanel/data"
		end

		-- 淇濆瓨鍒?UCI
		sh("uci set clawpanel.main.install_path='" .. install_path .. "'")
		sh("uci set clawpanel.main.openclaw_dir='" .. openclaw_dir .. "'")
		sh("uci commit clawpanel 2>/dev/null")

		-- 閫氳繃鐜鍙橀噺浼犵粰 clawpanel-env锛堜笉杩?UCI 宸茬粡淇濆瓨浜嗭紝鑴氭湰閲屼細璇?UCI锛?		local env_prefix = ""
		if version ~= "" and version ~= "latest" then
			env_prefix = "CP_VERSION=" .. version .. " "
		end

		sh("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' CP_OPENCLAW_DIR='" .. openclaw_dir .. "' /usr/bin/clawpanel-env setup >> /tmp/clawpanel-setup.log 2>&1; echo $? > /tmp/clawpanel-setup.exit ) & echo $! > /tmp/clawpanel-setup.pid")

		http.prepare_content("application/json")
		http.write_json({ status = "ok", message = "瀹夎宸插紑濮嬶紝璇风瓑寰?.." })

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
			local ok, val = pcall(tonumber, code)
			exit_code = (ok and val) and val or -1
		end
	end

	local state = "idle"
	if running then
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

	local logf = io.open("/tmp/clawpanel-uninstall.log", "w")
	local function log(msg)
		if logf then
			logf:write(msg .. "\n")
			logf:flush()
		end
	end

	log("=== ClawPanel Uninstall Started ===")

	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local cp_path = install_path ~= "" and (install_path .. "/clawpanel") or ""

	log("Stopping ClawPanel service...")
	sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
	sh("sleep 2")
	log("Killing all clawpanel processes...")
	sh("killall -9 clawpanel 2>/dev/null; sleep 1")
	log("Service stopped")

	log("Disabling auto-start...")
	sh("/etc/init.d/clawpanel disable 2>/dev/null")
	sh("uci set clawpanel.main.enabled=0; uci commit clawpanel 2>/dev/null")
	log("Auto-start disabled")

	if cp_path ~= "" and cp_path ~= "/" then
		log("Removing files from " .. cp_path .. "...")
		sh("rm -rf " .. cp_path)
		log("Files removed")
	else
		log("No valid install path to remove")
	end

	log("Cleaning up UCI config...")
	sh("uci revert clawpanel 2>/dev/null; uci commit clawpanel 2>/dev/null")
	log("Cleanup complete")
	log("=== Uninstall Finished ===")

	if logf then logf:close() end

	http.prepare_content("application/json")
	http.write_json({ status = "ok", message = "ClawPanel fully uninstalled" })
end

function action_uninstall_log()
	local http = require "luci.http"
	local log = ""

	local f = io.open("/tmp/clawpanel-uninstall.log", "r")
	if f then
		log = f:read("*a") or ""
		f:close()
	end

	local uci = require "luci.model.uci".cursor()
	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local completed = (install_path == "")

	http.prepare_content("application/json")
	http.write_json({ log = log, completed = completed })
end
