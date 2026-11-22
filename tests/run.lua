-- Offline tests for EverlookDB Bar: loads the addon in TOC order against wowmock.lua and checks the LDB host, error
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
local ALLOWED = { EverlookBar = true, EverlookBarDB = true, SLASH_EVERLOOKBAR1 = true, SLASH_EVERLOOKBAR2 = true, GetMinimapShape = true }
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
	-- a player from before the calendar's default changed: the old default moves to the new one
	-- and who switched 0.4.0's taskbar on: its bar and settings go
	EverlookBarDB = { version = 1, modules = { calendar = { style = "next" } },
		bars = { { name = "Top bar" }, { name = "Taskbar", kind = "taskbar", edge = "bottom" } }, taskbar = { on = true } }
	MOCK.Fire("ADDON_LOADED", ADDON)
	check(ns.db.taskbar == nil, "taskbar settings dropped")
	eq(EverlookBarDB.modules.calendar.style, "full", "old calendar default migrated")
	eq(EverlookBarDB.version, 4, "settings version")
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
	-- memory on the bar: still no scans from the ticker; the bar shows what the last hover read
	ns:ModuleDB("perf").memory = true
	for _ = 1, 90 do MOCK.time = MOCK.time + 1; ns.Tick() end
	eq(MOCK.memUpdates or 0, updates, "memory on the bar: no timed scans")
	ns.modules.perf.Tooltip(GameTooltip)
	check((MOCK.memUpdates or 0) == updates + 1, "hover reads memory")
	MOCK.time = MOCK.time + 1; ns.Tick()
	check(perf.text:find("MB", 1, true), "bar shows the hovered reading: " .. perf.text)
	ns:ModuleDB("perf").memory = false
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

step("Quest log: in log out of the most you can have, coloured as it fills", function()
	local q = function() return ldb:GetDataObjectByName("EverlookBar_Quests").text end
	eq(q(), "38/45", "headers are not counted")
	MOCK.quests = 43; MOCK.Fire("QUEST_LOG_UPDATE"); flush()
	eq(q(), "|cffffd25a43|r/45", "yellow with 2 left")
	MOCK.quests = 45; MOCK.Fire("QUEST_ACCEPTED"); flush()
	eq(q(), "|cffef5d5d45|r/45", "red when full")
	eq(ns.modules.quests.Text(40, 45, "left", 3), "5 left", "slots-left style")
	ns.modules.quests.Tooltip(GameTooltip)
	check(table.concat(MOCK.tip, " "):find("45 of 45"), "tooltip count")
	MOCK.quests = 38; MOCK.Fire("QUEST_LOG_UPDATE"); flush()
end)

