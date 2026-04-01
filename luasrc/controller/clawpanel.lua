-- luci-app-clawpanel — LuCI Controller
-- 全部使用 io.popen() 执行 shell 命令，不依赖 luci.sys
module("luci.controller.clawpanel", package.seeall)

-- 执行 shell 命令并返回 stdout
local function sh(cmd)
	local f = io.popen(cmd .. " 2>/dev/null")
	if not f then return "" end
	local out = f:read("*a")
	f:close()
	return out or ""
end

-- 去掉字符串首尾空白
local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function index()
	entry({"admin", "services", "clawpanel"},
		alias("admin", "services", "clawpanel", "basic"),
		_("ClawPanel"), 85).dependent = false

	entry({"admin", "services", "clawpanel", "basic"},
		cbi("clawpanel/basic"), _("状态与设置"), 10).leaf = true

	entry({"admin", "services", "clawpanel", "install"},
		template("clawpanel/basic_install"), _("安装 ClawPanel"), 20).leaf = true

	entry({"admin", "services", "clawpanel", "uninstall_page"},
		template("clawpanel/basic_uninstall"), _("卸载 ClawPanel"), 30).leaf = true

	entry({"admin", "services", "clawpanel", "status_api"},
		call("action_status"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "service_ctl"},
		call("action_service_ctl"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "setup_log"},
		call("action_setup_log"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "check_update"},
		call("action_check_update"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "uninstall"},
		call("action_uninstall"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "check_system"},
		call("action_check_system"), nil).leaf = true

	entry({"admin", "services", "clawpanel", "mounts"},
		call("action_mounts"), nil).leaf = true
end

-- ═══════════════════════════════════════════
-- 状态查询 API
-- ═══════════════════════════════════════════
function action_status()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()

	local port = uci:get("clawpanel", "main", "port") or "19527"
	local enabled = uci:get("clawpanel", "main", "enabled") or "0"
	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local edition = uci:get("clawpanel", "main", "edition") or "pro"
	local cp_bin = ""
	if install_path and install_path ~= "" then
		cp_bin = install_path .. "/clawpanel/clawpanel"
	end

	local result = {
		enabled = enabled,
		port = port,
		edition = edition,
		install_path = install_path or "",
		panel_running = false,
		panel_starting = false,
		pid = "",
		memory_kb = 0,
		uptime = "",
		panel_version = "",
		openclaw_version = "",
		disk_free = "",
	}

	-- 插件版本
	local f = io.open("/usr/share/clawpanel/VERSION", "r")
	if f then
		result.plugin_version = trim(f:read("*a"))
		f:close()
	end

	-- ClawPanel 版本
	if cp_bin ~= "" then
		local ver = trim(sh(cp_bin .. " --version"))
		result.panel_version = ver
	end

	-- 端口检测
	local cnt = trim(sh("ss -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || netstat -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || echo 0"))
	result.panel_running = (tonumber(cnt) or 0) > 0

	-- 正在启动中
	if not result.panel_running and enabled == "1" then
		local pid = trim(sh("pgrep -f 'clawpanel' 2>/dev/null | head -1"))
		if pid and pid ~= "" then
			result.panel_starting = true
		end
	end

	-- PID、内存、运行时长
	if result.panel_running and port then
		local pid = trim(sh("ss -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1 | sed 's/.*pid=//' | sed 's/.*\///' | awk '{print $1}'"))
		if not pid or pid == "" then
			pid = trim(sh("netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1 | sed -n 's|.* \\([0-9]*\\)/.*|\\1|p'"))
		end
		if pid and pid ~= "" then
			result.pid = pid
			local rss = trim(sh("awk '/VmRSS/{print $2}' /proc/" .. pid .. "/status 2>/dev/null"))
			result.memory_kb = tonumber(rss) or 0
			local start_ts = trim(sh("stat -c %Y /proc/" .. pid .. " 2>/dev/null"))
			local ts = tonumber(start_ts) or 0
			if ts > 0 then
				local up = os.time() - ts
				local h = math.floor(up / 3600)
				local m = math.floor((up % 3600) / 60)
				local s = up % 60
				if h > 0 then
					result.uptime = string.format("%dh %dm %ds", h, m, s)
				elseif m > 0 then
					result.uptime = string.format("%dm %ds", m, s)
				else
					result.uptime = s .. "s"
				end
			end
		end
	end

	-- 磁盘剩余空间
	if install_path and install_path ~= "" then
		local parent = install_path:match("^(.*)/[^/]+$") or "/"
		local disk = trim(sh("df -h " .. parent .. " 2>/dev/null | tail -1 | awk '{print $4}'"))
		if disk and disk ~= "" then
			result.disk_free = disk
		end
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

