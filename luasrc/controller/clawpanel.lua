-- luci-app-clawpanel — LuCI Controller
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

	entry({"admin", "services", "clawpanel", "basic"},
		cbi("clawpanel/basic"), _("状态与设置"), 10).leaf = true

	entry({"admin", "services", "clawpanel", "install"},
		template("clawpanel/basic_install"), _("安装"), 20).leaf = true

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
		disk_free = ""
	}

	if cp_bin ~= "" then
		result.panel_version = trim(sh(cp_bin .. " --version"))
	end

	local cnt = trim(sh("ss -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || netstat -tulnp 2>/dev/null | grep -c ':" .. port .. " ' || echo 0"))
	result.panel_running = (tonumber(cnt) or 0) > 0

	if result.panel_running then
		local pid = trim(sh("ss -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1 | sed 's/.*pid=//' | sed 's|/.*||' | awk '{print $1}'"))
		if pid == "" then
			pid = trim(sh("netstat -tulnp 2>/dev/null | grep ':" .. port .. " ' | head -1 | sed -n 's|.* \\([0-9]*\\)/.*|\\1|p'"))
		end
		if pid ~= "" then
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
				if h > 0 then result.uptime = string.format("%dh %dm %ds", h, m, s)
				elseif m > 0 then result.uptime = string.format("%dm %ds", m, s)
				else result.uptime = s .. "s" end
			end
		end
	end

	if install_path ~= "" then
		local parent = install_path:match("^(.*)/[^/]+$") or "/"
		local disk = trim(sh("df -h " .. parent .. " 2>/dev/null | tail -1 | awk '{print $4}'"))
		if disk ~= "" then result.disk_free = disk end
	end

	-- JSONP 支持：检查是否有 callback 参数
	local callback = http.formvalue("callback") or http.getenv("callback") or ""
	if callback ~= "" then
		http.prepare_content("application/javascript; charset=utf-8")
		http.write(callback .. "(")
		http.write_json(result)
		http.write(");")
	else
		http.prepare_content("application/json; charset=utf-8")
		http.write_json(result)
	end
end

