-- Everlook Bar: performance. FPS and latency on the bar (one cheap read per second, text rebuilt only when a shown
-- number changed); memory and per-addon CPU only in the tooltip, and only when you hover it.
local _, ns = ...

local M = ns:NewModule({
	id = "perf", title = "Performance", ldbName = ns.PREFIX .. "_Performance",
	desc = "FPS and latency on the bar; memory, CPU per addon and bandwidth in the tooltip.",
	defaults = { fps = true, latency = "world", memory = false, colors = true },
	place = { group = "right", order = 1 },
})

local obj
local last = { fps = -1, home = -1, world = -1, mem = -1 }
local memTotal, memAt = nil, -1000
local MEM_EVERY = 30 -- seconds; UpdateAddOnMemoryUsage walks every addon and is slow

local function color(v, good, bad)
	if v <= good then return "|cff62cf88" end
	if v >= bad then return "|cffef5d5d" end
	return "|cffffd25a"
end

local function numAddOns()
	local n = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)
	return n and n() or 0
end
local function addOnName(i)
	local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	return f and f(i)
end
local function isLoaded(i)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return f and f(i)
end

-- Total addon memory in KB, refreshed at most every MEM_EVERY seconds (never in combat).
local function memory(force)
	local now = GetTime()
	if (force or now - memAt >= MEM_EVERY) and not InCombatLockdown() and UpdateAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		memAt = now
		local total = 0
		for i = 1, numAddOns() do
			if isLoaded(i) then total = total + (ns.Num(GetAddOnMemoryUsage(i)) or 0) end
		end
		memTotal = total
	end
	return memTotal
end

local function fmtMem(kb)
	if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
	return string.format("%d KB", kb)
end