-- ═══════════════════════════════════════════
-- 服务控制 API
-- ═══════════════════════════════════════════
function action_service_ctl()
	local http = require "luci.http"
	local action = http.formvalue("action") or ""

	if action == "start" then
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
	elseif action == "stop" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 2")
	elseif action == "restart" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 2")
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
	elseif action == "enable" then
		sh("/etc/init.d/clawpanel enable 2>/dev/null")
	elseif action == "disable" then
		sh("/etc/init.d/clawpanel disable 2>/dev/null")
	elseif action == "setup" then
		sh("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")
		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or ""
		install_path = install_path:gsub("[`$;&|<>]", "")
		install_path = install_path:gsub("/+$", "")

		sh("uci set clawpanel.main.install_path='" .. install_path .. "'; uci commit clawpanel 2>/dev/null")

		local env_prefix = ""
		if version ~= "" and version ~= "latest" then
			if version:match("^[%d%.%-a-zA-Z]+$") then
				env_prefix = "CP_VERSION=" .. version .. " "
			end
		end

		sh("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' /usr/bin/clawpanel-env setup > /tmp/clawpanel-setup.log 2>&1; RC=$?; echo $RC > /tmp/clawpanel-setup.exit; if [ $RC -eq 0 ]; then uci set clawpanel.main.enabled=1; uci commit clawpanel; /etc/init.d/clawpanel enable 2>/dev/null; fi ) & echo $! > /tmp/clawpanel-setup.pid")

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

	local log = ""
	local f = io.open("/tmp/clawpanel-setup.log", "r")
	if f then
		log = f:read("*a") or ""
		f:close()
	end

	local running = false
	local pidf = io.open("/tmp/clawpanel-setup.pid", "r")
	if pidf then
		local pid = trim(pidf:read("*a"))
		pidf:close()
		if pid and pid ~= "" then
			local ok = trim(sh("kill -0 " .. pid .. " 2>/dev/null && echo yes || echo no"))
			running = (ok == "yes")
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

	local state = "idle"
	if running then
		state = "running"
	elseif exit_code == 0 then
		state = "success"
	elseif exit_code > 0 then
		state = "failed"
	end

	http.prepare_content("application/json")
	http.write_json({ state = state, exit_code = exit_code, log = log })
end

-- ═══════════════════════════════════════════
-- 版本检查 API
-- ═══════════════════════════════════════════
function action_check_update()
	local http = require "luci.http"

	local plugin_current = ""
	local f = io.open("/usr/share/clawpanel/VERSION", "r")
	if f then
		plugin_current = trim(f:read("*a"))
		f:close()
	end

	local plugin_latest = ""
	local release_notes = ""
	local plugin_has_update = false

	local gh_json = sh("curl -sf --connect-timeout 5 --max-time 10 'https://api.github.com/repos/zhaoxinyi02/ClawPanel/releases/latest' 2>/dev/null")
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
	local uci = require "luci.model.uci".cursor()

	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local cp_path = install_path
	if cp_path ~= "" then
		cp_path = cp_path .. "/clawpanel"
	end

	sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
	sh("/etc/init.d/clawpanel disable 2>/dev/null")
	sh("uci set clawpanel.main.enabled=0; uci commit clawpanel 2>/dev/null")

	if cp_path ~= "" then
		sh("rm -rf " .. cp_path)
	end

	sh("rm -f /tmp/clawpanel-setup.* /var/run/clawpanel.pid")
	sh("rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null")

	http.prepare_content("application/json")
	http.write_json({
		status = "ok",
		message = "ClawPanel 已完全卸载。安装目录 (" .. (cp_path or "") .. ") 和服务均已清除。"
	})
