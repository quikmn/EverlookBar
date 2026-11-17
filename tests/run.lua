-- Offline tests for Everlook Bar: loads the addon in TOC order against wowmock.lua and checks the LDB host, error
-- isolation, the layout maths, the secret-value guards, the modules, the minimap, settings from chat and the API.
local ROOT = ...
local ADDON = "EverlookBar"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then passes = passes + 1; print("  ok   " .. name)
	else failures[#failures + 1] = name .. ": " .. tostring(err); print("  FAIL " .. name .. "\n         " .. tostring(err)) end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function S(v) return MOCK.Secret(v) end
local function flush() MOCK.RunTimers() end
local function slash(msg) SlashCmdList.EVERLOOKBAR(msg) end
local function lastLog() return MOCK.log[#MOCK.log] or "" end
local function logHas(s)
	for _, l in ipairs(MOCK.log) do if l:find(s, 1, true) then return true end end
	return false
end

-- Taint guard: our own files may only write these globals (Blizzard globals must never be written).
local ALLOWED = { EverlookBar = true, EverlookBarDB = true, SLASH_EVERLOOKBAR1 = true, GetMinimapShape = true }
local globalWrites = {}
local addonEnv = setmetatable({}, {
	__index = _G,
	__newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end,
})

collectgarbage("collect")
local memStart = collectgarbage("count")
step("load TOC files", function()
	local toc = assert(io.open(ROOT .. "/EverlookBar.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local rel = line:gsub("\\", "/"):gsub("%s+$", "")
			local chunk, err = loadfile(ROOT .. "/" .. rel)
			if not chunk then error("syntax: " .. err) end
			if not rel:find("^Libs/") then setfenv(chunk, addonEnv) end
			chunk(ADDON, ns)
		end
	end
	check(EverlookBar and EverlookBar.API, "public API table missing")
end)


step("ADDON_LOADED: saved settings, one top bar, built-ins placed", function()
	MOCK.Fire("ADDON_LOADED", ADDON)
	MOCK.loggedIn = true
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	flush()
	check(EverlookBarDB == ns.db, "saved variable not bound")
	eq(#ns.db.bars, 1, "bars")
	eq(ns.db.bars[1].edge, "top", "edge")
	eq(ns.db.placement.EverlookBar_Location.group, "left", "location group")
	eq(ns.db.placement.EverlookBar_XP.group, "center", "xp group")
	eq(ns.db.placement.EverlookBar_Performance.group, "right", "perf group")
	check(ns.db.placement.EverlookBar_Clock == nil, "clock is off by default and not placed")
	check(ns.Host.plugins.EverlookBar_Gold.button:IsShown(), "gold button shown")
end)

collectgarbage("collect")
local memLoaded = collectgarbage("count")

step("taint guard: only our own globals written", function()
	for k in pairs(globalWrites) do check(ALLOWED[k], "wrote global " .. k) end
end)

------------------------------------------------------------------------
-- Layout maths
------------------------------------------------------------------------
local L = ns.Layout
step("layout: bars stack on an edge, side bars, free bars clamp", function()
	local bars = {
		{ edge = "top", lanes = 1, laneSize = 22 },
		{ edge = "top", lanes = 2, laneSize = 20 },
		{ edge = "bottom", lanes = 1, laneSize = 24, length = 600, align = "center" },
		{ edge = "left", lanes = 1, laneSize = 150, length = 400, align = "start" },
		{ edge = "free", lanes = 1, laneSize = 22, length = 300, x = 5000, y = -50 },
		{ edge = "top", lanes = 1, laneSize = 22, shown = false },
		{ edge = "top", lanes = 1, laneSize = 22 },
	}
	local r = L.BarRects(bars, 1920, 1080)
	eq(r[1].y, 1080 - 22, "first top bar at the top")
	eq(r[1].w, 1920, "full width")
	eq(r[2].y, 1080 - 22 - 40, "second top bar under the first")
	eq(r[2].h, 40, "two rows")
	eq(r[3].x, (1920 - 600) / 2, "centred bottom bar")
	eq(r[3].y, 0, "bottom")
	check(r[4].vertical, "left bar is vertical")
	eq(r[4].x, 0, "left edge"); eq(r[4].w, 150, "column width"); eq(r[4].y, 1080 - 400, "starts at the top")
	eq(r[5].x, 1920 - 300, "free bar clamped right"); eq(r[5].y, 0, "free bar clamped bottom")
	eq(r[7].y, 1080 - 22 - 40 - 22, "hidden bar takes no room")
end)

step("layout: groups left, centre, right; side bars stack", function()
	local bar = { edge = "top", lanes = 2, laneSize = 22, spacing = 10, padding = 8 }
	local a = { key = "a", w = 50, lane = 1, group = "left", order = 2 }
	local b = { key = "b", w = 30, lane = 1, group = "left", order = 1 }
	local c = { key = "c", w = 40, lane = 1, group = "center", order = 1 }
	local d = { key = "d", w = 60, lane = 2, group = "right", order = 1 }
	local e = { key = "e", w = 20, lane = 2, group = "right", order = 2 }
	local p = L.PlaceItems(bar, 1000, 44, { a, b, c, d, e })
	eq(p[b].x, 8, "first left item at the padding"); eq(p[a].x, 8 + 30 + 10, "second follows")
	eq(p[c].x, 480, "centred")
	eq(p[e].x, 1000 - 8 - 20, "last right item at the far end"); eq(p[d].x, 1000 - 8 - 20 - 10 - 60, "right group keeps order")
	eq(p[d].y, 22, "second row")
	local side = { edge = "left", lanes = 1, laneSize = 150, spacing = 2, padding = 4 }
	local s1 = { key = "s1", w = 300, lane = 1, group = "left", order = 1 }
	local s2 = { key = "s2", w = 80, lane = 1, group = "left", order = 2 }
	local q = L.PlaceItems(side, 150, 600, { s1, s2 }, 20)
	eq(q[s1].y, 4, "stacked from the top"); eq(q[s2].y, 4 + 20 + 2, "next one below")
	eq(q[s1].w, 150, "full column width")
end)

step("layout: drop target, sticky width, edge snapping, reorder", function()
	local bar = { edge = "top", lanes = 2, laneSize = 22 }
	local placed = { { key = "x", x = 10, y = 0, w = 40, h = 22, lane = 1, group = "left" },
		{ key = "y", x = 60, y = 0, w = 40, h = 22, lane = 1, group = "left" } }
	local lane, group, index = L.DropTarget(bar, 900, 44, 55, 5, placed)
	eq(lane, 1); eq(group, "left"); eq(index, 2, "between x and y")
	lane, group = L.DropTarget(bar, 900, 44, 450, 30, placed)
	eq(lane, 2); eq(group, "center")
	_, group = L.DropTarget(bar, 900, 44, 800, 5, placed)
	eq(group, "right")
	eq(L.StickyWidth(nil, 50), 50); eq(L.StickyWidth(50, 60), 60, "grows")
	eq(L.StickyWidth(60, 55, 10), 60, "small shrink ignored"); eq(L.StickyWidth(60, 40, 10), 40, "big shrink taken")
	eq(L.EdgeForDrop(100, 1060, 400, 20, 1920, 1080), "top")
	eq(L.EdgeForDrop(5, 300, 150, 400, 1920, 1080), "left")
	eq(L.EdgeForDrop(800, 500, 300, 22, 1920, 1080), "free")
	local r = L.Reorder({ "a", "b", "c" }, "c", 1)
	eq(table.concat(r, ","), "c,a,b")
	eq(L.Snap(17, 16), 16); eq(L.Snap(25, 16), 32)
end)

------------------------------------------------------------------------
-- LDB host
------------------------------------------------------------------------
local ldb = LibStub("LibDataBroker-1.1")
step("our LibDataBroker-1.1: the published interface", function()
	local seen = {}
	local owner = {}
	ldb.RegisterCallback(owner, "LibDataBroker_AttributeChanged_TestObj_text", function(_, name, key, value) seen[#seen + 1] = value end)
	local o = ldb:NewDataObject("TestObj", { type = "data source", text = "a" })
	check(o and ldb:GetDataObjectByName("TestObj") == o, "lookup")
	eq(ldb:GetNameByDataObject(o), "TestObj")
	check(ldb:NewDataObject("TestObj") == nil, "duplicate name refused")
	o.text = "b"; o.text = "b"; o.text = "c"
	eq(#seen, 2, "change callbacks only on a change")
	local n = 0
	for k in ldb:pairs(o) do n = n + 1 end
	eq(n, 2, "pairs over attributes")
	check(rawget(o, "text") == nil, "proxy stays empty")
	ldb.UnregisterAllCallbacks(owner)
end)

local third
step("a third-party plugin appears, waits off the bars, then shows when placed", function()
	third = ldb:NewDataObject("Other_Plugin", { type = "data source", text = "hello", label = "Other", icon = "Interface\\Icons\\X" })
	flush()
	local rec = ns.Host.plugins.Other_Plugin
	check(rec, "host knows it")
	check(not ns.db.placement.Other_Plugin, "not placed automatically")
	ns.Host:Place("Other_Plugin", 1, 1, "left")
	flush()
	check(rec.button and rec.button:IsShown(), "button shown")
	eq(rec.button.text:GetText(), "hello", "text")
end)

step("text updates are coalesced and cached", function()
	local rec = ns.Host.plugins.Other_Plugin
	local before = MOCK.setText
	third.text = "one"; third.text = "two"; third.text = "three"
	flush()
	eq(rec.button.text:GetText(), "three")
	eq(MOCK.setText - before, 1, "one SetText for three changes in a frame")
	before = MOCK.setText
	ns.Host:RefreshAll()
	eq(MOCK.setText - before, 0, "unchanged text is not set again")
end)

step("widths do not wobble", function()
	local rec = ns.Host.plugins.Other_Plugin
	third.text = "1234567890"; flush()
	local w = rec.button.wantW
	third.text = "123456789"; flush()
	eq(rec.button.wantW, w, "a one-character shrink keeps the width")
	third.text = "1"; flush()
	check(rec.button.wantW < w, "a big shrink is taken")
end)

------------------------------------------------------------------------
-- Error isolation
------------------------------------------------------------------------
step("a broken plugin gets a marker; the bar keeps working", function()
	local bad = ldb:NewDataObject("Broken", { type = "launcher", icon = "x",
		OnClick = function() error("boom") end,
		OnTooltipShow = function() error("tip boom") end })
	flush()
	ns.Host:Place("Broken", 1, 1, "right")
	flush()
	local rec = ns.Host.plugins.Broken
	local b = rec.button
	b:GetScript("OnClick")(b, "LeftButton")
	eq(rec.errors, 1, "error counted")
	check(b.err:IsShown(), "error marker shown")
	check(logHas("Broken"), "reported once in chat")
	b:GetScript("OnEnter")(b)
	eq(rec.errors, 2, "tooltip error counted")
	local found = false
	for _, l in ipairs(MOCK.tip) do if l:find("Error", 1, true) then found = true end end
	check(found, "tooltip shows the error")
	b:GetScript("OnLeave")(b)
	third.text = "still fine"; flush()
	eq(ns.Host.plugins.Other_Plugin.button.text:GetText(), "still fine", "other plugins keep updating")
end)

step("a plugin with nonsense attributes does not break the bar", function()
	local odd = ldb:NewDataObject("Odd", { type = "data source", text = { 1, 2 }, icon = { "x" }, iconCoords = "x", label = 5 })
	flush()
	ns.Host:Place("Odd", 1, 1, "right")
	flush()
	eq(ns.Host.plugins.Odd.button.text:GetText(), "", "table text shows nothing")
	odd.value = 12; odd.suffix = "fps"; flush()
	eq(ns.Host.plugins.Odd.button.text:GetText(), "12 fps", "value + suffix")
end)

step("a widget whose code fails is isolated", function()
	ldb:NewDataObject("WidgetFail", { type = "data source", text = "w" })
	EverlookBar.API.RegisterWidget("WidgetFail", { width = 30, create = function() error("create fails") end,
		update = function() error("update fails") end })
	ns.Host:Place("WidgetFail", 1, 1, "left")
	flush()
	check(ns.Host.plugins.WidgetFail.errors >= 1, "widget error counted")
	check(ns.Host.plugins.WidgetFail.button:IsShown(), "button still shown")
end)

step("a ticker task that keeps failing is quarantined", function()
	local calls = 0
	local t = EverlookBar.API.Every("Flaky", 0.1, function() calls = calls + 1; error("tick fail") end)
	for _ = 1, 60 do MOCK.time = MOCK.time + 0.2; ns.Tick() end
	check(calls == 50, "stopped after 50 errors, ran " .. calls)
	t:Cancel()
end)

------------------------------------------------------------------------
-- Secret values
------------------------------------------------------------------------
step("secret plugin text is shown, never compared or measured", function()
	local rec = ns.Host.plugins.Other_Plugin
	third.text = S("hidden"); flush()
	check(MOCK.isSecret(rec.button.text:GetText()), "secret text was passed to SetText")
	third.text = S("again"); flush()
	third.label = S("lab"); flush()
	third.text = "plain"; flush()
	eq(rec.button.text:GetText(), "plain")
end)

step("modules ignore secret game values", function()
	local oldXP, oldNet, oldMoney = UnitXP, GetNetStats, GetMoney
	UnitXP = function() return S(5) end
	GetNetStats = function() return S(1), S(2), S(3), S(4) end
	GetMoney = function() return S(99) end
	MOCK.pos = "secret"
	MOCK.Fire("PLAYER_XP_UPDATE")
	MOCK.Fire("PLAYER_MONEY")
	MOCK.time = MOCK.time + 2; ns.Tick()
	MOCK.Fire("ZONE_CHANGED")
	flush()
	local xp = ldb:GetDataObjectByName("EverlookBar_XP")
	eq(xp.text, "", "xp text empty when secret")
	local loc = ldb:GetDataObjectByName("EverlookBar_Location").text
	check(not loc:find("%d+%.%d"), "no coordinates when the position is secret: " .. loc)
	UnitXP, GetNetStats, GetMoney = oldXP, oldNet, oldMoney
	MOCK.pos = { 0.4523, 0.6311 }
	MOCK.Fire("PLAYER_XP_UPDATE"); MOCK.Fire("ZONE_CHANGED"); flush()
end)

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
step("XP: percent text, bar widths, hidden at max level", function()
	local xp = ldb:GetDataObjectByName("EverlookBar_XP")
	eq(xp.text, "", "percentage is on the bar, not beside it")
	local w = ns.Host.plugins.EverlookBar_XP.button.widget
	eq(w.label:GetText(), "37.5%", "percentage centred on the bar")
	eq(w.fill:GetWidth(), 160 * 1500 / 4000, "fill width")
	eq(w.rested:GetWidth(), 160 * 2300 / 4000, "rested overlay")
	MOCK.xp.level = 60
	MOCK.Fire("PLAYER_LEVEL_UP"); flush()
	check(not ns.Host.plugins.EverlookBar_XP.button:IsShown(), "hidden at max level")
	MOCK.xp.level = 20
	MOCK.Fire("PLAYER_LEVEL_UP"); flush()
	check(ns.Host.plugins.EverlookBar_XP.button:IsShown(), "back below max")
end)

step("Performance: compact text, rebuilt only on change, memory only on hover", function()
	local perf = ldb:GetDataObjectByName("EverlookBar_Performance")
	MOCK.time = MOCK.time + 2; ns.Tick()
	check(perf.text:find("60") and perf.text:find("fps") and perf.text:find("52") and perf.text:find("ms"), "text: " .. perf.text)
	local updates = MOCK.memUpdates or 0
	for _ = 1, 30 do MOCK.time = MOCK.time + 1; ns.Tick() end
	eq(MOCK.memUpdates or 0, updates, "no memory scans from the ticker")
	ns.modules.perf.Tooltip(GameTooltip)
	check((MOCK.memUpdates or 0) == updates + 1, "hover reads memory")
	local all = table.concat(MOCK.tip, "\n")
	check(all:find("Packet loss and jitter"), "honest about packet loss / jitter")
	check(all:find("OtherAddon"), "per-addon CPU from the game's profiler")
end)

step("Location: zone, subzone, coordinates; ticker only while moving", function()
	local loc = ldb:GetDataObjectByName("EverlookBar_Location")
	check(loc.text:find("Hillsbrad Foothills: Tarren Mill", 1, true) and loc.text:find("45.2, 63.1", 1, true), "text: " .. loc.text)
	local task = ns.modules.location.task
	check(not task.active, "no ticks standing still")
	MOCK.Fire("PLAYER_STARTED_MOVING")
	check(task.active, "ticking while moving")
	MOCK.pos = { 0.5, 0.25 }
	MOCK.time = MOCK.time + 0.3; ns.Tick()
	check(loc.text:find("50.0, 25.0", 1, true), "moved: " .. loc.text)
	MOCK.Fire("PLAYER_STOPPED_MOVING")
	check(not task.active, "stops with you")
	MOCK.pos = nil
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	check(not loc.text:find("%d+%.%d"), "no coordinates in an instance: " .. loc.text)
	MOCK.pos = { 0.4523, 0.6311 }
end)

step("Durability, mail, bags, gold", function()
	eq(ldb:GetDataObjectByName("EverlookBar_Durability").text, "|cffef5d5d10%|r", "lowest slot")
	eq(#ns.modules.durability.rows, 3, "three slots with durability")
	eq(ldb:GetDataObjectByName("EverlookBar_Mail").text, "|cff8d94a3No mail|r")
	MOCK.mail = true; MOCK.Fire("UPDATE_PENDING_MAIL")
	check(ldb:GetDataObjectByName("EverlookBar_Mail").text:find("New mail"), "new mail")
	ns.modules.mail.Tooltip(GameTooltip)
	check(table.concat(MOCK.tip, " "):find("Thrall"), "senders listed")
	local bags = ldb:GetDataObjectByName("EverlookBar_Bags").text
	eq(bags, "|cffffd25a3|r/26", "profession bag counted apart")
	eq(ns.modules.gold.Format(1234567, false), "123|cffffd25ag|r 45|cffc7c7cfs|r", "gold format")
	MOCK.money = 1234567 + 500; MOCK.Fire("PLAYER_MONEY")
	ns.modules.gold.Tooltip(GameTooltip)
	check(table.concat(MOCK.tip, " "):find("+", 1, true), "session change")
end)

step("Clock: off by default; switched on from chat it places itself", function()
	check(not ns.modules.clock.running, "off")
	slash("clock.enabled on")
	flush()
	check(ns.modules.clock.running, "on")
	check(ns.db.placement.EverlookBar_Clock, "placed when switched on")
	eq(#ldb:GetDataObjectByName("EverlookBar_Clock").text, 5, "hh:mm")
end)

step("Calendar: date maths, events, invites, answering", function()
	local C = ns.modules.calendar
	local y, m, d = C.AddDays(2026, 11, 30, 1); eq(y .. "-" .. m .. "-" .. d, "2026-12-1")
	y, m, d = C.AddDays(2024, 2, 28, 1); eq(m .. "-" .. d, "2-29", "leap year")
	y, m, d = C.AddDays(2026, 12, 31, 1); eq(y .. "-" .. m .. "-" .. d, "2027-1-1")
	MOCK.dayEvents["2026-11-30"] = {
		{ title = "Molten Core", calendarType = "GUILD_EVENT", startTime = { hour = 20, minute = 0 }, endTime = {}, inviteStatus = 0, inviteType = 0 },
		{ title = S("secret title"), calendarType = "PLAYER", startTime = { hour = 21, minute = 0 }, endTime = {} },
	}
	MOCK.dayEvents["2026-12-2"] = {
		{ title = "Darkmoon Faire", calendarType = "HOLIDAY", sequenceType = "START", startTime = { hour = 0, minute = 0 }, endTime = { month = 12, monthDay = 8 } },
	}
	MOCK.dayEvents["2026-12-3"] = {
		{ title = "Darkmoon Faire", calendarType = "HOLIDAY", sequenceType = "ONGOING", startTime = { hour = 0, minute = 0 }, endTime = { month = 12, monthDay = 8 } },
	}
	MOCK.pending = 1
	MOCK.Fire("CALENDAR_UPDATE_EVENT_LIST")
	eq(#C.events, 2, "secret event skipped, holiday once")
	local text = ldb:GetDataObjectByName("EverlookBar_Calendar").text
	check(text:find("^%d%d:%d%d, Monday, 30%-nov%-2026") and text:find("[1]", 1, true), "full clock text: " .. text)
	ns:ModuleDB("calendar").style = "next"; C.dirty = true; C:Render()
	text = ldb:GetDataObjectByName("EverlookBar_Calendar").text
	check(text:find("Molten Core 20:00", 1, true) and text:find("[1]", 1, true), "text: " .. text)
	ns:ModuleDB("calendar").style = "full"; C.dirty = true; C:Render()
	C.Tooltip(GameTooltip)
	local tip = table.concat(MOCK.tip, "\n")
	check(tip:find("Invites waiting") and tip:find("until Dec 8", 1, true), "tooltip:\n" .. tip)
	MOCK.combat = true
	check(not C:Respond(C.events[1], "accept"), "no answers in combat")
	MOCK.combat = false
	check(C:Respond(C.events[1], "accept"), "answered")
	eq(table.concat(MOCK.calls, ","), "select 2026-11-30 1,accept")
end)

step("Calendar: hides itself when the API is missing", function()
	local saved = C_Calendar
	C_Calendar = nil
	check(not ns.modules.calendar:Available(), "unavailable")
	C_Calendar = saved
end)

------------------------------------------------------------------------
-- Minimap
------------------------------------------------------------------------
step("minimap: decorations hidden, buttons collected, pins left alone", function()
	local mm = ns.modules.minimap
	check(mm.running, "minimap module running")
	check(not mm.stepAside, "no rival")
	check(not MinimapZoneTextButton:IsShown(), "zone text hidden")
	check(not GameTimeFrame:IsShown(), "day/night hidden")
	check(not MinimapCluster.Diel:IsShown(), "Diel ring found by key and hidden")
	check(not MinimapCluster.MinimapContainer.PlayerCoords:IsShown(), "Blizzard's coordinates under the minimap hidden")
	-- Blizzard's pieces keep their parents: their own code calls into the parent
	eq(MinimapZoneTextButton:GetParent(), MinimapCluster, "zone text keeps its parent")
	eq(MinimapCluster.IndicatorFrame.MailFrame:GetParent(), MinimapCluster.IndicatorFrame, "mail icon keeps its parent")
	eq(MinimapCluster.MinimapContainer.PlayerCoords:GetParent(), MinimapCluster.MinimapContainer, "coords keep their parent")
	eq(Minimap:GetParent(), mm.holder, "minimap in our holder")
	local btn = CreateFrame("Button", "SomeAddonMinimapButton", Minimap); btn:SetSize(31, 31)
	local pin = CreateFrame("Button", "QuestieFrame12", Minimap); pin:SetSize(16, 16)
	local blizz = CreateFrame("Button", "MiniMapLFGFrame", Minimap); blizz:SetSize(32, 32)
	MOCK.Fire("ADDON_LOADED", "SomeAddon"); flush()
	mm:ApplyAll(); flush()
	eq(btn:GetParent(), mm.drawer, "addon button in the drawer")
	eq(pin:GetParent(), Minimap, "map pin left alone")
	eq(blizz:GetParent(), Minimap, "Blizzard button left alone")
	slash("minimap ignore SomeAddonMinimapButton")
	eq(btn:GetParent(), Minimap, "released on ignore")
end)

step("minimap: Blizzard's mail event after we hid the mail icon (UPDATE_PENDING_MAIL regression)", function()
	local mm = ns.modules.minimap
	local mail = MinimapCluster.IndicatorFrame.MailFrame
	eq(mm:Mode("mail"), "hide", "mail icon hidden by default")
	MOCK.mail = true
	MOCK.Fire("UPDATE_PENDING_MAIL") -- runs Blizzard's handler: SetShown + GetParent():Layout()
	MOCK.Fire("CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS")
	check((MinimapCluster.IndicatorFrame.__layouts or 0) >= 2, "Blizzard's Layout() ran on the real parent")
	check(not mail:IsShown(), "still hidden after Blizzard showed it")
	MOCK.BlizzardShowsAgain()
	check(not MinimapZoneTextButton:IsShown() and not MinimapCluster.MinimapContainer.PlayerCoords:IsShown(), "Show() from Blizzard is undone")
	check(not mail:IsShown(), "mail too")
	-- "show" gives it back the way Blizzard wants it: mail waiting, so shown
	ns:ModuleDB("minimap").elements.mail = "show"
	mm:ApplyElements()
	check(mail:IsShown(), "mail icon back (there is mail)")
	ns:ModuleDB("minimap").elements.mail = nil
	mm:ApplyElements()
	check(not mail:IsShown(), "hidden again")
	MOCK.mail = false
	MOCK.Fire("UPDATE_PENDING_MAIL")
	ns:ModuleDB("minimap").elements.mail = "show"
	mm:ApplyElements()
	check(not mail:IsShown(), "no mail: Blizzard's wish (hidden) kept on show")
	ns:ModuleDB("minimap").elements.mail = "move"
	mm:ApplyElements()
	eq(mail:GetParent(), MinimapCluster.IndicatorFrame, "moving keeps the parent")
	MinimapCluster.IndicatorFrame.MailFrame:SetPoint("LEFT", MinimapCluster.IndicatorFrame, "LEFT", 0, 0) -- Blizzard's Layout()
	local _, rel = mail:GetPoint(1)
	eq(rel, Minimap, "re-anchored to the minimap after Blizzard's layout")
	ns:ModuleDB("minimap").elements.mail = nil
	mm:ApplyElements()
	-- no piece of Blizzard's ever sits under a frame of ours
	for _, w in ipairs(MOCK.widgets) do
		local p = w.__parent
		if w.__name and not w.__name:find("^EverlookBar") and not w.__name:find("Minimap$") and p == mm.hider then
			error(w.__name .. " re-parented to our hidden frame")
		end
	end
end)

step("minimap: round and square masks, border behind the map", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	eq(db.shape, "round", "round by default")
	eq(Minimap.__mask, "Interface\\AddOns\\EverlookBar\\Media\\MinimapRound", "our own round mask")
	local f = io.open(ROOT .. "/Media/MinimapRound.tga", "rb")
	check(f, "the round mask ships with the addon"); f:close()
	eq(GetMinimapShape(), "ROUND")
	local b = mm.borderFrame
	eq(b:GetFrameStrata(), "BACKGROUND", "border sits behind the minimap")
	check(b.tex.__masks and b.tex.__masks[1] == b.mask, "border cut to the shape")
	eq(b.mask.__texture, mm.MASKS.round)
	eq(b:GetWidth(), 140 + 2 * db.borderSize, "border a little larger than the map")
	eq(Minimap:GetFrameStrata(), "LOW", "minimap keeps Blizzard's strata")
	db.shape = "square"; mm:Redraw()
	eq(Minimap.__mask, "Interface\\Buttons\\WHITE8X8", "square mask")
	eq(b.mask.__texture, mm.MASKS.square)
	eq(GetMinimapShape(), "SQUARE")
	db.shape = "round"; db.borderSize = 5; mm:Redraw()
	eq(Minimap.__mask, mm.MASKS.round, "back to round")
	eq(b:GetWidth(), 150, "border thickness")
	db.border = false; mm:Redraw()
	check(not b:IsShown(), "border off")
	db.border = true; db.borderSize = 2; mm:Redraw()
	check(b:IsShown(), "border on")
end)

step("minimap: changes wait for combat to end", function()
	local mm = ns.modules.minimap
	MOCK.combat = true
	ns:ModuleDB("minimap").scale = 1.3
	mm:Redraw()
	check(mm.holder:GetScale() ~= 1.3, "nothing applied in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(true)
end)

step("minimap: steps aside for BasicMinimap", function()
	local mm = ns.modules.minimap
	MOCK.loaded.BasicMinimap = true
	mm:DetectRivals()
	eq(mm.stepAside, "BasicMinimap")
	MOCK.loaded.BasicMinimap = nil
	mm:DetectRivals()
	check(not mm.stepAside, "back")
end)

------------------------------------------------------------------------
-- Settings window, chat, API
------------------------------------------------------------------------
step("bare /ebar opens the window; every page builds", function()
	slash("")
	check(ns.app:IsShown(), "window shown")
	for _, id in ipairs(ns.app.order) do ns.app:ShowSection(id) end
	slash("")
	check(not ns.app:IsShown(), "toggled closed")
end)

step("chat: bars, bar settings, plugins", function()
	slash("bar add left")
	eq(#ns.db.bars, 2, "added")
	eq(ns.db.bars[2].laneSize, 150, "side bar column width")
	slash("bar1.lanes 2")
	eq(ns.db.bars[1].lanes, 2, "bar1.lanes")
	slash("bar2.edge right")
	eq(ns.db.bars[2].edge, "right")
	slash("bar2.edge top")
	eq(ns.db.bars[2].laneSize, 22, "row height back for a top bar")
	slash("place gold 2 left")
	eq(ns.db.placement.EverlookBar_Gold.bar, 2)
	slash("xp.width 200")
	eq(ns:ModuleDB("xp").width, 200)
	slash("bar delete 2")
	eq(#ns.db.bars, 1, "deleted")
	check(ns.db.placement.EverlookBar_Gold == nil, "its plugins came off")
	slash("perf")
	check(logHas("memory:"), "perf printed")
	slash("nonsense")
	check(lastLog():find("unknown"), "unknown command message")
end)

step("unlock mode: refused in combat, drag plugin onto a bar", function()
	MOCK.combat = true
	slash("unlock")
	check(not ns.Unlock.active, "no unlock in combat")
	MOCK.combat = false
	slash("unlock")
	check(ns.Unlock.active, "unlocked")
	local rec = ns.Host.plugins.Other_Plugin
	ns.Unlock:StartPluginDrag(rec)
	MOCK.cursorX, MOCK.cursorY = 1800, 1075 -- right end of the top bar
	ns.Unlock:StopPluginDrag(rec)
	eq(ns.db.placement.Other_Plugin.group, "right", "dropped in the right group")
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(not ns.Unlock.active, "combat locks")
end)

step("API: version, settings from another addon, placement", function()
	local API = EverlookBar.API
	check(API.GetVersion() >= 1, "version")
	local changed
	local get = API.RegisterSettings("myaddon", "My Addon", { { key = "size", type = "number", label = "Size", min = 1, max = 10, default = 3, onChange = function(v) changed = v end } })
	eq(get("size"), 3, "default")
	slash("myaddon.size 7")
	eq(get("size"), 7, "set from chat"); eq(changed, 7, "onChange called")
	local b, g = API.GetPlacement("Other_Plugin")
	eq(b, 1); eq(g, "right")
	check(API.Place("Other_Plugin", 1, "left"), "place")
	eq(select(2, API.GetPlacement("Other_Plugin")), "left")
	eq(API.GetNumBars(), 1)
end)

step("unknown events are skipped, not raised", function()
	MOCK.unknownEvents = { NOT_A_REAL_EVENT = true }
	check(ns.On("NOT_A_REAL_EVENT", {}, function() end) == false, "skipped")
	MOCK.unknownEvents = nil
end)

------------------------------------------------------------------------
-- Cost
------------------------------------------------------------------------
step("cost: idle ticks make no garbage; time per tick", function()
	for _ = 1, 20 do MOCK.time = MOCK.time + 1; ns.Tick() end -- settle
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 1000 do MOCK.time = MOCK.time + 0.1; ns.Tick() end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	if grew >= 4 then
		for i, t in ipairs(ns.tasks) do
			if t.active then
				collectgarbage("collect"); collectgarbage("stop")
				local b0 = collectgarbage("count")
				for _ = 1, 100 do t.fn(t, MOCK.time) end
				print("         task " .. i .. " (" .. tostring(t.owner and t.owner.name) .. "): " .. string.format("%.2f KB per 100 runs", collectgarbage("count") - b0))
				collectgarbage("restart")
			end
		end
	end
	check(grew < 4, string.format("idle ticks allocated %.1f KB", grew))
	local t0 = os.clock()
	for _ = 1, 10000 do MOCK.time = MOCK.time + 0.1; ns.Tick() end
	local perTick = (os.clock() - t0) / 10000 * 1000
	print(string.format("         addon memory after load: %.0f KB (Lua heap growth, libraries included)", memLoaded - memStart))
	print(string.format("         idle garbage per 1000 ticks: %.2f KB", grew))
	print(string.format("         one shared tick (all built-ins on, standing still): %.4f ms in plain Lua 5.1", perTick))
	print(string.format("         = %.4f ms per frame at 60 fps (ticks run 10 times a second)", perTick * 10 / 60))
end)

print(string.format("\n%d passed, %d failed", passes, #failures))
return #failures
