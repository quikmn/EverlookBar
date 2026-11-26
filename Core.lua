-- EverlookDB Bar: core. Names, saved settings, the shared event frame, the shared ticker, safe calls and profiling.
local ADDON, ns = ...

------------------------------------------------------------------------
-- The name. Renaming the addon: change these lines, the .toc Title, and (if the folder changes) the .toc file name,
-- the folder and the SavedVariables line. ns.GLOBAL is the public table third parties use (EverlookBar.API).
------------------------------------------------------------------------
ns.NAME = "EverlookDB Bar"
ns.SLASH = "/ebar"
ns.GLOBAL = "EverlookBar"
ns.PREFIX = "EverlookBar" -- LDB names of the built-in plugins ("EverlookBar_XP") and global frame names
ns.ADDON = ADDON
ns.name = ns.NAME
ns.SAVED = "EverlookBarDB"

local UI = LibStub("EverlookUI-1")
ns.UI = UI
local U = UI.Util
ns.Util = U

-- Gold accent: the one primary button per screen is gold.
ns.ACCENT = { 1.000, 0.780, 0.290 }
ns.Theme = UI.MakeTheme(ns.ACCENT)

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffc74a" .. ns.NAME .. "|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Secret values. Anything that could come back secret goes through these before maths, comparisons or SetText
-- caching. A secret is never compared, never added to, never used as a table key.
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
ns.IsSecret = issecret

-- A plain number, or nil (secret, nil, NaN or not a number).
function ns.Num(v)
	if v == nil or issecret(v) or type(v) ~= "number" or v ~= v then return nil end
	return v
end

-- A plain string, or nil.
function ns.Str(v)
	if v == nil or issecret(v) then return nil end
	local t = type(v)
	if t == "string" then return v end
	if t == "number" then return tostring(v) end
	return nil
end

------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------
ns.FONTS = {
	{ value = "friz", text = "Friz Quadrata (game default)", path = "Fonts\\FRIZQT__.TTF" },
	{ value = "arialn", text = "Arial Narrow (clean)", path = "Fonts\\ARIALN.TTF" },
	{ value = "skurri", text = "Skurri (chunky)", path = "Fonts\\SKURRI.TTF" },
	{ value = "morpheus", text = "Morpheus (fantasy)", path = "Fonts\\MORPHEUS.TTF" },
}
function ns.FontPath(key)
	for _, f in ipairs(ns.FONTS) do if f.value == key then return f.path end end
	return ns.FONTS[1].path
end

ns.BAR_DEFAULTS = {
	name = "Bar",
	edge = "top",          -- top | bottom | left | right | free
	lanes = 1,             -- rows (top/bottom) or columns (left/right)
	laneSize = 22,         -- row height, or column width for left/right bars (set from the edge when made)
	length = 0,            -- 0 = the whole edge, else pixels
	align = "center",      -- start | center | end: where a shorter bar sits along its edge
	offset = 0,            -- extra shift along the edge
	x = 0, y = 0,          -- free bars: bottom-left corner on screen
	bg = { 0, 0, 0, 0.6 },
	line = false,          -- thin accent line on the inner edge
	font = "friz",
	fontSize = 12,
	outline = "",
	spacing = 14,          -- gap between plugins
	padding = 8,           -- gap at the bar's ends
	shown = true,
	strata = "MEDIUM",
}

ns.DEFAULTS = {
	version = 1,
	bars = {},             -- [i] = bar settings (filled from BAR_DEFAULTS)
	placement = {},        -- [ldbName] = { bar = i, lane = 1, group = "left"|"center"|"right", order = n }
	plugins = {},          -- [ldbName] = { icon = true, label = false, text = true }
	modules = {},          -- [moduleId] = { enabled = bool, ... } (each module fills its own defaults)
	ext = {},              -- settings registered through EverlookBar.API.RegisterSettings, by owner
	autoAdd = false,       -- put plugins from other addons on bar 1 as they appear
	grid = 16,             -- unlock-mode grid size
	snap = true,
	profiling = false,
	hideBagGCD = true,     -- don't spin every bag slot with the global cooldown (WoW Forever reports it for all items)
	minimap = {},          -- filled by Minimap.lua
	seenLayout = false,    -- the default layout was placed once
	told = {},             -- notices said once ever in chat ("stepAside:SexyMap" = true); they stay in settings and /ebar status
}