end

-- ═══════════════════════════════════════════
-- 系统检测 API
-- ═══════════════════════════════════════════
function action_check_system()
	local http = require "luci.http"

	local install_path = http.formvalue("install_path") or ""
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
			local val = line:match("MemTotal:%s+(%d+)%s+kB")
			if val then
				result.memory_mb = math.floor(tonumber(val) / 1024)
				break
			end
		end
		meminfo:close()
	end
	result.memory_ok = result.memory_mb >= MIN_MEMORY_MB

	-- 获取磁盘空间
	local mp = install_path
	while mp ~= "/" and mp ~= "" do
		local test = io.open(mp, "r")
		if test then
			test:close()
			break
		end
		mp = mp:match("^(.*)/[^/]+$") or "/"
	end
	if mp == "" then mp = "/" end

	local df_out = trim(sh("df -m " .. mp .. " 2>/dev/null | tail -1 | awk '{print $4}'"))
	if df_out ~= "" and tonumber(df_out) then
		result.disk_mb = tonumber(df_out)
		result.disk_path = mp
		result.disk_free_str = trim(sh("df -h " .. mp .. " 2>/dev/null | tail -1 | awk '{print $4}'"))
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

-- ═══════════════════════════════════════════
-- 可用外置存储挂载点查询 API
-- ═══════════════════════════════════════════
function action_mounts()
	local http = require "luci.http"

	local output = sh("df -h 2>/dev/null | awk 'NR>1'")
	local mounts = {}

	for line in output:gmatch("[^\r\n]+") do
		local fs, avail, mp
		fs, avail, mp = line:match("^([%S]+)%s+[%d%.%w]+%s+[%d%.%w]+%s+([%d%.%w]+)%s+[%d%%]+%s+([%S]+)$")
		if not fs then
			fs, avail, mp = line:match("^([%S]+)%s+[%d%.%w]+%s+[%d%.%w]+%s+([%d%.%w]+)%s+[%d%%]+%s+([%S]+)$")
		end

		if fs and mp then
			local skip = false
			if mp == "/" then skip = true end
			if mp == "/overlay" then skip = true end
			if mp == "/rom" then skip = true end
			if mp == "/boot" then skip = true end
			if mp == "/tmp" then skip = true end
			if mp == "/var" then skip = true end
			if mp == "/run" then skip = true end
			if not skip and fs == "tmpfs" then skip = true end
			if not skip and fs == "devpts" then skip = true end
			if not skip and fs == "proc" then skip = true end
			if not skip and not mp:match("^/") then skip = true end

			if not skip then
				local avail_mb = 0
				if avail then
					local num = avail:match("([%d%.]+)")
					if avail:match("T") and num then
						avail_mb = tonumber(num) * 1024 * 1024
					elseif avail:match("G") and num then
						avail_mb = tonumber(num) * 1024
					elseif num then
						avail_mb = tonumber(num) or 0
					end
				end
				if avail_mb >= 100 then
					mounts[#mounts + 1] = {
						mount = mp,
						size = avail,
						avail_mb = math.floor(avail_mb),
						fs = fs
					}
				end
			end
		end
	end

	table.sort(mounts, function(a, b)
		return (a.avail_mb or 0) > (b.avail_mb or 0)
	end)

	local cur_path = trim(sh("uci -q get clawpanel.main.install_path || echo ''"))

	http.prepare_content("application/json")
	http.write_json({
		status = "ok",
		mounts = mounts,
		current_install_path = cur_path
	})
end