function M:Tick()
	local mdb = ns:ModuleDB("perf")
	local fps = math.floor((ns.Num(GetFramerate()) or 0) + 0.5)
	local _, _, home, world = GetNetStats()
	home, world = math.floor(ns.Num(home) or 0), math.floor(ns.Num(world) or 0)
	local mem = -1
	if mdb.memory then mem = math.floor((memory() or 0) / 1024 * 10) end -- tenths of MB
	if fps == last.fps and home == last.home and world == last.world and mem == last.mem then return end
	last.fps, last.home, last.world, last.mem = fps, home, world, mem
	local parts, c = {}, mdb.colors
	if mdb.fps then parts[#parts + 1] = (c and color(-fps, -50, -25) or "") .. fps .. (c and "|r" or "") .. " fps" end
	local lat = mdb.latency
	if lat == "home" or lat == "world" then
		local ms = lat == "home" and home or world
		parts[#parts + 1] = (c and color(ms, 100, 250) or "") .. ms .. (c and "|r" or "") .. " ms"
	elseif lat == "both" then
		parts[#parts + 1] = (c and color(home, 100, 250) or "") .. home .. (c and "|r" or "") .. "/"
			.. (c and color(world, 100, 250) or "") .. world .. (c and "|r" or "") .. " ms"
	end
	if mdb.memory and mem >= 0 then parts[#parts + 1] = string.format("%.1f MB", mem / 10) end
	obj.text = table.concat(parts, "  ")
end

-- Per-addon CPU: the game's addon profiler (always on in this client) or, failing that, scriptProfile.
local function cpuLines(tip)
	local P = C_AddOnProfiler
	if P and P.IsEnabled and P.IsEnabled() and P.GetTopKAddOnsForMetric and Enum and Enum.AddOnProfilerMetric then
		local ok, top = pcall(P.GetTopKAddOnsForMetric, Enum.AddOnProfilerMetric.RecentAverageTime, 6)
		if ok and type(top) == "table" then
			tip:AddLine(" ")
			tip:AddLine("CPU per addon (ms per frame, last 60 frames)", 1, 0.82, 0.29)
			for _, r in ipairs(top) do
				local v = ns.Num(r.metricValue)
				local name = ns.Str(r.addOnName)
				if v and name then tip:AddDoubleLine(name, string.format("%.3f", v), 0.9, 0.9, 0.9, 1, 1, 1) end
			end
			local all = P.GetOverallMetric and ns.Num(P.GetOverallMetric(Enum.AddOnProfilerMetric.RecentAverageTime))
			if all then tip:AddDoubleLine("All addons", string.format("%.3f", all), 0.9, 0.9, 0.9, 1, 1, 1) end
			return
		end
	end
	if GetCVarBool and GetCVarBool("scriptProfile") and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
		UpdateAddOnCPUUsage()
		local rows = {}
		for i = 1, numAddOns() do
			if isLoaded(i) then rows[#rows + 1] = { addOnName(i), ns.Num(GetAddOnCPUUsage(i)) or 0 } end
		end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		tip:AddLine(" ")
		tip:AddLine("CPU per addon (ms since login; scriptProfile is on)", 1, 0.82, 0.29)
		for i = 1, math.min(6, #rows) do
			tip:AddDoubleLine(rows[i][1] or "?", string.format("%.0f", rows[i][2]), 0.9, 0.9, 0.9, 1, 1, 1)
		end
		return
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "CPU per addon: not available. Turn on profiling with /console scriptProfile 1 and /reload (it slows the game; turn it off after).")
end

function M.Tooltip(tip)
	local fps = ns.Num(GetFramerate()) or 0
	local bin, bout, home, world = GetNetStats()
	bin, bout, home, world = ns.Num(bin) or 0, ns.Num(bout) or 0, ns.Num(home) or 0, ns.Num(world) or 0
	ns.TipHeader(tip, "Performance")
	tip:AddDoubleLine("Frame rate", string.format("%.0f fps", fps), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddDoubleLine("Latency home", string.format("%d ms", home), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddDoubleLine("Latency world", string.format("%d ms", world), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddDoubleLine("Bandwidth in / out", string.format("%.1f / %.1f KB/s", bin, bout), 0.9, 0.9, 0.9, 1, 1, 1)
	ns.TipHint(tip, "Home: you to your realm (chat, auction house). World: you to the game world (combat). The game updates latency about every 30 seconds.")
	ns.TipHint(tip, "Packet loss and jitter are not shown: the game gives addons no packet loss, and latency that changes only every 30 seconds is too coarse to measure jitter honestly.")

	-- memory: per addon, sorted; read now (hover), at most every 30 s
	local total = memory(false)
	if total then
		local rows = {}
		for i = 1, numAddOns() do
			if isLoaded(i) then rows[#rows + 1] = { addOnName(i), ns.Num(GetAddOnMemoryUsage(i)) or 0 } end
		end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		tip:AddLine(" ")
		tip:AddDoubleLine("Addon memory", fmtMem(total), 1, 0.82, 0.29, 1, 1, 1)
		for i = 1, math.min(8, #rows) do
			tip:AddDoubleLine(rows[i][1] or "?", fmtMem(rows[i][2]), 0.9, 0.9, 0.9, 1, 1, 1)
		end
		ns.TipHint(tip, string.format("Updated %d s ago (at most every 30 s; never in combat).", math.floor(GetTime() - memAt)))
	elseif InCombatLockdown() then
		tip:AddLine(" ")
		ns.TipHint(tip, "Addon memory: read after combat.")
	end
	cpuLines(tip)
	tip:AddLine(" ")
	ns.TipHint(tip, "Click: collect garbage (frees unused addon memory).")
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Perf", text = "", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function()
			if InCombatLockdown() then return end
			collectgarbage("collect")
			memAt = -1000
		end,
	})
	last.fps = -1
	self.task = self.task or ns.Every(self, 1, function() M:Tick() end)
	self.task:SetActive(true)
	self:Tick()
end

function M:Disable() if self.task then self.task:SetActive(false) end end