------------------------------------------------------------------------
-- Events: one frame for the whole addon. Handlers run through SafeCall under their owner, so one failing module
-- never stops the others.
------------------------------------------------------------------------
local handlers = {} -- [event] = { { owner, fn }, ... }
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

function ns.On(event, owner, fn)
	local list = handlers[event]
	if not list then
		-- an event this client does not have raises an error: skip it quietly
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
		list = {}
		handlers[event] = list
	end
	for _, h in ipairs(list) do
		if h.owner == owner then h.fn = fn return end
	end
	list[#list + 1] = { owner = owner, fn = fn }
	return true
end

function ns.Off(event, owner)
	local list = handlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i].owner == owner then table.remove(list, i) end
	end
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

function ns.OffAll(owner)
	for event in pairs(handlers) do ns.Off(event, owner) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local h = list[i]
		if h then ns.SafeCall(h.owner, h.fn, h.owner, event, ...) end
	end
end)

------------------------------------------------------------------------
-- Safe calls and error isolation. `owner` is a table that collects errors (a plugin record or a module).
-- A failing call marks the owner (its button shows a small red marker) and is reported once in chat.
-- After 50 errors an owner is quarantined: its ticks stop until /reload.
------------------------------------------------------------------------
local pcall, type, tostring = pcall, type, tostring
local profiling = false
local debugprofilestop = debugprofilestop or function() return 0 end
ns.prof = { total = 0, calls = 0, since = 0, by = {} }

function ns.SetProfiling(on)
	profiling = on and true or false
	ns.prof.total, ns.prof.calls, ns.prof.since = 0, 0, GetTime()
	ns.prof.by = {}
end

function ns.ReportError(owner, err)
	if type(owner) ~= "table" then owner = ns end
	owner.errors = (owner.errors or 0) + 1
	owner.lastError = tostring(err)
	if owner.errors >= 50 then owner.quarantined = true end
	if owner.OnError then pcall(owner.OnError, owner) end
	if not owner.errorReported then
		owner.errorReported = true
		ns:Print("|cffff6060" .. U.Escape(owner.name or "a plugin") .. " had an error (the bar keeps running):|r "
			.. U.Escape(owner.lastError))
	end
	if ns.Host and ns.Host.OnOwnerError then pcall(ns.Host.OnOwnerError, ns.Host, owner) end
end

-- Calls fn(...) and returns ok, results. Never raises.
function ns.SafeCall(owner, fn, ...)
	if type(fn) ~= "function" then return false end
	if owner and owner.quarantined then return false end
	if not profiling then
		local ok, a, b, c, d = pcall(fn, ...)
		if not ok then ns.ReportError(owner, a) return false end
		return true, a, b, c, d
	end
	local start = debugprofilestop()
	local ok, a, b, c, d = pcall(fn, ...)
	local spent = debugprofilestop() - start
	local P = ns.prof
	P.total, P.calls = P.total + spent, P.calls + 1
	local key = owner and owner.name or "?"
	P.by[key] = (P.by[key] or 0) + spent
	if not ok then ns.ReportError(owner, a) return false end
	return true, a, b, c, d
end

------------------------------------------------------------------------
-- The shared ticker: one C_Timer ticker for everything, with per-task intervals. A task that is not active costs a
-- single table read per tick. No closures or strings are made per tick.
------------------------------------------------------------------------
local TICK = 0.1
local tasks = {}
ns.tasks = tasks
local ticker

local Task = {}
Task.__index = Task
function Task:SetActive(on)
	on = on and true or false
	if self.active == on then return end
	self.active = on
	if on then self.nextAt = GetTime() end -- run at the next tick
end
function Task:SetInterval(s) self.interval = math.max(TICK, tonumber(s) or 1) end
function Task:Cancel() self.active = false; self.cancelled = true end

local function tick()
	local now = GetTime()
	for i = 1, #tasks do
		local t = tasks[i]
		if t.active and now >= t.nextAt then
			t.nextAt = now + t.interval
			ns.SafeCall(t.owner, t.fn, t, now)
		end
	end
end
ns.Tick = tick -- tests drive it