function action_service_ctl()
	local http = require "luci.http"
	local dispatcher = require "luci.dispatcher"

	-- 返回一个自动跳转回主页的最小 HTML 页面
	-- 这是 LuCI ucode bridge 上最可靠的 API 响应方式
	local function redirect_to_main(msg)
		http.prepare_content("text/html; charset=utf-8")
		http.write(string.format([[
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="1;url=%s">
<style>body{font-family:Arial,sans-serif;text-align:center;padding:60px;background:#f5f5f5}
p{font-size:18px;color:#333;margin-top:20px}.ok{color:#1a7f37}.err{color:#cf222e}</style>
</head><body>
<p>%s</p>
<p style="font-size:13px;color:#888">页面将自动返回...</p>
<script>setTimeout(function(){location.href='%s'},1500);</script>
</body></html>
		]], dispatcher.build_url("admin", "services", "clawpanel"), msg, dispatcher.build_url("admin", "services", "clawpanel")))
	end

	local action = http.formvalue("action") or ""

	if action == "start" then
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		redirect_to_main("⏳ 启动中...")
	elseif action == "stop" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		redirect_to_main("⏳ 停止中...")
	elseif action == "restart" then
		sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
		sh("sleep 2")
		sh("/etc/init.d/clawpanel start >/dev/null 2>&1 &")
		redirect_to_main("⏳ 重启中...")
	elseif action == "enable" then
		sh("/etc/init.d/clawpanel enable 2>/dev/null")
		redirect_to_main("✅ 已启用开机启动")
	elseif action == "disable" then
		sh("/etc/init.d/clawpanel disable 2>/dev/null")
		redirect_to_main("✅ 已禁用开机启动")
	elseif action == "setup" then
		sh("rm -f /tmp/clawpanel-setup.log /tmp/clawpanel-setup.pid /tmp/clawpanel-setup.exit")
		local version = http.formvalue("version") or ""
		local install_path = http.formvalue("install_path") or ""
		install_path = install_path:gsub("[`$;&|<>]", "")
		install_path = install_path:gsub("/+$", "")

		sh("uci set clawpanel.main.install_path='" .. install_path .. "'; uci commit clawpanel 2>/dev/null")

		local env_prefix = ""
		if version ~= "" and version ~= "latest" and version:match("^[%d%.%-%d]+$") then
			env_prefix = "CP_VERSION=" .. version .. " "
		end

		sh("( " .. env_prefix .. "CP_BASE_PATH='" .. install_path .. "' /usr/bin/clawpanel-env setup > /tmp/clawpanel-setup.log 2>&1; RC=$?; echo $RC > /tmp/clawpanel-setup.exit; if [ $RC -eq 0 ]; then uci set clawpanel.main.enabled=1; uci commit clawpanel; /etc/init.d/clawpanel enable 2>/dev/null; fi ) & echo $! > /tmp/clawpanel-setup.pid")
		redirect_to_main("⏳ 安装已启动，正在下载 ClawPanel，请稍候（10-30秒）...")
	else
		redirect_to_main("❌ 未知操作: " .. action)
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
	if pidf then
		local pid = trim(pidf:read("*a"))
		pidf:close()
		if pid ~= "" then
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
	if running then state = "running"
	elseif exit_code == 0 then state = "success"
	elseif exit_code > 0 then state = "failed"
	end

	http.prepare_content("application/json")
	http.write_json({ state = state, exit_code = exit_code, log = log })
end

function action_check_update()
	local http = require "luci.http"

	local plugin_current = ""
	local f = io.open("/usr/share/clawpanel/VERSION", "r")
	if f then
		plugin_current = trim(f:read("*a"))
		f:close()
	end

	local plugin_latest = ""
	local plugin_has_update = false

	local gh_json = sh("curl -sf --connect-timeout 5 --max-time 10 'https://api.github.com/repos/zhaoxinyi02/ClawPanel/releases/latest' 2>/dev/null")
	if gh_json and gh_json ~= "" then
		local tag = gh_json:match('"tag_name"%s*:%s*"([^"]+)"')
		if tag and tag ~= "" then
			plugin_latest = tag:gsub("^v", ""):gsub("%s+", "")
		end
	end

	if plugin_current ~= "" and plugin_latest ~= "" and plugin_current ~= plugin_latest then
		plugin_has_update = true
	end

	http.prepare_content("application/json")
	http.write_json({
		plugin_current = plugin_current,
		plugin_latest = plugin_latest,
		plugin_has_update = plugin_has_update
	})
end

function action_uninstall()
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	local dispatcher = require "luci.dispatcher"

	local install_path = uci:get("clawpanel", "main", "install_path") or ""
	local cp_path = install_path ~= "" and (install_path .. "/clawpanel") or ""

	sh("/etc/init.d/clawpanel stop >/dev/null 2>&1")
	sh("/etc/init.d/clawpanel disable 2>/dev/null")
	sh("uci set clawpanel.main.enabled=0; uci commit clawpanel 2>/dev/null")

	if cp_path ~= "" then
		sh("rm -rf " .. cp_path)
	end
	sh("rm -f /tmp/clawpanel-setup.* /var/run/clawpanel.pid")

	local main_url = dispatcher.build_url("admin", "services", "clawpanel")
	http.prepare_content("text/html; charset=utf-8")
	http.write(string.format([[
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="2;url=%s">
<style>body{font-family:Arial,sans-serif;text-align:center;padding:60px;background:#f5f5f5}
p{font-size:18px;color:#cf222e;margin-top:20px}.sub{font-size:13px;color:#888;margin-top:12px}</style>
</head><body>
<p>🗑️ 正在卸载 ClawPanel...</p>
<p class="sub">所有数据将被删除</p>
<script>setTimeout(function(){location.href='%s'},2500);</script>
</body></html>
	]], main_url, main_url))
end

function action_check_system()
	local http = require "luci.http"

	local install_path = http.formvalue("install_path") or ""
	install_path = install_path:gsub("[`$;&|<>]", "")
	install_path = install_path:gsub("/+$", "")
	if install_path == "" then install_path = "/opt" end

	local MIN_MEMORY_MB = 256
	local MIN_DISK_MB = 500

	local result = {
		memory_mb = 0, memory_ok = false,
		disk_mb = 0, disk_ok = false,
		install_path = install_path, pass = false, message = ""
	}

	-- 读取内存
	local mi = io.open("/proc/meminfo", "r")
	if mi then
		for line in mi:lines() do
			local v = line:match("MemTotal:%s+(%d+)%s+kB")
			if v then result.memory_mb = math.floor(tonumber(v) / 1024); break end
		end
		mi:close()
	end
	result.memory_ok = result.memory_mb >= MIN_MEMORY_MB

	-- 磁盘空间（直接用 df -m 获取 MB 数值）
	local avail_mb = trim(sh("df -m " .. install_path .. " 2>/dev/null | tail -1 | awk '{print $4}'"))
	if avail_mb ~= "" and tonumber(avail_mb) then
		result.disk_mb = tonumber(avail_mb)
	else
		result.disk_mb = 0
	end
	result.disk_ok = result.disk_mb >= MIN_DISK_MB
	result.pass = result.memory_ok and result.disk_ok

	if result.pass then
		result.message = "OK"
	else
		local issues = {}
		if not result.memory_ok then
			table.insert(issues, "内存" .. result.memory_mb .. "MB不足")
		end
		if not result.disk_ok then
			table.insert(issues, "磁盘" .. result.disk_mb .. "MB不足")
		end
		result.message = table.concat(issues, "; ")
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

function action_mounts()
	local http = require "luci.http"

	-- df -h 输出格式:
	-- tmpfs  499  0  499  0%  /run
	-- /dev/root  226G  180G  46G  80%  /
	-- 字段: 1=fs 2=size 3=used 4=avail 5=pct 6+=mount
	-- avail 可能是 "226G" "46G" "499" (tmpfs用KB)
	local output = sh("df -h 2>/dev/null | awk 'NR>1{print}'")
	local mounts = {}

	for line in output:gmatch("[^\r\n]+") do
		-- 提取第4字段(avail)和第6+字段(mount point)
		local avail, mp = line:match("^%S+%s+%S+%s+%S+%s+(%S+)%s+%d+%%%s+(.+)$")
		if not avail then
			avail, mp = line:match("^%S+%s+%S+%s+%S+%s+(%S+)%s+%d+%%%s+(.+)$")
		end

		if avail and mp then
			local skip = false
			if mp == "/" or mp == "/overlay" or mp == "/rom" or mp == "/boot" then skip = true end
			if mp == "/tmp" or mp == "/var" or mp == "/run" then skip = true end
			if avail == "0" then skip = true end

			if not skip then
				local avail_mb = 0
				local num = avail:match("^([%d%.]+)")
				if num then
					if avail:match("G$") then
						avail_mb = tonumber(num) * 1024
					elseif avail:match("M$") then
						avail_mb = tonumber(num)
					elseif avail:match("K$") then
						avail_mb = tonumber(num) / 1024
					else
						-- tmpfs raw number is in KB
						avail_mb = tonumber(num) / 1024
					end
			 end

				if avail_mb >= 100 then
					mounts[#mounts + 1] = {
						mount = mp,
						size = avail,
						avail_mb = math.floor(avail_mb)
					}
				end
			end
		end
	end

	table.sort(mounts, function(a, b) return (a.avail_mb or 0) > (b.avail_mb or 0) end)

	local cur = trim(sh("uci -q get clawpanel.main.install_path || echo ''"))

	http.prepare_content("application/json")
	http.write_json({ mounts = mounts, current_install_path = cur })
end