step("Professions: skills on the bar, the cap coloured, weapon skills left out", function()
	local P = ns.modules.professions
	local obj = ldb:GetDataObjectByName("EverlookBar_Professions")
	eq(ns.db.placement.EverlookBar_Professions.group, "left", "placed on the left by default")
	eq(#P.rows, 6, "Mining, Herbalism (once, not twice), Cooking, First Aid, Fishing, Riding; no Swords")
	eq(P.rows[1].name .. "," .. P.rows[2].name .. "," .. P.rows[3].name, "Herbalism,Mining,Cooking", "primary first, then secondary")
	eq(#P.shown, 2, "only the two main professions on the bar by default")
	-- the rest of this step shows the secondary skills too
	slash("professions.cooking on"); slash("professions.firstaid on"); slash("professions.fishing on")
	eq(#P.shown, 5, "Riding is off by default")
	local db = ns:ModuleDB("professions")
	eq(P.Text(db), "Herb |cffff8c40150|r  Mining 187  Cook 225  Aid |cffff8c4075|r  Fish 1", "short names, cap coloured")
	eq(obj.text, "", "the pieces draw it")
	local b = ns.Host.plugins.EverlookBar_Professions.button
	check(b:IsShown(), "button shown")
	eq(P.pieces[2].text:GetText(), "Mining 187", "one piece per profession")
	eq(P.pieces[2].id, 186, "piece knows its skill")
	check(P.widgetW > 0 and b.wantW >= P.widgetW, "button as wide as its pieces")
	slash("professions.showmax on")
	eq(P.pieces[2].text:GetText(), "Mining 187/225", "with the cap")
	eq(P.pieces[1].text:GetText(), "Herb |cffff8c40150/150|r", "at cap: coloured")
	slash("professions.markcap off")
	eq(P.pieces[1].text:GetText(), "Herb 150/150", "colouring off")
	slash("professions.markcap on"); slash("professions.showmax off")
	slash("professions.riding on")
	eq(#P.shown, 6, "Riding shown")
	slash("professions.riding off"); slash("professions.fishing off"); slash("professions.primary off")
	eq(P.Text(db), "Cook 225  Aid |cffff8c4075|r", "only the chosen ones")
	slash("professions.primary on"); slash("professions.fishing on")
	slash("professions.names full")
	eq(P.pieces[1].text:GetText(), "Herbalism |cffff8c40150|r", "full names")
	slash("professions.names none")
	eq(P.pieces[2].text:GetText(), "187", "icon only")
	slash("professions.icons off")
	eq(P.pieces[2].text:GetText(), "Mining 187", "no icon and no name falls back to the short name")
	slash("professions.icons on"); slash("professions.names short")
	-- a skill-up, coalesced
	MOCK.skills[2].rank = 188
	MOCK.Fire("CHAT_MSG_SKILL"); MOCK.Fire("SKILL_LINES_CHANGED"); flush()
	eq(P.pieces[2].text:GetText(), "Mining 188", "skill-up shown")
	-- under a collapsed header: found by ID
	local mining = table.remove(MOCK.skills, 2)
	MOCK.skills[1].isCollapsed = true
	MOCK.skillsHidden[186] = mining
	MOCK.Fire("SKILL_LINES_CHANGED"); flush()
	check(P.Row(186), "Mining found under a collapsed header")
	table.insert(MOCK.skills, 2, mining); MOCK.skills[1].isCollapsed = false; MOCK.skillsHidden[186] = nil
	MOCK.skills[2].rank = 187
	MOCK.Fire("SKILL_LINES_CHANGED"); flush()
	eq(P.pieces[2].text:GetText(), "Mining 187")
	-- secret skill values are skipped, never compared
	local old = MOCK.skills[6].rank
	MOCK.skills[6].rank = S(225)
	MOCK.Fire("SKILL_LINES_CHANGED"); flush()
	check(not P.Row(185), "secret rank skipped")
	MOCK.skills[6].rank = old
	MOCK.Fire("SKILL_LINES_CHANGED"); flush()
	ns.modules.professions.Tooltip(GameTooltip)
	local tip = table.concat(MOCK.tip, "\n")
	check(tip:find("Herbalism |cff8d94a3(no window)|r | 150/150  at cap", 1, true), "tooltip: no window, at cap\n" .. tip)
	check(tip:find("Fishing |cff8d94a3(no window)|r | 1/75 (+25)", 1, true), "tooltip: gear bonus")
	check(tip:find("Riding", 1, true), "tooltip lists every profession")
	check(tip:find("At cap: a trainer", 1, true), "cap hint, no invented skill level")
	check(tip:find("Click a profession: open it. Right-click: every profession.", 1, true), "click hint")
end)

step("Professions: a click opens that profession; no window, nothing; right-click lists them", function()
	local P = ns.modules.professions
	local b = ns.Host.plugins.EverlookBar_Professions.button
	MOCK.opened = {}
	local mining, herb, cook = P.pieces[2], P.pieces[1], P.pieces[3]
	-- left-click a profession: it opens, no list
	mining:GetScript("OnClick")(mining, "LeftButton")
	eq(MOCK.opened[1], 186, "left-click on Mining opens Mining")
	check(not ns.UI.IsPopupShown(), "no list on a left-click")
	-- left-click on one without a window (Herbalism): the list instead
	herb:GetScript("OnClick")(herb, "LeftButton")
	check(ns.UI.IsPopupShown(), "no window: the list")
	eq(#MOCK.opened, 1, "nothing opened for Herbalism")
	ns.UI.ClosePopup()
	-- the button around the pieces (no profession under the mouse): the list
	b:GetScript("OnClick")(b, "LeftButton")
	check(ns.UI.IsPopupShown(), "the plugin's own click: the list")
	ns.UI.ClosePopup()
	P.MenuPick(185)
	eq(MOCK.opened[2], 185, "picking Cooking opens Cooking")
	-- the open one again: closed
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	MOCK.openProfession = 186
	P.MenuPick(186)
	eq(MOCK.opened[3], "close", "picking the open profession closes it")
	ProfessionsFrame:Hide(); MOCK.openProfession = nil
	-- right-click: every profession, those without a window greyed out
	herb:GetScript("OnClick")(herb, "RightButton")
	check(ns.UI.IsPopupShown(), "menu shown")
	local herbItem, cookItem
	for _, it in ipairs(P.menuItems) do
		if it.text:find("^Herbalism") then herbItem = it end
		if it.text:find("^Cooking") then cookItem = it end
	end
	check(herbItem and herbItem.title, "Herbalism listed, not clickable")
	check(cookItem and cookItem.value == 185, "Cooking clickable")
	ns.UI.ClosePopup()
	P.MenuPick(129)
	eq(MOCK.opened[#MOCK.opened], 129, "menu opens First Aid")
	MOCK.openFails = true
	MOCK.log = {}
	P.MenuPick(185)
	check(logHas("did not open Cooking"), "says so when the game refuses")
	MOCK.openFails = nil
	-- unlock mode: clicks do nothing
	ns.Unlock.active = true
	local n = #MOCK.opened
	mining:GetScript("OnClick")(mining, "LeftButton")
	eq(#MOCK.opened, n, "no click in unlock mode")
	ns.Unlock.active = false
end)

step("Reputation bar: watched faction, colours per standing, a chosen faction, width maths", function()
	local R = ns.modules.reputation
	local obj = ldb:GetDataObjectByName("EverlookBar_Reputation")
	local list = ns.Host:GroupList(1, 1, "center")
	eq(list[1] .. "," .. list[2], "EverlookBar_XP,EverlookBar_Reputation", "next to the XP bar")
	eq(R.state.name, "Stormwind", "follows the watched faction by default")
	check(R.state.watched, "watched")
	eq(R.state.value .. "/" .. R.state.max, "1500/6000", "value within the standing")
	local w = ns.Host.plugins.EverlookBar_Reputation.button.widget
	eq(w.fill:GetWidth(), 160 * 0.25, "fill width")
	eq(w.label:GetText(), "Stormwind: Friendly", "name and standing in the bar")
	eq(obj.text, "", "text in the bar, not beside it")
	-- colours: the game's own when it has them, else the classic ones
	eq(w.fill.__color[1] .. "," .. w.fill.__color[2], "0,0.6", "friendly is green (fallback)")
	local RED, ORANGE, YELLOW, GREEN = { r = 0.8, g = 0.1, b = 0.1 }, { r = 0.9, g = 0.5, b = 0 }, { r = 1, g = 1, b = 0 }, { r = 0, g = 0.7, b = 0 }
	FACTION_BAR_COLORS = { RED, RED, ORANGE, YELLOW, GREEN, GREEN, GREEN, GREEN }
	local want = { "0.8", "0.8", "0.9", "1", "0", "0", "0", "0" }
	for standing = 1, 8 do eq(tostring((R.Color(standing))), want[standing], "standing " .. standing) end
	eq(select(2, R.Color(4)), 1, "neutral yellow")
	eq(tostring((R.Color(S(3)))), "1", "a secret standing reads as neutral")
	FACTION_BAR_COLORS = nil
	eq(select(2, R.Color(3)), 0.27, "unfriendly orange (fallback)")
	eq(R.Color(2), 0.8, "hostile red (fallback)")
	-- a chosen faction, from chat
	slash("reputation.faction ironforge")
	eq(ns:ModuleDB("reputation").faction, 47, "picked by name")
	eq(R.state.name, "Ironforge"); check(not R.state.watched, "chosen, not watched")
	eq(w.label:GetText(), "Ironforge: Honored")
	MOCK.watched = 529; MOCK.Fire("UPDATE_FACTION"); flush()
	eq(R.state.name, "Ironforge", "a chosen faction ignores the watched one")
	slash("reputation.faction watched")
	eq(R.state.name, "Argent Dawn", "back to the watched faction")
	R.Tooltip(GameTooltip)
	local tip = table.concat(MOCK.tip, "\n")
	check(tip:find("Standing | Exalted", 1, true), "exalted\n" .. tip)
	check(not tip:find("To ", 1, true), "no next standing after Exalted")
	MOCK.watched = 72; MOCK.Fire("UPDATE_FACTION"); flush()
	R.Tooltip(GameTooltip)
	tip = table.concat(MOCK.tip, "\n")
	check(tip:find("To Honored | 4,500", 1, true), "amount to the next standing\n" .. tip)
	check(tip:find("watched faction", 1, true) and tip:find("Right-click", 1, true), "source and click hint")
	-- an unknown faction falls back to the watched one; none watched says so
	ns:ModuleDB("reputation").faction = 99999; R:Update(); flush()
	eq(R.state.name, "Stormwind", "unknown faction: watched instead")
	ns:ModuleDB("reputation").faction = "watched"
	MOCK.watched = nil; MOCK.Fire("UPDATE_FACTION"); flush()
	check(not ns.Host:Wanted("EverlookBar_Reputation"), "none watched and none picked: takes no room")
	MOCK.watched = 72; MOCK.Fire("UPDATE_FACTION"); flush()
	check(ns.Host:Wanted("EverlookBar_Reputation"), "back when a faction is watched")
	-- text options
	slash("reputation.showvalue on"); slash("reputation.showpercent on")
	eq(w.label:GetText(), "Stormwind: Friendly 1,500/6,000 25%")
	slash("reputation.showname off"); slash("reputation.showstanding off")
	eq(w.label:GetText(), "1,500/6,000 25%")
	slash("reputation.textinbar off")
	eq(obj.text, "1,500/6,000 25%", "text beside the bar")
	eq(w.label:GetText(), "", "nothing in the bar")
	slash("reputation.textinbar on"); slash("reputation.showname on"); slash("reputation.showstanding on")
	slash("reputation.showvalue off"); slash("reputation.showpercent off")
	-- width maths
	slash("reputation.width 200")
	eq(w.fill:GetWidth(), 50, "a quarter of 200")
	eq(R.FillWidth({ valid = true, value = 0, max = 0 }, 120), 120, "no room left: full bar")
	eq(R.FillWidth({ valid = true, value = 3000, max = 6000 }, 100), 50, "half")
	eq(R.FillWidth({ valid = true, value = 9000, max = 6000 }, 100), 100, "never past the end")
	eq(R.FillWidth({ valid = false }, 100), 0.01, "no data: empty")
	slash("reputation.width 160")
	-- at max level the XP bar hides; the reputation bar stays
	MOCK.xp.level = 60; MOCK.Fire("PLAYER_LEVEL_UP"); flush()
	check(not ns.Host.plugins.EverlookBar_XP.button:IsShown(), "XP hidden at max level")
	check(ns.Host.plugins.EverlookBar_Reputation.button:IsShown(), "reputation stays")
	MOCK.xp.level = 20; MOCK.Fire("PLAYER_LEVEL_UP"); flush()
	-- clicks
	local b = ns.Host.plugins.EverlookBar_Reputation.button
	b:GetScript("OnClick")(b, "LeftButton")
	eq(MOCK.toggled, "ReputationFrame", "left-click opens the reputation panel")
	b:GetScript("OnClick")(b, "RightButton")
	check(ns.UI.IsPopupShown(), "right-click: the faction list")
	ns.UI.ClosePopup()
end)

step("Blizzard panels open from secure code (no taint on the player frame)", function()
	local SC = ns.SecureClick
	local microClicks = 0
	CharacterMicroButton = CreateFrame("Button", "CharacterMicroButton")
	CharacterMicroButton:SetScript("OnClick", function() microClicks = microClicks + 1 end)
	-- Durability: the cover lays a secure "click the character micro button" over the plugin
	local b = ns.Host.plugins.EverlookBar_Durability.button
	b.__left, b.__bottom, b.__w, b.__h = 300, 1050, 60, 22
	MOCK.toggled = nil
	b:GetScript("OnEnter")(b)
	local c = SC:Frame()
	check(c and c:IsShown(), "cover shown over the plugin")
	eq(SC:Owner(), b, "cover's owner")
	eq(c:GetAttribute("type1"), "click", "secure click")
	eq(c:GetAttribute("clickbutton1"), CharacterMicroButton, "clicks the micro button")
	local p = c.__points[1]
	eq(p[2], UIParent, "anchored to UIParent, never to the bar's button")
	eq(p[4], 300, "same place as the button"); eq(c.__w, 60, "same width")
	c.__scripts.PostClick(c, "LeftButton")
	eq(MOCK.toggled, nil, "the left click is not run again from addon code")
	c.__scripts.OnLeave(c)
	check(not c:IsShown() and SC:Owner() == nil, "cover goes when the mouse leaves")
	-- in combat no new cover, and the plain click does not open the panel from tainted code
	MOCK.combat = true
	b:GetScript("OnEnter")(b)
	check(not c:IsShown(), "no cover made in combat")
	b:GetScript("OnClick")(b, "LeftButton")
	eq(MOCK.toggled, nil, "no ToggleCharacter in combat")
	b:GetScript("OnLeave")(b)
	MOCK.combat = false
	-- without the micro button the old path still works out of combat
	CharacterMicroButton = nil
	b:GetScript("OnEnter")(b)
	check(not c:IsShown(), "no cover without a micro button")
	b:GetScript("OnClick")(b, "LeftButton")
	eq(MOCK.toggled, "PaperDollFrame", "falls back to the panel function")
	b:GetScript("OnLeave")(b)
	CharacterMicroButton = _G.CharacterMicroButton or CreateFrame("Button", "CharacterMicroButton")
	-- Reputation: a /click macro opens the character panel on the reputation tab; right-click stays the plugin's
	CharacterFrame = CreateFrame("Frame", "CharacterFrame"); CharacterFrame:Hide()
	CharacterFrameTab1 = CreateFrame("Button", "CharacterFrameTab1"); CharacterFrameTab1:SetText("Character")
	CharacterFrameTab2 = CreateFrame("Button", "CharacterFrameTab2"); CharacterFrameTab2:SetText("Reputation")
	local rb = ns.Host.plugins.EverlookBar_Reputation.button
	rb:GetScript("OnEnter")(rb)
	eq(c:GetAttribute("type1"), "macro", "reputation: macro")
	eq(c:GetAttribute("macrotext1"), "/click CharacterMicroButton\n/click CharacterFrameTab2", "opens on the reputation tab")
	c.__scripts.PostClick(c, "RightButton")
	check(ns.UI.IsPopupShown(), "right-click still lists the factions")
	ns.UI.ClosePopup()
	c.__scripts.OnLeave(c)
	CharacterFrame:Show()
	rb:GetScript("OnEnter")(rb)
	eq(c:GetAttribute("macrotext1"), "/click CharacterFrameTab2", "panel open on another tab: switch tab")
	c.__scripts.OnLeave(c)
	-- unlock mode: no cover (plugins are dragged)
	ns.Unlock.active = true
	rb:GetScript("OnEnter")(rb)
	check(not c:IsShown(), "no cover in unlock mode")
	rb:GetScript("OnLeave")(rb)
	ns.Unlock.active = false
	CharacterFrame, CharacterFrameTab1, CharacterFrameTab2, CharacterMicroButton = nil, nil, nil, nil
	-- no built-in module calls a panel function outside a secure fallback
	for _, f in ipairs({ "Durability", "Reputation", "Quests", "Location" }) do
		local src = assert(io.open(ROOT .. "/Modules/" .. f .. ".lua")):read("*a")
		check(src:find("ebarSecure", 1, true), f .. " has a secure click")
	end
end)

step("Reputation bar: the faction list, grouped, flat or by header as room allows", function()
	local R = ns.modules.reputation
	local items = R.Items(100)
	local t = {}
	for _, it in ipairs(items) do t[#t + 1] = (it.title and "#" or "") .. it.text end
	eq(table.concat(t, ","), "Watched faction (the game's own),#Alliance,Ironforge,Stormwind,#Other,Argent Dawn,Bloodsail Buccaneers,Booty Bay,Wintersaber Trainers", "grouped, A-Z inside")
	check(MOCK.factions[4].isCollapsed, "a collapsed header is closed again after reading")
	items = R.Items(8)
	eq(#items, 7, "too tall grouped: A-Z without headers")
	check(not items[2].title, "no header rows")
	items = R.Items(5)
	eq(#items, 3, "too tall even flat: one row per header")
	eq(items[3].value, "group:2")
	R.Pick("group:2")
	check(ns.UI.IsPopupShown(), "a header opens its factions")
	eq(ns:ModuleDB("reputation").faction, "watched", "a header is not a choice")
	ns.UI.ClosePopup()
	R.Pick(21)
	eq(R.state.name, "Booty Bay", "a faction under a collapsed header")
	eq(R.state.reaction, 3)
	R.Pick("watched")
	eq(R.ChoiceText("watched"), "Watched faction (the game's own)")
	eq(R.ChoiceText(47), "Ironforge")
end)

step("Professions and reputation settings are in the window's search", function()
	local wasShown = ns.app:IsShown()
	if not wasShown then slash("") end
	local function finds(q, key)
		for _, m in ipairs(ns.app:Search(q)) do if m.entry.info and m.entry.info.key == key then return true end end
		return false
	end
	check(finds("faction", "reputation.faction"), "faction")
	check(finds("watched", "reputation.faction"), "watched")
	check(finds("reputation width", "reputation.width"), "reputation width")
	check(finds("cooking", "professions.cooking"), "cooking")
	check(finds("profession", "professions.showmax"), "profession")
	check(finds("trainer", "professions.markcap"), "trainer")
	ns.app:Search("")
	if not wasShown then slash("") end
end)

step("Migration: players with a layout get the new plugins placed once", function()
	local saved = ns.newModules
	ns.newModules = {}
	ns.Migrate({ version = 2, seenLayout = true })
	check(ns.newModules.professions and ns.newModules.reputation, "placed for an existing layout")
	ns.newModules = {}
	ns.Migrate({ version = 3, seenLayout = true })
	check(not ns.newModules.professions, "only once")
	ns.newModules = saved
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
	btn:CreateTexture():SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	local blank = CreateFrame("Button", "SomeAddonBlankButton", Minimap); blank:SetSize(31, 31) -- no icon: left alone
	local pin = CreateFrame("Button", "QuestieFrame12", Minimap); pin:SetSize(16, 16)
	local blizz = CreateFrame("Button", "MiniMapLFGFrame", Minimap); blizz:SetSize(32, 32)
	MOCK.Fire("ADDON_LOADED", "SomeAddon"); flush()
	mm:ApplyAll(); flush()
	eq(btn:GetParent(), mm.drawer, "addon button in the drawer")
	eq(blank:GetParent(), Minimap, "a button with nothing to show is left where it was")
	eq(mm.skipped.SomeAddonBlankButton, "no icon of its own", "and the scan can say why")
	MOCK.log = {}; slash("minimap scan")
	check(logHas("left on the minimap: SomeAddonBlankButton"), "scan lists it")
	eq(pin:GetParent(), Minimap, "map pin left alone")
	eq(blizz:GetParent(), Minimap, "Blizzard button left alone")
	slash("minimap ignore SomeAddonMinimapButton")
	eq(btn:GetParent(), Minimap, "released on ignore")
end)

step("minimap: Blizzard's mail event after we hid the mail icon (UPDATE_PENDING_MAIL regression)", function()
	local mm = ns.modules.minimap
	-- the mail piece is the indicator frame (mail and crafting orders); the mail icon inside stays Blizzard's
	local box = MinimapCluster.IndicatorFrame
	local mail = box.MailFrame
	eq(mm:Mode("mail"), "hide", "mail icon hidden by default")
	check(not mm:PieceOn("mail"), "off by default")
	MOCK.mail = true
	MOCK.Fire("UPDATE_PENDING_MAIL") -- runs Blizzard's handler: SetShown + GetParent():Layout()
	MOCK.Fire("CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS")
	check((box.__layouts or 0) >= 2, "Blizzard's Layout() ran on the real parent")
	check(not mail:IsVisible(), "still hidden after Blizzard showed it")
	MOCK.BlizzardShowsAgain()
	check(not MinimapZoneTextButton:IsShown() and not MinimapCluster.MinimapContainer.PlayerCoords:IsShown(), "Show() from Blizzard is undone")
	box:Show() -- Blizzard's own Show on the piece itself
	check(not box:IsShown() and not mail:IsVisible(), "mail too")
	-- on: there, on the minimap's edge; mail waiting, so the icon shows
	mm:SetPieceOn("mail", true)
	check(mail:IsVisible(), "mail icon back (there is mail)")
	local _, rel = box:GetPoint(1)
	eq(rel, Minimap, "anchored to the minimap, not to the corner strip")
	eq(mail:GetParent(), box, "the icon keeps its parent")
	eq(box:GetParent(), MinimapCluster, "the piece keeps its parent")
	mm:SetPieceOn("mail", false)
	check(not mail:IsVisible(), "hidden again")
	MOCK.mail = false
	MOCK.Fire("UPDATE_PENDING_MAIL")
	mm:SetPieceOn("mail", true)
	check(box:IsShown() and not mail:IsShown(), "no mail: the piece is on, Blizzard keeps its icon hidden")
	-- Blizzard lays its header out again: the piece goes back to our place
	box:ClearAllPoints(); box:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", 0, 0)
	_, rel = box:GetPoint(1)
	eq(rel, Minimap, "re-anchored to the minimap after Blizzard's layout")
	ns:ModuleDB("minimap").pieceOn.mail = nil
	mm:ApplyElements()
	check(not box:IsShown(), "back to its default: off")
	-- no piece of Blizzard's ever sits under a frame of ours
	for _, w in ipairs(MOCK.widgets) do
		local p = w.__parent
		if w.__name and not w.__name:find("^EverlookBar") and not w.__name:find("Minimap$") and p == mm.hider then
			error(w.__name .. " re-parented to our hidden frame")
		end
	end
end)

-- A LibDBIcon-1.0 like the real one (r57): buttons on the minimap with a border (OVERLAY), a background and the icon
-- (ARTWORK); strata MEDIUM and level 8 pinned with SetFixedFrameStrata/Level; showOnMouseover fades them to alpha 0.
local function fakeLibDBIcon()
	local lib = LibStub:NewLibrary("LibDBIcon-1.0", 57)
	lib.objects, lib.callbacks = {}, {}
	function lib.RegisterCallback(owner, event, fn) lib.callbacks[event] = fn end
	function lib:GetButtonList() local t = {}; for n in pairs(self.objects) do t[#t + 1] = n end; table.sort(t); return t end
	function lib:GetMinimapButton(n) return self.objects[n] end
	function lib:Make(name, db)
		local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
		b.db = db or {}
		b.dataObject = { icon = "Interface\\Icons\\" .. name }
		b:SetFrameStrata("MEDIUM"); b:SetFixedFrameStrata(true)
		b:SetFrameLevel(8); b:SetFixedFrameLevel(true)
		b:SetSize(31, 31)
		b.border = b:CreateTexture(nil, "OVERLAY"); b.border:SetTexture(136430)
		b.background = b:CreateTexture(nil, "BACKGROUND"); b.background:SetTexture(136467)
		b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(b.dataObject.icon)
		b:SetScript("OnDragStart", function() end); b:RegisterForDrag("LeftButton")
		b:SetScript("OnEnter", function(self) MOCK.tipFor = self end)
		b:SetScript("OnClick", function(self, button) MOCK.clicked = self:GetName() .. ":" .. button end)
		b.fadeOut = { Stop = function() b.__fading = false end, Play = function() b.__fading = true end }
		b:SetPoint("CENTER", Minimap, "CENTER", -80, -40)
		if b.db.hide then b:Hide() end
		self.objects[name] = b
		if self.callbacks.LibDBIcon_IconCreated then self.callbacks.LibDBIcon_IconCreated("LibDBIcon_IconCreated", b, name) end
		return b
	end
	-- BasicMinimap's "hide addon buttons until hovered": alpha 0, faded again when the mouse leaves the minimap
	function lib:ShowOnEnter(name, v) local b = self.objects[name]; b.showOnMouseover = v; b:SetAlpha(v and 0 or 1) end
	function lib:MinimapLeave() for _, b in pairs(self.objects) do if b.showOnMouseover then b:SetAlpha(0) end end end
	return lib
end

step("minimap: LibDBIcon buttons in the drawer keep their icon, tooltip and click", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	local lib = fakeLibDBIcon()
	local bug = lib:Make("BugSack")
	local q = lib:Make("Questie")
	local off = lib:Make("Hidden", { hide = true })
	lib:ShowOnEnter("Questie", true)
	mm:ApplyAll(); flush()
	local drawer, toggle = mm.drawer, mm.drawerToggle
	eq(bug:GetParent(), drawer, "BugSack in the drawer")
	eq(q:GetParent(), drawer, "Questie in the drawer")
	-- the old drawer sat in DIALOG while the buttons stayed pinned at MEDIUM: the drawer's dark panel covered them
	-- and only their grey rings showed through. Now they draw above the drawer.
	eq(bug:GetFrameStrata(), drawer:GetFrameStrata(), "same strata as the drawer")
	check(bug:GetFrameLevel() > drawer:GetFrameLevel(), "above the drawer's panel")
	eq(bug.icon:GetParent(), bug, "icon texture untouched")
	eq(bug.icon.__texture, "Interface\\Icons\\BugSack", "icon kept")
	eq(q:GetAlpha(), 1, "faded button visible in the drawer")
	check(not q.showOnMouseover, "no fading while in the drawer")
	lib:MinimapLeave()
	eq(q:GetAlpha(), 1, "stays visible when the mouse leaves the minimap")
	check(not bug.__drag, "dragging off in the drawer")
	-- grid: two visible buttons, the hidden one is not placed
	local _, _, _, x1 = bug:GetPoint(1)
	local _, _, _, x2 = q:GetPoint(1)
	check(x1 ~= x2, "in a grid")
	eq(toggle.count, 2, "two buttons shown")
	check(toggle:IsShown(), "drawer button shown")
	-- opening: next to the drawer button, never somewhere else
	toggle.__scripts.OnClick(toggle, "LeftButton")
	check(drawer:IsShown(), "opens")
	local p, rel, rp = drawer:GetPoint(1)
	eq(rel, toggle, "anchored to the drawer button")
	eq(p, "BOTTOMRIGHT", "minimap top-right, button bottom-left: opens to the left, growing up along the map")
	eq(rp, "BOTTOMLEFT")
	-- the buttons' own scripts still work
	bug.__scripts.OnClick(bug, "RightButton")
	eq(MOCK.clicked, "LibDBIcon10_BugSack:RightButton", "normal click")
	bug.__scripts.OnEnter(bug)
	eq(MOCK.tipFor, bug, "own tooltip")
	-- a button created later joins
	local late = lib:Make("TomTom"); flush()
	eq(late:GetParent(), drawer, "late button collected")
	-- release gives everything back
	db.buttons = "leave"; mm:ReleaseButtons()
	eq(bug:GetParent(), Minimap, "back on the minimap")
	eq(bug:GetFrameStrata(), "MEDIUM", "strata back")
	eq(bug:GetFrameLevel(), 8, "level back")
	check(bug:HasFixedFrameStrata(), "pinned again")
	check(q.showOnMouseover, "fading back")
	check(bug.__drag, "dragging back")
	local _, relb = bug:GetPoint(1)
	eq(relb, Minimap, "position back")
	db.buttons = "drawer"; mm:ApplyAll(); flush()
	eq(bug:GetParent(), drawer, "collected again")
	drawer:Hide()
end)

step("minimap: drawer opens beside its button, flips when there is no room", function()
	local mm = ns.modules.minimap
	local p, rp, dx = mm.DrawerAnchor("BOTTOMLEFT", 1700, 200, 1920)
	eq(p, "BOTTOMRIGHT"); eq(rp, "BOTTOMLEFT"); check(dx < 0)
	p, rp = mm.DrawerAnchor("TOPLEFT", 1700, 200, 1920)
	eq(p, "TOPRIGHT", "top corner: grows down")
	p, rp = mm.DrawerAnchor("BOTTOMLEFT", 100, 200, 1920)
	eq(p, "BOTTOMLEFT", "no room on the left: opens to the right"); eq(rp, "BOTTOMRIGHT")
	p = mm.DrawerAnchor("TOPRIGHT", 1850, 200, 1920)
	eq(p, "TOPRIGHT", "no room on the right: opens to the left")
	check(mm.drawer:IsClampedToScreen(), "clamped to the screen")
end)

step("minimap: coordinates under the minimap: Blizzard's hidden, other addons named with the setting", function()
	local mm = ns.modules.minimap
	local coords = MinimapCluster.MinimapContainer.PlayerCoords
	check(not coords:IsShown(), "Blizzard's coordinates hidden by default")
	-- another addon's coordinates text under the minimap: listed by the scan, with its owner
	MOCK.addons[#MOCK.addons + 1] = "SomeCoords"
	MOCK.loaded.SomeCoords = true
	local f = CreateFrame("Frame", "SomeCoordsFrame", UIParent)
	f:SetSize(80, 14); f.__left, f.__bottom = mm.holder.__left or 100, 380
	local fs = f:CreateFontString(); fs:SetText("49.5, 55.7")
	fs.__w, fs.__h = 80, 14; fs.__left, fs.__bottom = Minimap:GetLeft() + 30, Minimap:GetBottom() - 20
	local secretFrame = CreateFrame("Frame", "SecretTextFrame", UIParent)
	local sfs = secretFrame:CreateFontString(); sfs:SetText(S("hidden")); sfs.__left, sfs.__bottom = fs.__left, fs.__bottom
	local found = mm:ScanText()
	local hit
	for _, x in ipairs(found) do if x.name == "SomeCoordsFrame" then hit = x end end
	check(hit, "scan lists the other addon's text")
	eq(hit.owner, "SomeCoords", "and its addon")
	eq(hit.text, "49.5, 55.7")
	for _, x in ipairs(found) do check(x.name ~= "SecretTextFrame", "secret text skipped, not read") end
	MOCK.log = {}
	slash("minimap scan")
	check(logHas("SomeCoordsFrame (SomeCoords)"), "scan prints it")
	f:Hide()
	-- Questie's own minimap coordinates: told once, with the setting to switch off
	Questie = { db = { profile = { minimapCoordinatesEnabled = true } } }
	MOCK.log = {}
	mm:TellForeignCoords(); mm:TellForeignCoords()
	local n = 0
	for _, l in ipairs(MOCK.log) do if l:find("Show Minimap Coordinates", 1, true) then n = n + 1 end end
	eq(n, 1, "told once, naming the setting")
	Questie = nil
end)

step("minimap: zone line shows the subzone, follows zone changes", function()
	local mm = ns.modules.minimap
	eq(mm.ZoneLabelText("subzone", "Hillsbrad Foothills", "Tarren Mill"), "Tarren Mill")
	eq(mm.ZoneLabelText("subzone", "Hillsbrad Foothills", ""), "Hillsbrad Foothills", "no subzone: the zone")
	eq(mm.ZoneLabelText("zone", "Hillsbrad Foothills", "Tarren Mill"), "Hillsbrad Foothills")
	eq(mm.ZoneLabelText("both", "Hillsbrad Foothills", "Tarren Mill"), "Hillsbrad Foothills: Tarren Mill")
	eq(mm.ZoneLabelText("both", "Orgrimmar", "Orgrimmar"), "Orgrimmar", "no doubling")
	check(not mm.zoneLabel or not mm.zoneLabel:IsShown(), "off by default")
	slash("minimap.zonelabel subzone")
	check(mm.zoneLabel and mm.zoneLabel:IsShown(), "shown")
	eq(mm.zoneLabel:GetText(), "Tarren Mill", "the subzone")
	MOCK.zone = { "Hillsbrad Foothills", "Southshore", "contested" }
	MOCK.Fire("ZONE_CHANGED")
	eq(mm.zoneLabel:GetText(), "Southshore", "follows the player")
	slash("minimap.zonelabelpos bottom")
	local p, rel, rp = mm.zoneLabel:GetPoint(1)
	eq(p, "TOP"); eq(rel, Minimap); eq(rp, "BOTTOM")
	slash("minimap.zonelabel off")
	check(not mm.zoneLabel:IsShown(), "off again")
	MOCK.zone = { "Hillsbrad Foothills", "Tarren Mill", "contested" }
	ns:ModuleDB("minimap").zoneLabelPos = "top"
end)

step("minimap: round and square masks, border behind the map", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	eq(db.shape, "square", "square for a new player")
	eq(mm.defaults.shape, "square", "the default")
	eq(Minimap.__mask, "Interface\\Buttons\\WHITE8X8", "square mask")
	eq(GetMinimapShape(), "SQUARE")
	-- a player who already had a shape keeps it: defaults only fill what is missing
	local saved = ns.Util.FillDefaults({ shape = "round", scale = 1.2 }, mm.defaults)
	eq(saved.shape, "round", "a saved round minimap stays round")
	eq(ns.Util.FillDefaults({}, mm.defaults).shape, "square", "nothing saved: square")
	db.shape = "round"; mm:Redraw()
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

-- Drag a frame of ours the way the client does: StartMoving, the cursor moves it, StopMovingOrSizing.
local function drag(frame, dragged, left, bottom)
	frame.__scripts.OnDragStart(frame, "LeftButton")
	check(dragged.__moving, "StartMoving on the holder")
	dragged.__left, dragged.__bottom = left, bottom
	frame.__scripts.OnDragStop(frame)
	check(not dragged.__moving, "StopMovingOrSizing")
end

step("minimap: Unlock to move, left-drag the map itself, Done", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	check(not ns.Unlock.active, "edit mode is off")
	check(not mm.unlocked, "locked after login")
	check(not (mm.overlay and mm.overlay:IsShown()), "no mover while locked: clicks go to the map")
	-- the minimap page starts with the Unlock to move button (the old switch is the same thing from chat)
	ns.app:Open("minimap")
	local row = ns.Options.unlockRow
	check(row and row.buttons[1]:GetText() == "Unlock to move", "the button is on the minimap page")
	row.buttons[1].__scripts.OnClick(row.buttons[1], "LeftButton")
	check(ns.Unlock.active and mm.unlocked, "the button starts edit mode and unlocks the minimap")
	eq(row.buttons[1]:GetText(), "Done moving", "and says how to end it")
	row.buttons[1].__scripts.OnClick(row.buttons[1], "LeftButton")
	check(not ns.Unlock.active and not mm.unlocked, "the button ends it")
	ns.app:Close()
	slash("minimap.unlocked on")
	check(ns.Unlock.active and mm.unlocked, "unlocked from the old setting: the same edit mode")
	local ov = mm.overlay
	check(ov:IsShown() and ov:IsMouseEnabled(), "mover over the map, taking the mouse")
	eq(ov:GetFrameStrata(), "HIGH", "above the map and its buttons")
	check(not ov.handle and not ov.lock, "no tab above the map any more (it sat under a top bar)")
	-- drag: lands where dropped
	drag(ov, mm.holder, 700, 500)
	eq(db.point[1], 770, "x saved (centre)"); eq(db.point[2], 570, "y saved")
	-- snapping is off by default: dropped 5 px from the right edge stays there
	eq(db.snapEdges, false, "no sticky edges by default")
	local pad = mm:BorderPad()
	drag(ov, mm.holder, 1920 - 140 - 5, 300)
	eq(db.point[1], 1920 - 140 - 5 + 70, "stays where dropped")
	-- switched on: flush to the edge, border included (never cut off)
	db.snapEdges = true
	drag(ov, mm.holder, 1920 - 140 - 5, 300)
	eq(db.point[1], 1920 - 70 - pad, "snapped to the right edge, border on screen")
	db.snapEdges = false
	-- the control in the middle of the map drags the map too; half off screen -> back on screen
	drag(ns.Unlock.panel, mm.holder, -60, 300)
	eq(db.point[1], 70 + mm:BorderPad(), "kept on screen, border included")
	-- wheel: size in 5% steps, saved
	ov.__scripts.OnMouseWheel(ov, 1)
	eq(db.scale, 1.05, "wheel up"); eq(mm.holder:GetScale(), 1.05, "applied")
	ov.__scripts.OnMouseWheel(ov, -1); ov.__scripts.OnMouseWheel(ov, -1)
	eq(db.scale, 0.95, "wheel down")
	slash("minimap lock")
	check(not mm.unlocked and not ov:IsShown() and not ns.Unlock.active, "chat lock ends edit mode")
	slash("minimap unlock")
	check(mm.unlocked and ns.Unlock.active, "chat unlock: edit mode")
	slash("lock")
	check(not mm.unlocked, "locked")
	-- reset: asks first, the second time does it
	slash("minimap reset")
	eq(db.scale, 0.95, "asked first, nothing reset yet")
	slash("minimap reset")
	eq(db.scale, 1, "reset size")
	eq(db.point[1], 1920 - 70 - mm:BorderPad() - 16, "reset to the top-right corner")
	eq(db.point[2], 1080 - 70 - mm:BorderPad() - 34)
end)

step("minimap: no moving in combat, says why; combat locks it", function()
	local mm = ns.modules.minimap
	MOCK.log = {}
	MOCK.combat = true
	check(not ns.Unlock:Start(), "refused in combat")
	check(logHas("can't move things in combat"), "says why")
	check(not mm.unlocked and not ns.Unlock.active)
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	MOCK.log = {}
	ns.Unlock:Start()
	local ov = mm.overlay
	ov.__scripts.OnDragStart(ov, "LeftButton")
	check(mm.holder.__moving, "dragging")
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(not ns.Unlock.active, "edit mode ended")
	check(not mm.holder.__moving, "drag dropped when combat starts")
	check(not mm.unlocked and not ov:IsShown(), "locked for combat")
	check(not ns.Unlock.panel:IsShown(), "the control is gone")
	local n = 0
	for _, l in ipairs(MOCK.log) do if l:find("locked for combat", 1, true) then n = n + 1 end end
	eq(n, 1, "told once")
	-- a drag started in combat does nothing
	mm.unlocked = true; ov:Show(); MOCK.combat = true; MOCK.log = {}
	ov.__scripts.OnDragStart(ov, "LeftButton")
	check(not mm.holder.__moving, "no StartMoving in combat")
	check(logHas("can't be moved in combat"))
	MOCK.combat = false
	mm:SetUnlocked(false, true)
	MOCK.Fire("PLAYER_REGEN_ENABLED")
end)

step("edit mode: the minimap, its pieces and the control; Done, Escape and Reset positions", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	local U = ns.Unlock
	db.shape = "square"; mm:Redraw()
	mm:SetPieceOn("tracking", true); mm:SetPieceOn("mail", true)
	check(U:Start(), "started")
	check(U.active and mm.unlocked, "the minimap is unlocked with the rest")
	-- the control: in the middle of the minimap, above everything, with Done (the one gold button) and Reset positions
	local p = U.panel
	check(p:IsShown() and p.onMap, "the control is shown on the map")
	local point, rel, relPoint, x, y = p:GetPoint(1)
	eq(point, "CENTER"); eq(rel, Minimap, "anchored to the minimap, so it follows it"); eq(relPoint, "CENTER"); eq(x, 0); eq(y, 0)
	eq(p:GetFrameStrata(), "FULLSCREEN_DIALOG", "above the map, the pieces and the bars")
	eq(p.done:GetText(), "Done"); eq(p.reset:GetText(), "Reset positions")
	check(p.reset:IsShown(), "Reset positions is there")
	check(p.hint:GetText():find("Drag the pieces", 1, true) and p.hint:GetText():find("snaps to the edge", 1, true), "one line of help")
	-- a box over each piece that is on, none for one that is off
	check(U.movers.tracking and U.movers.tracking:IsShown(), "tracking has a box")
	check(U.movers.mail and U.movers.mail:IsShown(), "mail has a box")
	check(not (U.movers.zone and U.movers.zone:IsShown()), "the zone name is off: no box")
	local _, mrel = U.movers.tracking:GetPoint(1)
	eq(mrel, Minimap, "the box is anchored to the minimap")
	eq(U.movers.tracking.tag:GetText(), "Tracking", "with the piece's name")
	-- the guide shows the shape's edge
	eq(mm.overlay.guide.shape, "square", "square guide on a square map")
	eq(mm.overlay.guide.half, 70 + mm:BorderPad(), "at the edge, border included")
	db.shape = "round"; mm:Redraw()
	eq(mm.overlay.guide.shape, "round", "round guide after the shape changed")
	db.shape = "square"; mm:Redraw()
	-- dragging a piece: it sticks to the edge and snaps to the corner; Shift puts it anywhere
	local half = mm:Half()
	mm:DragPieceTo("tracking", -half - 10, half + 4)
	eq(db.piecePos.tracking.a, 135, "snapped to the top-left corner"); eq(db.piecePos.tracking.d, 0, "on the edge")
	local tx, ty = mm:PieceXY("tracking")
	eq(math.floor(tx + 0.5), -half); eq(math.floor(ty + 0.5), half)
	local _, _, _, ox, oy = MiniMapTracking:GetPoint(1)
	eq(math.floor(ox + 0.5), -half, "the piece itself went there"); eq(math.floor(oy + 0.5), half)
	mm:DragPieceTo("tracking", 0, half + 40, true)
	eq(db.piecePos.tracking.a, 90, "free: straight above"); eq(db.piecePos.tracking.d, 40, "40 px off the edge")
	check(mm:IsMoved("tracking"), "it counts as moved")
	-- the box's own drag reads the cursor
	local mv = U.movers.mail
	mv.__scripts.OnDragStart(mv, "LeftButton")
	check(mv.dragging and mv.__scripts.OnUpdate, "dragging")
	local cx, cy = Minimap:GetCenter()
	MOCK.cursorX, MOCK.cursorY = cx + half + 20, cy + 2
	mv.__scripts.OnUpdate(mv, 0.02)
	eq(db.piecePos.mail.a, 0, "snapped to the middle of the right side")
	mv.__scripts.OnDragStop(mv)
	check(not mv.dragging and not mv.__scripts.OnUpdate, "dropped")
	-- right-click a box: that piece back to its own place
	mv.__scripts.OnClick(mv, "RightButton")
	check(not mm:IsMoved("mail"), "right-click resets one piece")
	-- Reset positions: asks first, then every piece and the minimap go back
	db.scale = 1.3
	p.reset.__scripts.OnClick(p.reset, "LeftButton")
	check(mm:IsMoved("tracking"), "asked first")
	p.reset.__scripts.OnClick(p.reset, "LeftButton")
	check(not mm:IsMoved("tracking") and next(db.piecePos) == nil, "pieces back in their own places")
	eq(db.scale, 1, "minimap back at 100%")
	check(U.active, "still editing")
	-- Done
	p.done.__scripts.OnClick(p.done, "LeftButton")
	check(not U.active and not mm.unlocked and not p:IsShown(), "Done ends it")
	check(not U.movers.tracking:IsShown(), "boxes gone")
	-- Escape (the control closes on Escape, which ends edit mode)
	U:Start()
	p.__scripts.OnKeyDown(p, "ESCAPE")
	check(not U.active and not mm.unlocked, "Escape ends it")
	-- another addon manages the minimap: a small panel in the middle of the screen, Done only
	mm.stepAside = "SexyMap"
	U:Start()
	check(U.active and not mm.unlocked, "bars and plugins can still be moved")
	check(not p.onMap, "not on the map")
	point, rel = p:GetPoint(1)
	eq(point, "CENTER"); eq(rel, UIParent, "centred on screen, never at the top or bottom edge")
	check(not p.reset:IsShown(), "nothing of the minimap to reset")
	check(not U.movers.tracking:IsShown(), "no boxes")
	U:Stop()
	mm.stepAside = nil
	mm:SetPieceOn("tracking", false); mm:SetPieceOn("mail", false)
	db.pieceOn.tracking, db.pieceOn.mail = nil, nil
	db.shape = "round"; mm:Redraw()
end)

step("minimap pieces: where they sit, the same saved place on a round and a square map", function()
	local mm = ns.modules.minimap
	local function near(a, b, what) if math.abs(a - b) > 0.01 then error((what or "value") .. ": expected " .. b .. ", got " .. a, 2) end end
	-- round: on the circle
	local x, y = mm.PiecePoint(0, 0, "round", 100); near(x, 100); near(y, 0)
	x, y = mm.PiecePoint(45, 0, "round", 100); near(x, 70.7107); near(y, 70.7107)
	x, y = mm.PiecePoint(90, 16, "round", 100); near(x, 0); near(y, 116)
	-- square: on the outline; the same angle is the corner
	x, y = mm.PiecePoint(45, 0, "square", 100); near(x, 100); near(y, 100)
	x, y = mm.PiecePoint(90, 16, "square", 100); near(x, 0); near(y, 116, "the same distance above the top side")
	x, y = mm.PiecePoint(60, 0, "square", 100); near(y, 100, "on the top side"); near(x, 57.735)
	x, y = mm.PiecePoint(20, 10, "square", 100); near(x, 110, "10 px outside the right side")
	-- there and back
	for _, shape in ipairs({ "round", "square" }) do
		for _, pt in ipairs({ { 30, -80 }, { -120, 10 }, { 5, 150 }, { -60, -60 } }) do
			local a, d = mm.PieceFromXY(pt[1], pt[2], shape, 100)
			local bx, by = mm.PiecePoint(a, d, shape, 100)
			near(bx, pt[1], shape .. " x"); near(by, pt[2], shape .. " y")
		end
	end
	-- no saved place ever lands inside the map or floats off it when the shape changes
	for a = 0, 350, 10 do
		local rx, ry = mm.PiecePoint(a, 0, "round", 100)
		near(math.sqrt(rx * rx + ry * ry), 100, "round: on the ring")
		local sx, sy = mm.PiecePoint(a, 0, "square", 100)
		near(math.max(math.abs(sx), math.abs(sy)), 100, "square: on the outline")
	end
	-- snap points
	eq(mm.SnapAngle(41, "square"), 45, "a corner pulls from 10 degrees")
	eq(mm.SnapAngle(36, "square"), 45); eq(mm.SnapAngle(33, "square"), 33, "further away it slides along the side")
	eq(mm.SnapAngle(93, "square"), 90, "the middle of a side"); eq(mm.SnapAngle(97, "square"), 97)
	eq(mm.SnapAngle(358, "square"), 0); eq(mm.SnapAngle(-44, "square"), 315)
	eq(mm.SnapAngle(47, "round"), 45, "round: every 45 degrees"); eq(mm.SnapAngle(60, "round"), 60, "else anywhere on the ring")
	eq(mm.SnapAngle(178, "round"), 180)
end)

step("minimap pieces: defaults, every switch on and off, drawn above the map", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	-- defaults: everything off but the dungeon difficulty flag; each piece has its own place on the edge
	local seen = {}
	for _, e in ipairs(mm.ELEMENTS) do
		eq(mm:PieceOn(e.key), e.key == "difficulty", e.key .. " default")
		check(type(e.label) == "string" and type(e.desc) == "string" and e.short, e.key .. " has a name and a line of help")
		if not e.fixed then
			local a, d = mm:PiecePos(e.key)
			eq(a, e.a, e.key .. " default angle"); eq(d, e.d)
			local id = a .. "/" .. d
			check(not seen[id], e.key .. " shares its default place with " .. tostring(seen[id]))
			seen[id] = e.key
			check(not mm:IsMoved(e.key), e.key .. " not moved")
		end
	end
	-- what this (mock) client has
	for _, k in ipairs({ "zone", "tracking", "mail", "calendar", "daynight", "clock", "coords", "zoom", "compartment" }) do
		check(mm:Present(k), k .. " is in this client")
	end
	check(not mm:Present("worldmap") and not mm:Present("difficulty"), "no world map button or difficulty flag here")
	-- the calendar button is the calendar piece, not day/night
	eq(mm:Find(mm.ELEMENT.calendar)[1], GameTimeFrame, "GameTimeFrame is the calendar button")
	eq(mm:Find(mm.ELEMENT.daynight)[1], MinimapCluster.Diel, "the dial is day/night")
	-- every switch works at once, both ways, from the setting itself
	local level = Minimap:GetFrameLevel()
	for _, k in ipairs({ "zone", "tracking", "mail", "calendar", "daynight", "clock", "coords", "compartment" }) do
		local obj = mm:Find(mm.ELEMENT[k])[1]
		check(not obj:IsShown(), k .. " hidden while off")
		slash("minimap." .. k .. " on")
		check(obj:IsShown(), k .. " shown at once")
		local point, rel, relPoint, x, y = obj:GetPoint(1)
		eq(point, "CENTER", k); eq(rel, Minimap, k .. " anchored to the minimap"); eq(relPoint, "CENTER")
		local px, py = mm:PieceXY(k)
		eq(x, px, k .. " x"); eq(y, py, k .. " y")
		check(obj:GetFrameLevel() > level, k .. " drawn above the map")
		eq(obj:GetFrameStrata(), Minimap:GetFrameStrata(), k .. " in the map's strata")
		check(math.sqrt(x * x + y * y) >= 70, k .. " on the edge, not inside the map")
		slash("minimap." .. k .. " off")
		check(not obj:IsShown(), k .. " hidden at once")
		db.pieceOn[k] = nil
	end
	-- "show" and "hide" still work as words (old macros)
	slash("minimap.clock show"); check(TimeManagerClockButton:IsShown(), "show = on")
	slash("minimap.clock hide"); check(not TimeManagerClockButton:IsShown(), "hide = off")
	db.pieceOn.clock = nil
	-- a piece keeps the minimap's scale
	db.scale = 1.5; mm:Redraw()
	mm:SetPieceOn("tracking", true)
	eq(MiniMapTracking:GetScale(), 1.5, "scaled with the minimap (its parent is the corner strip)")
	db.scale = 1; mm:Redraw()
	eq(MiniMapTracking:GetScale(), 1, "and back")
	mm:SetPieceOn("tracking", false); db.pieceOn.tracking = nil
	-- zoom buttons: the game shows them only under the mouse; switched on they stay
	local zin, zout = Minimap.ZoomIn, Minimap.ZoomOut
	check(not zin:IsShown() and not zout:IsShown(), "hidden (the game hides them, and they are off)")
	zin:Show(); check(not zin:IsShown(), "off: the game's Show on mouse-over is undone")
	mm:SetPieceOn("zoom", true)
	check(zin:IsShown() and zout:IsShown(), "on: both shown at once")
	zin:Hide(); zout:SetShown(false)
	check(zin:IsShown() and zout:IsShown(), "and they stay when the mouse leaves the map")
	local _, _, _, ix, iy = zin:GetPoint(1)
	local _, _, _, ox, oy = zout:GetPoint(1)
	check(ix > ox and iy > oy, "plus up and right of minus")
	mm:SetPieceOn("zoom", false)
	check(not zin:IsShown() and not zout:IsShown(), "off again")
	db.pieceOn.zoom = nil
	-- the game's ring art is for a round map only
	db.shape = "round"; mm:Redraw()
	mm:SetPieceOn("ringart", true)
	check(mm:PieceShown("ringart"), "round: shown")
	db.shape = "square"; mm:Redraw()
	check(not mm:PieceShown("ringart"), "square: not shown, whatever the switch says")
	db.shape = "round"; db.pieceOn.ringart = nil; mm:Redraw()
end)

step("minimap pieces: a new shape, size or border moves them with the edge", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	local function at(obj) local _, _, _, x, y = obj:GetPoint(1); return math.floor(x + 0.5), math.floor(y + 0.5) end
	db.shape, db.border, db.borderSize, db.scale = "round", true, 2, 1
	mm:Redraw()
	mm:SetPieceOn("tracking", true) -- default: 135 degrees, on the edge
	mm:SetPieceOn("calendar", true)
	db.piecePos.calendar = { a = 60, d = 10 } -- a saved place
	mm:ApplyElements()
	local half = 72
	eq(mm:Half(), half, "half the map plus its border")
	local x, y = at(MiniMapTracking)
	eq(x, -51, "round: on the ring at 135 degrees"); eq(y, 51)
	local cx, cy = at(GameTimeFrame)
	eq(cx, 41, "round: 10 px outside the ring at 60 degrees"); eq(cy, 71)
	-- square: the same saved places, now on the square's outline (the shape setting re-places them)
	slash("minimap.shape square")
	x, y = at(MiniMapTracking)
	eq(x, -half, "square: the top-left corner"); eq(y, half)
	cx, cy = at(GameTimeFrame)
	eq(cy, half + 10, "square: 10 px above the top side"); eq(cx, 47)
	eq(db.piecePos.calendar.a, 60, "the saved place itself did not change"); eq(db.piecePos.calendar.d, 10)
	-- a thicker border pushes the edge out
	slash("minimap.bordersize 6")
	x, y = at(MiniMapTracking)
	eq(x, -76, "border 6: edge at 76"); eq(y, 76)
	slash("minimap.border off")
	x, y = at(MiniMapTracking)
	eq(x, -70, "no border: the map's own edge"); eq(y, 70)
	-- the mouse wheel in edit mode: a bigger map, the pieces keep to its edge and its scale
	ns.Unlock:Start()
	mm.overlay.__scripts.OnMouseWheel(mm.overlay, 1)
	eq(db.scale, 1.05)
	eq(MiniMapTracking:GetScale(), 1.05, "the piece is scaled with the map")
	x, y = at(MiniMapTracking)
	eq(x, -70, "still on the corner (in the map's own units)"); eq(y, 70)
	eq(mm.overlay.guide.half, 70, "the guide follows")
	ns.Unlock:Stop()
	-- back to round: on the ring again
	slash("minimap.shape round")
	x, y = at(MiniMapTracking)
	eq(x, -49, "round again: on the ring"); eq(y, 49)
	db.shape, db.border, db.borderSize, db.scale = "round", true, 2, 1
	db.piecePos.calendar = nil
	mm:SetPieceOn("tracking", false); mm:SetPieceOn("calendar", false)
	db.pieceOn.tracking, db.pieceOn.calendar = nil, nil
	mm:Redraw()
end)

step("minimap pieces: old show / hide / move settings are migrated, never dropped", function()
	local mm = ns.modules.minimap
	-- 0.2.2: elements[key] = mode, elementPos[key] = { x, y } from the minimap's centre
	local old = { shape = "round", scale = 1.2, border = true,
		elements = { zone = "show", mail = "move", tracking = "move", clock = "hide", daynight = "show", compartment = "hide", bogus = "show" },
		elementPos = { mail = { -80, 60 }, tracking = { 0, 0 } } }
	mm.MigratePieces(old, 70)
	eq(old.pieceOn.zone, true, "show -> on")
	eq(old.pieceOn.mail, true, "move -> on")
	eq(old.pieceOn.clock, false, "hide -> off")
	eq(old.pieceOn.compartment, false)
	eq(old.pieceOn.bogus, nil, "unknown keys ignored")
	eq(old.pieceOn.coords, nil, "never set: still the default")
	-- the moved piece is where it was
	local p = old.piecePos.mail
	check(p, "the dragged place is kept")
	local x, y = mm.PiecePoint(p.a, p.d, "round", 70)
	check(math.abs(x + 80) < 1 and math.abs(y - 60) < 1, "at the same spot: " .. x .. ", " .. y)
	eq(old.piecePos.tracking, nil, "\"move\" never dragged (it sat in the middle of the map): its default place")
	eq(old.pieceOn.tracking, true)
	eq(old.piecePos.zone, nil, "show: default place")
	-- GameTimeFrame (the calendar button) used to follow day/night
	eq(old.pieceOn.calendar, true, "calendar button follows the old day/night setting")
	eq(old.pieceOn.daynight, true)
	eq(old.elements, nil, "old tables gone once moved over"); eq(old.elementPos, nil)
	eq(old.shape, "round", "the saved shape stays"); eq(old.scale, 1.2)
	-- again: nothing changes (and a choice made since is not overwritten)
	old.pieceOn.zone = false
	mm.MigratePieces(old, 70)
	eq(old.pieceOn.zone, false)
	-- a square minimap: the same spot on the square
	local sq = { shape = "square", elements = { mail = "move", calendar = "show", daynight = "hide" }, elementPos = { mail = { 90, 20 } } }
	mm.MigratePieces(sq, 70)
	x, y = mm.PiecePoint(sq.piecePos.mail.a, sq.piecePos.mail.d, "square", 70)
	check(math.abs(x - 90) < 1 and math.abs(y - 20) < 1, "square: same spot")
	eq(sq.pieceOn.calendar, true, "an explicit calendar setting wins over day/night")
	-- a new player: empty tables, defaults apply
	local new = {}
	mm.MigratePieces(new, 70)
	check(next(new.pieceOn) == nil and next(new.piecePos) == nil, "nothing invented for a new player")
	-- the live settings went through it at load
	local db = ns:ModuleDB("minimap")
	check(type(db.pieceOn) == "table" and type(db.piecePos) == "table" and db.elements == nil, "live settings migrated")
end)

step("minimap pieces: combat. A switch works in combat; what the game locks waits and the page says so", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	local cal, track = GameTimeFrame, MiniMapTracking
	MOCK.combat = true
	-- an ordinary piece: at once, also in combat
	slash("minimap.calendar on")
	check(cal:IsShown(), "shown in combat")
	check(not mm:Waiting(), "nothing waiting")
	slash("minimap.calendar off")
	check(not cal:IsShown(), "hidden in combat")
	-- a piece the game protects in combat: never touched in it, applied when combat ends
	track.__protected = true
	slash("minimap.tracking on")
	check(not track:IsShown(), "not touched in combat")
	check(mm.waiting.tracking and mm:Waiting(), "it waits, and the page can say so")
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(track:IsShown(), "shown when combat ends")
	local _, rel = track:GetPoint(1)
	eq(rel, Minimap, "and placed")
	check(not mm:Waiting(), "nothing waiting any more")
	-- the other way round
	MOCK.combat = true
	slash("minimap.tracking off")
	check(track:IsShown() and mm.waiting.tracking, "still there in combat, waiting")
	-- the newest choice wins
	slash("minimap.tracking on"); slash("minimap.tracking off")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not track:IsShown(), "hidden when combat ends")
	-- the minimap frame itself (shape, size) always waits for combat to end
	MOCK.combat = true
	slash("minimap.shape square")
	check(mm:Waiting(), "a shape change waits")
	eq(GetMinimapShape(), "SQUARE", "the setting is saved")
	check(Minimap.__mask ~= mm.MASKS.square, "the map itself not touched yet")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	eq(Minimap.__mask, mm.MASKS.square, "applied after combat")
	check(not mm:Waiting())
	track.__protected = nil
	db.pieceOn.tracking, db.pieceOn.calendar = nil, nil
	db.shape = "round"; mm:Redraw()
end)

step("minimap page: a short list of pieces, each with a picture, Reset and a switch; the search finds them", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	local wasShown = ns.app:IsShown()
	if not wasShown then slash("") end
	ns.app:Open("minimap")
	local function rowOf(key)
		for _, m in ipairs(ns.app:Search(mm.ELEMENT[key].label)) do
			if m.entry.info and m.entry.info.key == "minimap." .. key then return m.entry.frame end
		end
	end
	local row = rowOf("mail")
	check(row and row.switch and row.reset and row.art, "the mail row: picture, Reset, switch")
	ns.app:Search("")
	check(not rowOf("worldmap"), "a piece this game version lacks has no row")
	ns.app:Search("")
	-- the search finds a piece by a plain word
	local found = false
	for _, m in ipairs(ns.app:Search("letter")) do if m.entry.info and m.entry.info.key == "minimap.mail" then found = true end end
	check(found, "\"letter\" finds the mail icon")
	found = false
	for _, m in ipairs(ns.app:Search("unlock")) do if m.entry.info and m.entry.info.key == "minimap.unlocked" then found = true end end
	check(found, "\"unlock\" finds the Unlock to move button")
	ns.app:Search("")
	-- the row's switch is the setting; Reset is only for a moved piece
	row.__scripts.OnClick(row, "LeftButton")
	check(mm:PieceOn("mail") and MinimapCluster.IndicatorFrame:IsShown(), "the row's switch shows the piece at once")
	check(row.reset:GetAlpha() < 1, "Reset greyed: not moved")
	mm:DragPieceTo("mail", 0, 200, true)
	row:Refresh()
	eq(row.reset:GetAlpha(), 1, "Reset lit once it is moved")
	check(row.desc:GetText():find("Moved", 1, true), "and the row says so")
	row.reset.__scripts.OnClick(row.reset, "LeftButton")
	check(not mm:IsMoved("mail"), "Reset puts it back")
	row.__scripts.OnClick(row, "LeftButton")
	check(not mm:PieceOn("mail") and not MinimapCluster.IndicatorFrame:IsShown(), "and off again")
	db.pieceOn.mail = nil
	-- another addon manages the minimap: said once on the page, the pieces greyed out
	mm.stepAside = "SexyMap"
	ns.app:Refresh()
	check(ns.app:GetSetting("minimap.mail").disabled(), "greyed out")
	check(ns.app:GetSetting("minimap.shape").disabled(), "the shape too")
	local src = assert(io.open(ROOT .. "/Options.lua")):read("*a")
	local page = src:sub((src:find('app:Section("minimap"', 1, true)))
	local _, n = page:gsub("is managing the minimap", "")
	eq(n, 1, "said in one place")
	mm.stepAside = nil
	ns.app:Refresh()
	check(not ns.app:GetSetting("minimap.mail").disabled(), "back")
	if not wasShown then slash("") end
end)

step("minimap: dropped, resized or given a piece, it stays clear of the bars (and its pieces with it)", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	db.shape, db.scale, db.border, db.borderSize = "square", 1, true, 2
	mm:Redraw()
	-- the room the bars take: one top bar, 22 high
	local inset = mm.BarInsets()
	eq(inset[1], 0, "left"); eq(inset[2], 0, "right"); eq(inset[3], 22, "the top bar"); eq(inset[4], 0, "bottom")
	-- pure: kept inside the screen less the insets
	local x, y = mm.SnapCenter(1900, 1075, 144, 144, 1920, 1080, 0, { 0, 0, 22, 0 })
	eq(x, 1920 - 72, "on screen"); eq(y, 1080 - 22 - 72, "under the top bar, not behind it")
	x, y = mm.SnapCenter(500, 500, 144, 144, 1920, 1080, 0, { 0, 0, 22, 0 })
	eq(x, 500, "left alone in the open"); eq(y, 500)
	x, y = mm.SnapCenter(1900, 1075, 144, 144, 1920, 1080, 0)
	eq(y, 1080 - 72, "no insets: the screen only, as before")
	-- dropped at the very top in edit mode: flush under the bar
	ns.Unlock:Start()
	drag(mm.overlay, mm.holder, 900, 1080 - 100)
	eq(db.point[2], 1080 - 22 - 72, "dropped at the top: under the bar")
	-- the zone name sits above the map: with it on, the map leaves room for it too
	MinimapZoneTextButton.__w, MinimapZoneTextButton.__h = 175, 12
	mm:SetPieceOn("zone", true)
	local _, _, top = mm:Overhang()
	check(top > 0, "the zone name sticks out above the map")
	drag(mm.overlay, mm.holder, 900, 1080 - 100)
	eq(db.point[2], 1080 - 22 - 72 - top, "room for the zone name under the bar")
	-- the size in the control follows the mouse wheel
	check(ns.Unlock.panel.size:GetText():find("100%", 1, true), "the control shows the size")
	mm.overlay.__scripts.OnMouseWheel(mm.overlay, 1)
	check(ns.Unlock.panel.size:GetText():find("105%", 1, true), "and follows the wheel")
	check(db.point[2] <= 1080 - 22 - 72 * 1.05 - top * 1.05 + 1, "a bigger map still clear of the bar")
	ns.Unlock:Stop()
	-- a piece switched on while the map is flush under the bar: the map makes room
	mm:SetPieceOn("zone", false); db.pieceOn.zone = nil
	db.scale = 1; db.point = { 900, 1080 - 22 - 72 }; mm:Redraw()
	check(not mm:KeepClear(), "clear as it is: nothing moves")
	slash("minimap.zone on")
	eq(db.point[2], 1080 - 22 - 72 - top, "moved down for the zone name")
	slash("minimap.zone off"); db.pieceOn.zone = nil
	-- a minimap saved under a bar is left where it is at login (only a drop, a resize or a new piece moves it)
	db.point = { 900, 1080 - 72 }; mm:ApplyFrame()
	eq(db.point[2], 1080 - 72, "a saved place is not changed by loading")
	db.shape = "round"; db.point = nil
	slash("minimap reset"); slash("minimap reset")
end)

step("edit mode: a box's name sits outside it, never on the control, another box, another name or off the screen", function()
	local spot = ns.Unlock.LabelSpot
	local screen = { 0, 0, 1920, 1058 } -- the room under a top bar
	local function apart(a, b) return a[1] >= b[3] or a[3] <= b[1] or a[2] >= b[4] or a[4] <= b[2] end
	-- a box on the map's right, room beside it: the name goes right, away from the map
	local side, shift, r = spot({ 1000, 500, 1020, 520 }, 50, 12, 100, 0, screen, {})
	eq(side, "right"); eq(r[1], 1024, "4 px from the box")
	-- on the left: left
	side = spot({ 800, 500, 820, 520 }, 50, 12, -100, 0, screen, {})
	eq(side, "left")
	-- above the map: above the box, centred
	side, shift, r = spot({ 900, 600, 920, 620 }, 50, 12, 0, 100, screen, {})
	eq(side, "top"); eq(shift, 0); eq(r[2], 623)
	-- at the screen's right edge there is no room to the right: above the box (it is in the map's upper half),
	-- slid left to stay on screen
	side, shift, r = spot({ 1890, 500, 1915, 520 }, 50, 12, 100, 30, screen, {})
	eq(side, "top", "next side round")
	check(r[3] <= 1920 - 2 and shift < 0, "slid left, on screen")
	-- in the lower half: below
	side = spot({ 1890, 500, 1915, 520 }, 50, 12, 100, -30, screen, {})
	eq(side, "bottom")
	-- under the top bar there is no room above: beside the box instead
	side, shift, r = spot({ 900, 1040, 920, 1056 }, 50, 12, 10, 100, screen, {})
	check(side == "right", "not over the bar: " .. side)
	check(r[4] <= 1058, "inside the room under the bar")
	-- the control in the middle of the map is in the way of a name on the map's side: never placed on it
	local control = { 860, 460, 1034, 540 }
	side, shift, r = spot({ 1030, 520, 1050, 545 }, 60, 12, 100, 20, { 0, 0, 1060, 1058 }, { control })
	check(apart(r, control), "clear of the control (" .. side .. ")")
	-- a name already placed is avoided by the next one
	local first = select(3, spot({ 1000, 500, 1020, 520 }, 50, 12, 100, 0, screen, {}))
	side, shift, r = spot({ 1000, 505, 1020, 525 }, 50, 12, 100, 5, screen, { first })
	check(apart(r, first), "two names never overlap")
	-- nothing free at all: over its own box, still on screen
	side, shift, r = spot({ 1890, 500, 1915, 520 }, 50, 12, 100, 0, { 0, 0, 1920, 1058 },
		{ { 1800, 521, 1920, 560 }, { 1800, 460, 1920, 499 }, { 1700, 480, 1889, 540 } })
	eq(side, "over")
	check(r[3] <= 1920 - 2, "on screen")
	-- live: every name of a full square minimap in the screen's corner is clear of the control and of the others
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	db.shape = "square"; mm:Redraw()
	local keys = { "zone", "tracking", "mail", "calendar", "daynight", "clock", "coords", "zoom", "compartment" }
	for _, k in ipairs(keys) do mm:SetPieceOn(k, true) end
	ns.Unlock:Start()
	local names = {}
	for _, k in ipairs(keys) do
		local m = ns.Unlock.movers[k]
		check(m and m:IsShown() and m.side, k .. " has a box and a name")
		if m.tagRect and m.side ~= "over" then names[#names + 1] = { k, m.tagRect } end
	end
	for i, a in ipairs(names) do
		for j = i + 1, #names do check(apart(a[2], names[j][2]), a[1] .. " and " .. names[j][1] .. " overlap") end
		check(a[2][1] >= 0 and a[2][3] <= 1920 and a[2][4] <= 1080 - 22, a[1] .. " off the screen or over the bar")
	end
	ns.Unlock:Stop()
	for _, k in ipairs(keys) do mm:SetPieceOn(k, false); db.pieceOn[k] = nil end
	db.shape = "round"; mm:Redraw()
end)

step("minimap: a protected piece shown by Blizzard in combat is hidden after combat, never touched in it", function()
	local mm = ns.modules.minimap
	local track = MiniMapTracking
	track.__protected = true
	check(not track:IsShown(), "tracking hidden by default")
	-- the client refuses Hide/SetPoint on a protected frame in combat (an error even inside pcall)
	local hide = rawget(track, "Hide")
	MOCK.combat = true
	track.__touchedInCombat = false
	local oldHide = track.Hide
	rawset(track, "Hide", function(self, ...)
		if MOCK.combat and self.__protected and not MOCK.blizzardCall then self.__touchedInCombat = true end
		return oldHide(self, ...)
	end)
	MOCK.blizzardCall = true
	track:Show() -- Blizzard shows it in combat
	MOCK.blizzardCall = false
	check(not track.__touchedInCombat, "not hidden by us in combat")
	check(track:IsShown(), "stays shown until combat ends")
	check(mm.waiting.tracking, "and it is marked as waiting")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not track:IsShown(), "hidden after combat")
	rawset(track, "Hide", hide)
	track.__protected = nil
end)

step("minimap: a smaller screen keeps the minimap on it", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	db.point = { 1850, 1000 }
	UIParent.__w, UIParent.__h = 1280, 720
	MOCK.Fire("DISPLAY_SIZE_CHANGED")
	local _, _, _, x, y = mm.holder:GetPoint(1)
	eq(x, 1280 - 70 - mm:BorderPad(), "pulled back on screen (x)")
	eq(y, 720 - 70 - mm:BorderPad(), "pulled back on screen (y)")
	eq(db.point[1], 1850, "the saved spot is kept for the bigger screen")
	UIParent.__w, UIParent.__h = 1920, 1080
	MOCK.Fire("DISPLAY_SIZE_CHANGED")
	_, _, _, x = mm.holder:GetPoint(1)
	eq(x, 1920 - 70 - mm:BorderPad(), "back where it was, border kept on screen")
	mm:ResetPosition()
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
	-- said in chat once ever (a /reload or the next login says nothing); /ebar status says it every time
	MOCK.log = {}
	mm:TellRivals(); mm:TellRivals()
	local n = 0
	for _, l in ipairs(MOCK.log) do if l:find("BasicMinimap is managing the minimap", 1, true) then n = n + 1 end end
	eq(n, 1, "stepping aside told once")
	check(ns.db.told["stepAside:BasicMinimap"], "remembered in the saved settings")
	MOCK.log = {}
	slash("status")
	check(logHas("Minimap: BasicMinimap manages it"), "/ebar status names it")
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

step("Build your own: the search finds the guide button; it shows the guide and the AI line to copy", function()
	slash("")
	for _, q in ipairs({ "plugin", "module", "develop", "API", "guide" }) do
		local r = ns.app:Search(q)
		local found
		for _, m in ipairs(r) do if m.entry.sectionId == "develop" then found = m.entry end end
		check(found, "search '" .. q .. "' finds the guide")
	end
	local b = ns.app:Search("guide")[1].entry.frame.buttons[1]
	ns.app:Search("")
	b:GetScript("OnClick")(b, "LeftButton")
	local w = ns.Guide.window
	check(w and w:IsShown(), "link window shown")
	check(w:IsMovable() and w:GetScript("OnDragStart"), "the window can be moved")
	eq(w.guide:GetText(), "https://everlookdb.com/ebar/plugins", "guide address")
	check(w.ai:GetText():find("https://everlookdb.com/ebar/plugins.md", 1, true), "AI line names the brief")
	w.guide:SetText("typed over")
	w.guide:GetScript("OnTextChanged")(w.guide, true) -- the client fires this on typing
	eq(w.guide:GetText(), "https://everlookdb.com/ebar/plugins", "typing can't change it")
	w:Hide()
	slash("")
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

step("chat: the shared command pattern (help, lock, resets ask first, status, suggestions)", function()
	eq(SLASH_EVERLOOKBAR1, "/ebar"); eq(SLASH_EVERLOOKBAR2, "/everlookbar", "long-name alias")
	MOCK.log = {}
	slash("help")
	for _, want in ipairs({ "/ebar unlock || lock", "/ebar reset bars || all || minimap", "/ebar get [setting]", "/ebar search <words>" }) do
		check(logHas(want), "help lists " .. want)
	end
	-- lock / unlock / move flip unlock mode
	slash("unlock"); check(ns.Unlock.active, "unlock")
	slash("lock"); check(not ns.Unlock.active, "lock")
	slash("move"); check(ns.Unlock.active, "move flips it on")
	slash("move"); check(not ns.Unlock.active, "move flips it off")
	-- reset bars asks first, then works on the second try
	slash("bar add left")
	eq(#ns.db.bars, 2, "two bars")
	MOCK.log = {}
	slash("reset bars")
	eq(#ns.db.bars, 2, "asked first")
	check(logHas("again within 10 s"), "says how to confirm")
	slash("reset bars")
	eq(#ns.db.bars, 1, "reset on the second try")
	eq(ns.db.bars[1].name, "Top bar")
	-- reset all asks first; the old "reset all confirm" still reloads at once
	MOCK.reloaded = nil
	slash("reset all")
	check(not MOCK.reloaded, "reset all asks first")
	local saved = _G[ns.SAVED]
	slash("reset all confirm")
	check(MOCK.reloaded, "reset all confirm reloads")
	_G[ns.SAVED] = saved
	MOCK.reloaded = nil
	-- minimap reset asks first
	local db = ns:ModuleDB("minimap")
	db.scale = 1.2
	slash("minimap reset")
	eq(db.scale, 1.2, "minimap reset asks first")
	slash("minimap reset")
	eq(db.scale, 1, "then resets")
	-- a typo suggests the nearest setting and keeps the value
	MOCK.log = {}
	slash("bar.edg left")
	check(logHas("Did you mean /ebar bar.edge left?"), "suggestion: " .. lastLog())
	-- status: bars, plugins, memory
	MOCK.log = {}
	slash("status")
	check(logHas("1 bar(s), ") and logHas(" plugin(s); "), "status line: " .. lastLog())
end)

step("AI help: the text lists every setting by page, the bars and plugins; the apply box takes bar2.edge", function()
	slash("bar add left")
	slash("place gold 2 left")
	ns.editBar = 1
	local t = ns.app:AiText()
	local out = os.getenv("EBAR_AI_SAMPLE")
	if out then local f = io.open(out, "wb"); f:write(t); f:close() end
	local function has(want) check(t:find(want, 1, true), "AI text lacks: " .. want) end
	has("EverlookDB Bar v")
	has("EverlookDB Bar puts info bars on the screen edges")
	has("Bars \194\187 Place:\n- bar.edge: Where. Choice: top = Top of the screen; bottom = Bottom of the screen;")
	has("Now: top (Top of the screen). Default: top (Top of the screen).")
	has("- bar.bg: Background colour and opacity. Colour: hex rrggbb, or r g b a as 0-1 numbers (a = opacity). Now: 0 0 0 0.6 (#000000). Default: 0 0 0 0.6 (#000000).")
	has("- xp.width: XP bar width. Number 40 to 600. Now: ")
	local clock = t:match("\n(%- clock%.enabled:[^\n]*)")
	check(clock and clock:find("On/off. Now: o", 1, true) and clock:find("Default: off.", 1, true), "clock line: " .. tostring(clock))
	has("- minimap.scale: Minimap size. Number 0.5 to 2.5, step 0.05.")
	has("MORE ABOUT EVERLOOKDB BAR")
	has("- bar 2: name \"Bar 2\", shown on, edge left (Left side (plugins stacked))")
	has("- Gold: bar 2, left group, row 1")
	has("/ebar place <plugin> <bar> [left / center / right] [row]")
	check(not t:find("|", 1, true), "a | in the AI text")
	-- the apply box: bar2.edge previews bar 2 and leaves bar 1 picked
	local rows = ns.app:PlanApply("# move bar 2\n/ebar bar2.edge right\nbar.fontsize 14\nplace gold 1 right\nbar7.edge top")
	eq(#rows, 4, "rows")
	eq(rows[1].old, "left", "bar 2's edge")
	eq(rows[1].value, "right", "new edge")
	check(rows[3].err and rows[3].err:find("is a command", 1, true), "place was accepted")
	check(rows[4].err and rows[4].err:find("there is no bar 7", 1, true), "bar 7: " .. tostring(rows[4].err))
	eq(ns.editBar, 1, "planning picked bar 2")
	local changed, skipped = ns.app:ApplyText("bar2.edge right\nbar.fontsize 14\nplace gold 1 right\nbar7.edge top")
	eq(changed, 2, "changed"); eq(skipped, 2, "skipped")
	eq(ns.db.bars[2].edge, "right", "bar 2 moved")
	eq(ns.db.bars[1].fontSize, 14, "bar 1 font")
	eq(ns.editBar, 1, "applying left bar 2 picked")
	-- one chat line with several changes
	slash("set bar2.edge bottom ; bar1.fontsize 12")
	eq(ns.db.bars[2].edge, "bottom", "multi-set bar 2"); eq(ns.db.bars[1].fontSize, 12, "multi-set bar 1")
	slash("bar delete 2")
	ns.editBar = 1
end)

------------------------------------------------------------------------
-- Plugins page: drag and drop
------------------------------------------------------------------------
step("drag maths: insertion slot, lanes, nearest group", function()
	local c = L.RowCentres(3, 28, 2)
	eq(c[1], 14, "first centre"); eq(c[3], 74, "third centre")
	eq(L.InsertSlot(c, 0), 1, "above everything")
	eq(L.InsertSlot(c, 20), 2, "under the first row's middle")
	eq(L.InsertSlot(c, 59), 3, "upper half of row 3")
	eq(L.InsertSlot(c, 500), 4, "under the last")
	eq(L.InsertSlot({}, 10), 1, "empty list")
	-- one lane: index is the slot, minus one when the dragged row was above the line
	local lane, index = L.ListDrop({ 1, 1, 1 }, 4, 1)
	eq(lane, 1); eq(index, 3, "first row dragged to the end")
	lane, index = L.ListDrop({ 1, 1, 1 }, 1, 3)
	eq(index, 1, "last row dragged to the top")
	lane, index = L.ListDrop({ 1, 1, 1 }, 2, 2)
	eq(index, 2, "dropped on itself stays")
	lane, index = L.ListDrop({ 1, 1 }, 2, nil)
	eq(index, 2, "from elsewhere, between the two")
	-- two lanes shown lane by lane: the line between them belongs to the lane above
	lane, index = L.ListDrop({ 1, 1, 2, 2 }, 3, nil)
	eq(lane, 1); eq(index, 3, "end of lane 1")
	lane, index = L.ListDrop({ 1, 1, 2, 2 }, 1, nil)
	eq(lane, 1); eq(index, 1, "top: the lane of the row below")
	lane, index = L.ListDrop({ 1, 1, 2, 2 }, 4, nil)
	eq(lane, 2); eq(index, 2, "inside lane 2")
	lane, index = L.ListDrop({ 1, 2 }, 2, 1)
	eq(lane, 2); eq(index, 1, "the only lane-1 row dropped under itself takes the lane of the row below")
	lane, index = L.ListDrop({}, 1, nil, 2)
	eq(lane, 2); eq(index, 1, "empty group: the fallback lane")
	local z = { { top = 0, bottom = 100 }, { top = 140, bottom = 200 } }
	eq(L.NearestZone(z, 50), 1, "inside the first"); eq(L.NearestZone(z, 115), 1, "gap: nearer the first")
	eq(L.NearestZone(z, 130), 2, "gap: nearer the second"); eq(L.NearestZone(z, 900), 2, "under everything")
end)

local D = ns.PluginDrag
local function zoneOf(bar, group)
	for _, z in ipairs(D.zones) do if z.bar == bar and z.group == group then return z end end
end
local function offZone()
	for _, z in ipairs(D.zones) do if not z.bar then return z end end
end
local function rowOf(zone, name)
	for _, r in ipairs(zone.list.rows) do if r.item == name and r:IsShown() then return r end end
end
local function shownItems(zone)
	local t = {}
	for _, r in ipairs(zone.list.rows) do if r:IsShown() and r.item ~= nil then t[#t + 1] = r.item end end
	return table.concat(t, ",")
end
local function dragTo(name, from, to, slot)
	D:Start(name, from, rowOf(from, name))
	check(D.drag, "drag started for " .. name)
	D:SetTarget(to, slot)
	return D:Drop()
end
local function order(bar, group) return table.concat(ns.Host:GroupList(bar, 1, group), ",") end

step("Plugins page: rows have a grip; reorder inside a group, saved and live", function()
	slash("")
	ns.app:ShowSection("plugins")
	for _, n in ipairs(ns.Host:GroupList(1, 1, "left")) do ns.Host:Place(n, 1, 1, "right") end
	ns.Host:Place("Other_Plugin", 1, 1, "left", 1)
	ns.Host:Place("EverlookBar_Gold", 1, 1, "left", 2)
	ns.Host:Place("EverlookBar_Location", 1, 1, "left", 3)
	local left = zoneOf(1, "left")
	check(left and zoneOf(1, "right") and zoneOf(1, "center"), "three groups on the page")
	eq(shownItems(left), "Other_Plugin,EverlookBar_Gold,EverlookBar_Location", "rows in bar order")
	local r = rowOf(left, "Other_Plugin")
	check(r.dragGrip and r.__drag, "grip shown, row registered for dragging")
	eq(dragTo("Other_Plugin", left, left, 4), "place")
	eq(order(1, "left"), "EverlookBar_Gold,EverlookBar_Location,Other_Plugin", "moved to the end")
	eq(shownItems(left), "EverlookBar_Gold,EverlookBar_Location,Other_Plugin", "page shows it at once")
	eq(EverlookBarDB.placement.Other_Plugin.order, 3, "saved")
	-- the bar itself: the button sits after the other two
	local function bx(n) return ns.Host.plugins[n].button.pos.x end
	check(bx("Other_Plugin") > bx("EverlookBar_Location") and bx("EverlookBar_Location") > bx("EverlookBar_Gold"), "bar updated live")
	dragTo("EverlookBar_Location", left, left, 1)
	eq(order(1, "left"), "EverlookBar_Location,EverlookBar_Gold,Other_Plugin", "moved to the top")
	eq(rowOf(left, "EverlookBar_Gold"):GetAlpha(), 1, "no row left dimmed")
end)

step("Plugins page: drag across groups, off the bar and back on", function()
	local left, right, off = zoneOf(1, "left"), zoneOf(1, "right"), offZone()
	check(off, "Not on a bar is a drop zone")
	local before = #ns.Host:GroupList(1, 1, "right")
	dragTo("EverlookBar_Gold", left, right, 1)
	local p = ns.db.placement.EverlookBar_Gold
	eq(p.group, "right", "now in the right group"); eq(p.bar, 1)
	eq(ns.Host:GroupList(1, 1, "right")[1], "EverlookBar_Gold", "at the top of it")
	eq(#ns.Host:GroupList(1, 1, "right"), before + 1, "one more on the right")
	eq(dragTo("EverlookBar_Gold", right, off), "remove")
	check(ns.db.placement.EverlookBar_Gold == nil, "off the bar")
	check(EverlookBarDB.placement.EverlookBar_Gold == nil, "saved off")
	check(not ns.Host.plugins.EverlookBar_Gold.button:IsShown(), "its button is gone from the bar")
	check(rowOf(off, "EverlookBar_Gold"), "listed under Not on a bar")
	eq(dragTo("EverlookBar_Gold", off, off), nil, "from Not on a bar to itself: nothing")
	eq(dragTo("EverlookBar_Gold", off, left, 2), "place")
	eq(order(1, "left"), "EverlookBar_Location,EverlookBar_Gold,Other_Plugin", "added between the two")
	check(ns.Host.plugins.EverlookBar_Gold.button:IsShown(), "back on the bar")
	check(not rowOf(off, "EverlookBar_Gold"), "no longer under Not on a bar")
	eq(dragTo("Other_Plugin", left, nil), nil, "dropped off the page: nothing")
	eq(order(1, "left"), "EverlookBar_Location,EverlookBar_Gold,Other_Plugin", "unchanged")
end)

step("Plugins page: cancel with Escape, right-click, or by closing the window", function()
	local left, right = zoneOf(1, "left"), zoneOf(1, "right")
	local was = order(1, "left")
	D:Start("Other_Plugin", left, rowOf(left, "Other_Plugin"))
	D:SetTarget(right, 1)
	check(ns.app.window.eluiEscape(ns.app.window), "Escape is taken by the drag")
	check(D.drag == nil, "cancelled")
	check(ns.app:IsShown(), "the window stays open")
	D:Drop() -- the mouse button comes up afterwards: nothing happens
	eq(order(1, "left"), was, "nothing moved")
	eq(rowOf(left, "Other_Plugin"):GetAlpha(), 1, "row back to full")
	-- right-click while dragging
	local down = { LeftButton = true }
	IsMouseButtonDown = function(b) return down[b] or false end
	D:Start("Other_Plugin", left, rowOf(left, "Other_Plugin"))
	D:SetTarget(right, 1)
	down.RightButton = true
	D:Update()
	check(D.drag == nil, "right-click cancels")
	IsMouseButtonDown = nil
	eq(order(1, "left"), was, "nothing moved")
	-- closing the window mid-drag
	D:Start("Other_Plugin", left, rowOf(left, "Other_Plugin"))
	slash("")
	check(D.drag == nil, "closing the window cancels")
	eq(order(1, "left"), was, "nothing moved")
	-- a list lent to search results can't be dragged from
	slash("")
	ns.app:ShowSection("plugins")
	left = zoneOf(1, "left")
	left.list.stackEntry.borrowed = true
	D:Start("Other_Plugin", left, rowOf(left, "Other_Plugin"))
	check(D.drag == nil, "no drag from a borrowed list")
	left.list.stackEntry.borrowed = nil
end)

step("Plugins page: the cursor picks the group and the line; the page scrolls at its edges", function()
	local scroll = D.zones[1].list:GetParent():GetParent()
	check(rawget(scroll, "ScrollBy"), "page scroll found")
	scroll.__left, scroll.__w, scroll.__bottom, scroll.__h = 0, 500, 0, 1000
	local scrolled = 0
	local realScrollBy = rawget(scroll, "ScrollBy")
	rawset(scroll, "ScrollBy", function(_, d) scrolled = scrolled + d; return true end)
	-- lay the zones out from the top: heading 20 px, then the rows
	local top = 1000
	for _, z in ipairs(D.zones) do
		local n = #z.items()
		local h = n == 0 and 24 or n * 30
		if z.title then z.title.__left, z.title.__w, z.title.__h, z.title.__bottom = 0, 500, 16, top - 16 end
		z.list.__left, z.list.__w, z.list.__h, z.list.__bottom = 0, 500, h, top - 20 - h
		top = top - 20 - h - 30
	end
	local left, center = zoneOf(1, "left"), zoneOf(1, "center")
	local lt = left.list:GetTop()
	local zone, slot = D:TargetAt(200, lt - 50) -- the lower half of the second row (30 to 58 px down)
	check(zone == left, "left group under the cursor"); eq(slot, 3, "line under the second row")
	zone, slot = D:TargetAt(200, center.list:GetTop() + 10) -- on the Centre heading
	check(zone == center, "heading counts as the group"); eq(slot, 1, "line at the top")
	check(D:TargetAt(900, 500) == nil, "off the page: nowhere")
	-- a real drag by the cursor: Gold to the top of Centre
	MOCK.cursorX, MOCK.cursorY = 200, lt - 40
	D:Start("EverlookBar_Gold", left, rowOf(left, "EverlookBar_Gold"))
	MOCK.cursorX, MOCK.cursorY = 200, center.list:GetTop() - 2
	D:Update()
	check(D.drag.zone == center and D.drag.slot == 1, "target follows the cursor")
	eq(scrolled, 0, "no scrolling in the middle")
	MOCK.cursorY = 1000 - 5
	D:Update()
	check(scrolled < 0, "scrolls up near the top")
	scrolled = 0
	MOCK.cursorY = 5
	D:Update()
	check(scrolled > 0, "scrolls down near the bottom")
	MOCK.cursorX, MOCK.cursorY = 200, center.list:GetTop() - 2
	D:Update()
	D:Drop()
	eq(ns.Host:GroupList(1, 1, "center")[1], "EverlookBar_Gold", "dropped at the top of Centre")
	rawset(scroll, "ScrollBy", realScrollBy)
	MOCK.cursorX, MOCK.cursorY = 0, 0
	ns.Host:Place("EverlookBar_Gold", 1, 1, "left", 2)
end)

step("Plugins page: more bars show under their names; drag between bars", function()
	ns.Options:AddBar("bottom")
	flush()
	ns.app:ShowSection("plugins")
	flush()
	check(zoneOf(2, "left") and zoneOf(2, "right"), "bar 2's groups on the page")
	local count = 0
	for _, z in ipairs(D.zones) do if z.bar then count = count + 1 end end
	eq(count, 6, "three groups per bar")
	dragTo("Other_Plugin", zoneOf(1, "left"), zoneOf(2, "center"), 1)
	local p = ns.db.placement.Other_Plugin
	eq(p.bar, 2, "on bar 2"); eq(p.group, "center")
	check(ns.Host.plugins.Other_Plugin.button:GetParent() == ns.Bars.frames[2], "button moved to bar 2's frame")
	-- two rows on bar 2: a drop under a row-2 plugin lands in row 2
	ns.db.bars[2].lanes = 2
	ns.Host:Place("EverlookBar_Gold", 2, 2, "center", 1)
	local c2 = zoneOf(2, "center")
	eq(shownItems(c2), "Other_Plugin,EverlookBar_Gold", "row 1 then row 2")
	dragTo("EverlookBar_Location", zoneOf(1, "left"), c2, 3)
	eq(ns.db.placement.EverlookBar_Location.lane, 2, "joined row 2"); eq(ns.db.placement.EverlookBar_Location.order, 2)
	ns.Options:DeleteBar(2)
	flush()
	ns.app:ShowSection("plugins")
	flush()
	check(zoneOf(2, "left") == nil, "page rebuilt for one bar")
	ns.Host:Place("Other_Plugin", 1, 1, "right")
	ns.Host:Place("EverlookBar_Gold", 1, 1, "right")
	ns.Host:Place("EverlookBar_Location", 1, 1, "left", 1)
	slash("")
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
-- Audit round 2026-11-21
------------------------------------------------------------------------
step("every setting is in the window, so the search finds it by its own label", function()
	local wasShown = ns.app:IsShown()
	if not wasShown then slash("") end
	local missing = {}
	for _, def in ipairs(ns.app.settingOrder) do
		local label = type(def.label) == "function" and def.label() or def.label
		local found = false
		if type(label) == "string" then
			for _, m in ipairs(ns.app:Search(label)) do if m.entry.info and m.entry.info.key == def.key then found = true end end
		end
		-- a piece around the minimap that this game version does not have has no row
		local piece = def.key:match("^minimap%.(.+)$")
		if piece and ns.modules.minimap.ELEMENT[piece] and not ns.modules.minimap:Present(piece) then found = true end
		if not found then missing[#missing + 1] = def.key .. " [" .. tostring(label) .. "]" end
	end
	ns.app:Search("")
	if not wasShown then slash("") end
	check(#missing == 0, "not found: " .. table.concat(missing, ", "))
end)

step("bag cooldowns: a secret global cooldown or cooldown is left alone, never compared", function()
	local hook = ns.BagGCDHook
	local cleared = 0
	local bagButton = CreateFrame("Button"); bagButton.GetBagID = function() return 0 end
	local cd = CreateFrame("Cooldown", nil, bagButton); cd.Clear = function() cleared = cleared + 1 end
	local saved = C_Spell
	C_Spell = { GetSpellCooldown = function() return { startTime = S(100), duration = S(1.5) } end }
	hook(cd, 100, 1.5)
	eq(cleared, 0, "a secret global cooldown: the item's cooldown stays")
	C_Spell = { GetSpellCooldown = function() return { startTime = 100, duration = 1.5 } end }
	hook(cd, S(100), S(1.5))
	eq(cleared, 0, "a secret item cooldown stays")
	hook(cd, 100, 1.5)
	eq(cleared, 1, "the plain global cooldown is cleared")
	hook(cd, 50, 1.5)
	eq(cleared, 1, "a real 1.5 s item cooldown that is not the GCD stays")
	C_Spell = saved
end)

step("gold: this session starts in the world, not at a 0 read before login", function()
	local G = ns.modules.gold
	local savedMoney, savedLogged = MOCK.money, MOCK.loggedIn
	G.ResetSession()
	MOCK.loggedIn = false; MOCK.money = 0
	G:Update()
	MOCK.loggedIn = true; MOCK.money = 5000000
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	MOCK.tip = {}
	G.Tooltip(GameTooltip)
	check(table.concat(MOCK.tip, " "):find("no change", 1, true), "no gain from the 0 before login: " .. table.concat(MOCK.tip, " "))
	MOCK.money, MOCK.loggedIn = savedMoney, savedLogged
	MOCK.Fire("PLAYER_MONEY")
end)

step("XP: hidden on the level-up to max even while the game still reports the old level", function()
	local xpb = ns.Host.plugins.EverlookBar_XP
	MOCK.xp.level = 59
	MOCK.Fire("PLAYER_XP_UPDATE"); flush()
	check(xpb.button:IsShown(), "shown at 59")
	MOCK.Fire("PLAYER_LEVEL_UP", 60); flush()
	check(not xpb.button:IsShown(), "hidden at once on reaching 60")
	MOCK.xp.level = 20
	MOCK.Fire("PLAYER_XP_UPDATE"); flush()
	check(xpb.button:IsShown(), "back for the rest of the tests")
end)

step("secure clicks: bags, calendar and clock; every secure plugin is covered when combat starts", function()
	local SC = ns.SecureClick
	MainMenuBarBackpackButton = CreateFrame("Button", "MainMenuBarBackpackButton")
	CharacterMicroButton = CreateFrame("Button", "CharacterMicroButton")
	GameTimeFrame = CreateFrame("Button", "GameTimeFrame")
	local function at(name, x)
		local b = ns.Host.plugins[name].button
		b.__left, b.__bottom, b.__w, b.__h = x, 1050, 50, 22
		return b
	end
	local bags, dur, cal = at("EverlookBar_Bags", 500), at("EverlookBar_Durability", 300), at("EverlookBar_Calendar", 700)
	bags:GetScript("OnEnter")(bags)
	local c = SC:Frame()
	eq(c:GetAttribute("clickbutton1"), MainMenuBarBackpackButton, "bags open through the game's backpack button")
	c.__scripts.OnLeave(c)
	check(not c:IsShown(), "cover gone after the mouse left")
	cal:GetScript("OnEnter")(cal)
	c = SC:Frame()
	eq(c:GetAttribute("clickbutton1"), GameTimeFrame, "calendar opens through the game's calendar button")
	-- the game's button changed nothing: the calendar opens from here after all
	local opened = 0
	local savedOpen = ns.OpenCalendar
	ns.OpenCalendar = function() opened = opened + 1 end
	c.__scripts.PreClick(c, "LeftButton"); c.__scripts.PostClick(c, "LeftButton"); flush()
	eq(opened, 1, "fallback when the calendar did not open")
	ns.OpenCalendar = savedOpen
	check(c:IsShown() and SC:Covers()[cal] == c, "still covered (attributes refreshed after the click)")
	c.__scripts.OnLeave(c)
	-- combat starts: covers go over every secure plugin on screen (the mouse may come from anywhere in the fight)
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	MOCK.combat = true
	check(SC:Covers()[bags] and SC:Covers()[dur] and SC:Covers()[cal], "covered at combat start")
	local bc = SC:Covers()[bags]
	bc.__scripts.OnLeave(bc)
	check(bc:IsShown(), "a cover stays in combat (it can't be hidden then)")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not SC:Covers()[bags] and not SC:Covers()[dur] and not SC:Covers()[cal], "covers go after combat")
	-- a plugin moved while covered: the cover follows when the bar is laid out
	bags:GetScript("OnEnter")(bags)
	bags.__left = 520
	ns.Bars:LayoutAll()
	eq(SC:Covers()[bags].__points[1][4], 520, "cover follows its button")
	bags:GetScript("OnLeave")(bags); SC:Uncover(bags)
	MainMenuBarBackpackButton, CharacterMicroButton, GameTimeFrame = nil, nil, nil
	for _, f in ipairs({ "Bags", "Calendar", "Clock" }) do
		local src = assert(io.open(ROOT .. "/Modules/" .. f .. ".lua")):read("*a")
		check(src:find("ebarSecure", 1, true), f .. " has a secure click")
	end
end)

step("a third-party plugin's text with line breaks stays on one line", function()
	local obj = LibStub("LibDataBroker-1.1"):NewDataObject("Multi_Line", { type = "data source", text = "a\nb\r\nc" })
	ns.Host:Place("Multi_Line", 1, 1, "left"); flush()
	eq(ns.Host.plugins.Multi_Line.button.text:GetText(), "a b c", "one line")
	ns.Host:Remove("Multi_Line"); flush()
	check(obj, "made")
end)

step("professions: a skill line with no cap shows its rank alone", function()
	local P = ns.modules.professions
	eq(P.RankText({ rank = 150, max = 0 }), "150")
	eq(P.RankText({ rank = 150, max = 225 }), "150/225")
end)

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------
local TR = ns.modules.tracking
local function trackDB() return ns:ModuleDB("tracking") end
local function trackObj() return LibStub("LibDataBroker-1.1"):GetDataObjectByName("EverlookBar_Tracking") end

step("tracking: on by default, placed for a new profile, uses C_Minimap", function()
	check(TR.running, "tracking module running")
	eq(TR.Api(), "C_Minimap", "api")
	check(ns.db.placement.EverlookBar_Tracking ~= nil, "placed on a new profile")
	eq(ns.db.placement.EverlookBar_Tracking.group, "right", "group")
end)

step("tracking: menu groups follow the game (find and track, townsfolk, other)", function()
	MOCK.ResetTracking()
	TR:Update()
	local m = TR.MenuModel(false)
	local titles, order = {}, {}
	for _, r in ipairs(m) do
		if r.title then titles[#titles + 1] = r.text elseif r.index then order[#order + 1] = r.name end
		check(not r.disabled, "nothing disabled out of combat")
	end
	eq(table.concat(titles, "|"), "Find and track|Townsfolk|Other", "groups")
	eq(table.concat(order, "|"), "Find Herbs|Find Minerals|Auctioneer|Mailbox|Repair|Points of Interest", "rows in the game's order")
	eq(m[3].checked, true, "Find Minerals checked")
	eq(m[2].checked, false, "Find Herbs unchecked")
	eq(m[3].icon, 136025, "icon from the game")
	-- a group with nothing in it has no heading
	table.remove(MOCK.tracking, 6)
	TR:Update()
	titles = {}
	for _, r in ipairs(TR.MenuModel(false)) do if r.title then titles[#titles + 1] = r.text end end
	eq(table.concat(titles, "|"), "Find and track|Townsfolk", "empty group left out")
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: text shows what's tracked; first only; icon only", function()
	MOCK.ResetTracking()
	local db = trackDB()
	db.show = "all"
	TR:Update()
	local obj = trackObj()
	eq(obj.text, "Minerals, Mailbox", "all")
	eq(obj.icon, 136025, "icon of the first active one")
	MOCK.tracking[5].active = true
	TR:Update()
	eq(obj.text, "Minerals, Mailbox |cff8d94a3+1|r", "more than two")
	db.show = "first"
	TR:Update()
	eq(obj.text, "Minerals |cff8d94a3+2|r", "first only")
	db.show = "icon"
	TR:Update()
	eq(obj.text, "", "icon only")
	for _, t in ipairs(MOCK.tracking) do t.active = false end
	db.show = "all"
	TR:Update()
	eq(obj.text, "|cff8d94a3Not tracking|r", "nothing tracked")
	check(tostring(obj.icon):find("None"), "the game's 'none' icon")
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: a click toggles exactly the type clicked", function()
	MOCK.ResetTracking()
	TR:Update()
	check(TR.Toggle(4, "Mailbox"), "mailbox off")
	eq(MOCK.trackingSet[1], "4=false", "SetTracking(4, false)")
	check(TR.Toggle(1, "Find Herbs"), "herbs on")
	eq(MOCK.trackingSet[2], "1=true", "SetTracking(1, true)")
	eq(#MOCK.trackingSet, 2, "nothing else set or cast")
	eq(TR.active[1].name, "Find Herbs", "active list refreshed")
	-- the list changed under the menu: nothing is set
	local ok, why = TR.Toggle(1, "Find Minerals")
	check(not ok and why == "changed", "stale row refused")
	eq(#MOCK.trackingSet, 2, "nothing set for a stale row")
	-- the event refreshes the plugin
	MOCK.tracking[3].active = true
	MOCK.Fire("MINIMAP_UPDATE_TRACKING")
	flush()
	local names = {}
	for _, r in ipairs(TR.active) do names[#names + 1] = r.short end
	eq(table.concat(names, ","), "Herbs,Auctioneer", "after MINIMAP_UPDATE_TRACKING")
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: in combat the menu is read-only and nothing is set", function()
	MOCK.ResetTracking()
	TR:Update()
	MOCK.combat = true
	local m = TR.MenuModel(true)
	for _, r in ipairs(m) do if r.index then check(r.disabled, r.name .. " disabled in combat") end end
	check(m[#m].note and m[#m].text:find("after combat"), "after-combat note")
	local ok, why = TR.Toggle(1, "Find Herbs")
	check(not ok and why == "combat", "toggle refused in combat")
	ok, why = TR.ClearAll()
	check(not ok and why == "combat", "untrack all refused in combat")
	eq(#MOCK.trackingSet, 0, "nothing set in combat")
	-- the open menu redraws read-only, and a click on a row does nothing
	local button = ns.Host.plugins.EverlookBar_Tracking.button
	TR.OpenMenu(button)
	check(TR.menu:IsShown(), "menu opens in combat")
	local row = TR.menu.rows[2]
	check(row.item and row.item.disabled, "row disabled")
	row:GetScript("OnClick")(row, "LeftButton")
	eq(#MOCK.trackingSet, 0, "a click in combat sets nothing")
	MOCK.combat = false
	TR.DrawMenu()
	check(not TR.menu.rows[2].item.disabled, "enabled again after combat")
	TR.menu.rows[2]:GetScript("OnClick")(TR.menu.rows[2], "LeftButton")
	eq(MOCK.trackingSet[1], "1=true", "click after combat sets it")
	TR.OpenMenu(button) -- a second click on the plugin closes it
	check(not TR.menu:IsShown(), "second click closes the menu")
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: right-click offers untrack all only when the game has it", function()
	MOCK.ResetTracking()
	TR:Update()
	TR.RightMenu(nil)
	local has = false
	for _, it in ipairs(TR.rightItems) do if it.value == "clear" then has = true end end
	check(has, "untrack all offered")
	TR.RightPick("clear")
	eq(MOCK.trackingSet[1], "clear", "ClearAllTracking called")
	eq(#TR.active, 0, "nothing active")
	MOCK.ResetTracking()
	local clear = C_Minimap.ClearAllTracking
	C_Minimap.ClearAllTracking = nil
	TR:Update()
	TR.RightMenu(nil)
	for _, it in ipairs(TR.rightItems) do check(it.value ~= "clear", "no untrack all without the API") end
	C_Minimap.ClearAllTracking = clear
	ns.UI.ClosePopup()
end)

step("tracking: the older global API, and no API at all", function()
	local C = C_Minimap
	C_Minimap = nil
	local set = {}
	GetNumTrackingTypes = function() return 2 end
	GetTrackingInfo = function(i)
		if i == 1 then return "Find Treasure", 135725, true, "spell", -1 end
		return "Flight Master", 136456, false, "other", 2
	end
	SetTracking = function(i, on) set[#set + 1] = i .. "=" .. tostring(on) end
	eq(TR.Api(), "global", "global api")
	TR:Update()
	eq(#TR.list, 2, "two types")
	eq(TR.list[2].group, "town", "subType 2 is townsfolk")
	eq(TR.Text("all"), "Treasure", "short name")
	check(TR.Toggle(2, "Flight Master"), "toggle through the global API")
	eq(set[1], "2=true", "global SetTracking")
	GetNumTrackingTypes, GetTrackingInfo, SetTracking = nil, nil, nil
	eq(TR.Api(), nil, "no api")
	check(not TR:Available(), "not available without an API")
	TR:Update()
	eq(#TR.list, 0, "empty list")
	local m = TR.MenuModel(false)
	check(m[1].note and m[1].text:find("no tracking API"), "menu says so")
	local ok, why = TR.Toggle(1)
	check(not ok and why == "api", "toggle without API")
	C_Minimap = C
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: secret values are never read", function()
	MOCK.tracking[1] = { name = S("Find Herbs"), texture = S(1), active = S(true), type = "spell", subType = 1 }
	MOCK.tracking[2] = S({})
	TR:Update()
	for _, r in ipairs(TR.list) do check(r.name ~= "Find Herbs" and r.name ~= "Find Minerals", "secret rows skipped") end
	MOCK.ResetTracking()
	TR:Update()
end)

step("tracking: the setting works from chat; the minimap setting points to the plugin", function()
	local def = ns.app:GetSetting("tracking.show")
	check(def and def.type == "choice", "tracking.show setting")
	slash("tracking.show first")
	eq(trackDB().show, "first", "set from chat")
	eq(trackObj().text, "Minerals |cff8d94a3+1|r", "text follows the setting")
	slash("tracking.show all")
	local mmDef = ns.app:GetSetting("minimap.tracking")
	check(mmDef.desc and mmDef.desc:find("Tracking plugin"), "minimap tracking setting mentions the plugin")
	local found = false
	for _, w in ipairs(def.keywords or {}) do if w == "mailbox" then found = true end end
	check(found, "keywords include mailbox")
end)

step("tracking: an existing profile is told once, not placed", function()
	local saved = ns.db.placement.EverlookBar_Tracking
	ns.db.placement.EverlookBar_Tracking = nil
	ns.db.told.trackingPlugin = nil
	local before = #MOCK.log
	TR.TellExisting()
	TR.TellExisting()
	local n = 0
	for i = before + 1, #MOCK.log do if MOCK.log[i]:find("Tracking plugin", 1, true) then n = n + 1 end end
	eq(n, 1, "said once")
	check(ns.db.placement.EverlookBar_Tracking == nil, "not put on a bar")
	ns.db.placement.EverlookBar_Tracking = saved
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