-- Run fn(task, now) every `interval` seconds while active. owner collects errors.
function ns.Every(owner, interval, fn, active)
	local t = setmetatable({ owner = owner, fn = fn, interval = math.max(TICK, tonumber(interval) or 1), nextAt = 0,
		active = active ~= false }, Task)
	-- reuse a cancelled slot so add/remove cycles do not grow the list
	for i = 1, #tasks do
		if tasks[i].cancelled then tasks[i] = t return t end
	end
	tasks[#tasks + 1] = t
	if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(TICK, tick) end
	return t
end

-- Coalesce: fn runs once on the next frame however many times this is called before then.
local pendingSoon = {}
local soonQueued = false
local function runSoon()
	soonQueued = false
	-- swap in a fresh table first: the calls below may queue more (into the new one, for the next frame); changing the
	-- table pairs() walks made "invalid key to 'next'"
	local batch = pendingSoon
	pendingSoon = {}
	for fn, owner in pairs(batch) do
		local o = owner ~= true and owner or nil
		ns.SafeCall(o, fn, o) -- methods get their owner as self
	end
end
function ns.Soon(fn, owner)
	pendingSoon[fn] = owner or true
	if not soonQueued then
		soonQueued = true
		C_Timer.After(0, runSoon)
	end
end

------------------------------------------------------------------------
-- Out of combat: run now, or when combat ends.
------------------------------------------------------------------------
local afterCombat = {}
function ns.AfterCombat(key, fn)
	if not InCombatLockdown() then
		ns.SafeCall(ns, fn)
		return true
	end
	afterCombat[key] = fn
	return false
end
-- Combat locks whatever is unlocked (bars, minimap): one chat line per combat, however many things locked.
local toldCombatLock = false
function ns.SayLockedForCombat()
	if toldCombatLock then return end
	toldCombatLock = true
	ns:Print("locked for combat. Unlock again after combat.")
end

-- A notice for chat once ever (kept in the saved settings); returns true when it should be said now.
function ns.TellOnce(key)
	if not ns.db then return false end
	ns.db.told = ns.db.told or {}
	if ns.db.told[key] then return false end
	ns.db.told[key] = true
	return true
end

ns.On("PLAYER_REGEN_ENABLED", ns, function()
	toldCombatLock = false
	for key, fn in pairs(afterCombat) do
		afterCombat[key] = nil
		ns.SafeCall(ns, fn)
	end
end)

------------------------------------------------------------------------
-- Modules (the built-in plugins and the minimap). Each is switchable; a disabled module registers nothing.
------------------------------------------------------------------------
ns.modules, ns.moduleOrder = {}, {}

-- spec: id, title, desc, default (enabled by default?), defaults (its settings table), place ({ group, order })
function ns:NewModule(spec)
	local m = spec
	m.name = spec.title
	ns.modules[spec.id] = m
	ns.moduleOrder[#ns.moduleOrder + 1] = m
	return m
end

function ns:ModuleDB(id)
	return ns.db.modules[id]
end

-- user: the player switched it on just now (place it on a bar if it is on none).
function ns:SetModuleEnabled(m, on, user)
	local mdb = ns.db.modules[m.id]
	mdb.enabled = on and true or false
	if on and not m.running then
		if m.Available and not m:Available() then return end
		m.running = true
		ns.SafeCall(m, m.Enable, m)
		if m.ldbName and ns.Host and (user or not ns.db.seenLayout or ns.newModules[m.id]) then ns.Host:PlaceDefault(m.ldbName, m.place) end
	elseif not on and m.running then
		m.running = false
		ns.OffAll(m)
		if m.task then m.task:SetActive(false) end
		ns.SafeCall(m, m.Disable, m)
	end
	if ns.Host then ns.Host:RefreshAll() end
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
-- Defaults are written into the saved settings on first load, so a changed default never reaches a player who
-- already has the old one. Each step moves an old default to the new one; a value the player picked stays.
ns.newModules = {} -- [moduleId] = true: place it on bar 1 this session (see migrate)
local function migrate(db)
	local v = tonumber(db.version) or 1
	if v < 2 then
		-- 2026-11-18: the calendar's default became "23:59, Wednesday, 26-nov-2026" (was today's next event)
		local cal = db.modules and db.modules.calendar
		if cal and cal.style == "next" then cal.style = "full" end
	end
	if v < 3 and db.seenLayout then
		-- 2026-11-18: new built-ins (Professions, Reputation bar) are placed once for players who had a layout
		-- already; new players get every default anyway. Taken off a bar after that, they stay off.
		ns.newModules.professions, ns.newModules.reputation = true, true
	end
	if v < 4 then
		-- 2026-11-18: Professions shows only the two main professions on the bar; the rest fold out on a click
		local p = db.modules and db.modules.professions
		if p and p.cooking == true and p.firstAid == true and p.fishing == true then
			p.cooking, p.firstAid, p.fishing = false, false, false
		end
	end
	if v < 5 and db.seenLayout then
		-- 2026-11-26: the flight timer is placed once for players who had a layout (it hides on the ground)
		ns.newModules.flight = true
	end
	db.version = 5
end
ns.Migrate = migrate -- tests

ns.On("ADDON_LOADED", ns, function(_, _, name)
	if name ~= ADDON then return end
	ns.Off("ADDON_LOADED", ns)
	local saved = _G[ns.SAVED]
	if type(saved) ~= "table" then saved = {} end
	_G[ns.SAVED] = saved
	ns.db = U.FillDefaults(saved, ns.DEFAULTS)
	migrate(ns.db)
	if #ns.db.bars == 0 then
		ns.db.bars[1] = U.CopyTable(ns.BAR_DEFAULTS)
		ns.db.bars[1].name = "Top bar"
	end
	for _, bar in ipairs(ns.db.bars) do U.FillDefaults(bar, ns.BAR_DEFAULTS) end
	for _, m in ipairs(ns.moduleOrder) do
		ns.db.modules[m.id] = U.FillDefaults(ns.db.modules[m.id] or {}, m.defaults or {})
		if ns.db.modules[m.id].enabled == nil then ns.db.modules[m.id].enabled = m.default ~= false end
		-- a module's own older settings, moved to how it saves them now (never dropped)
		if m.Migrate then ns.SafeCall(m, m.Migrate, m, ns.db.modules[m.id]) end
	end
	ns.SetProfiling(ns.db.profiling)
	ns.Bars:Init()
	ns.Host:Init()
	-- the taskbar (0.4.0) is gone: its bar and settings go with it; plugins on it move like on any removed bar
	for i = #ns.db.bars, 1, -1 do
		local bar = ns.db.bars[i]
		if bar.kind == "taskbar" and not ns.Bars:RemoveBar(i) then bar.kind = nil end
	end
	ns.db.taskbar = nil
	for _, m in ipairs(ns.moduleOrder) do
		if ns.db.modules[m.id].enabled then ns:SetModuleEnabled(m, true) end
	end
	ns.db.seenLayout = true
	ns.Host:RefreshAll()
	if ns.Options then ns.Options:Init() end
end)

-- Public table (API.lua fills EverlookBar.API).
_G[ns.GLOBAL] = _G[ns.GLOBAL] or {}

-- The LDB data object of a built-in module: made the first time the module runs, reused after that (LDB objects
-- cannot be removed; a switched-off module's object simply gets no updates and no button).
function ns.Plugin(m, attrs)
	local ldb = LibStub("LibDataBroker-1.1")
	local obj = ldb:GetDataObjectByName(m.ldbName)
	if obj then return obj end
	return ldb:NewDataObject(m.ldbName, attrs)
end

-- Short number with thousands separators (no secrets: callers pass plain numbers).
function ns.Thousands(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

-- Tooltip helpers shared by the modules.
function ns.TipHeader(tip, title)
	tip:AddLine(title, 1, 0.82, 0.29)
end
function ns.TipHint(tip, text)
	tip:AddLine(text, 0.55, 0.58, 0.64, true)
end

-- This computer's time as hour, minute (and the epoch seconds) without making a table each call: the time-zone
-- offset is read from date("*t") once an hour (that call allocates), the rest is integer maths.
local tzOffset, tzAt = 0, -1e9
function ns.LocalClock()
	local now = time()
	if now - tzAt > 3600 then
		local t = date("*t", now)
		tzOffset = (t.hour * 3600 + t.min * 60 + t.sec) - now % 86400
		tzAt = now
	end
	local s = (now + tzOffset) % 86400
	return math.floor(s / 3600), math.floor(s / 60) % 60, now
end
