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
	EverlookBarDB = { version = 1, modules = { calendar = { style = "next" } } }
	MOCK.Fire("ADDON_LOADED", ADDON)
	eq(EverlookBarDB.modules.calendar.style, "full", "old calendar default migrated")
	eq(EverlookBarDB.version, 3, "settings version")
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
	check(tip:find("Right-click", 1, true), "click hint")
end)

step("Professions: a click opens that profession; no window, nothing; right-click lists them", function()
	local P = ns.modules.professions
	local b = ns.Host.plugins.EverlookBar_Professions.button
	MOCK.opened = {}
	local mining, herb, cook = P.pieces[2], P.pieces[1], P.pieces[3]
	mining:GetScript("OnClick")(mining, "LeftButton")
	eq(MOCK.opened[1], 186, "Mining piece opens Mining")
	cook:GetScript("OnClick")(cook, "LeftButton")
	eq(MOCK.opened[2], 185, "Cooking piece opens Cooking")
	herb:GetScript("OnClick")(herb, "LeftButton")
	eq(#MOCK.opened, 2, "Herbalism has no window: nothing opened")
	b:GetScript("OnClick")(b, "LeftButton")
	eq(MOCK.opened[3], 186, "the button itself opens the first with a window")
	-- the open one again: closed
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	MOCK.openProfession = 186
	mining:GetScript("OnClick")(mining, "LeftButton")
	eq(MOCK.opened[4], "close", "clicking the open profession closes it")
	ProfessionsFrame:Hide(); MOCK.openProfession = nil
	-- hover: the tooltip names the profession under the mouse
	mining:GetScript("OnEnter")(mining)
	check(table.concat(MOCK.tip, " "):find("Click: open Mining", 1, true), "hover hint")
	mining:GetScript("OnLeave")(mining)
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

-- Drag a frame of ours the way the client does: StartMoving, the cursor moves it, StopMovingOrSizing.
local function drag(frame, dragged, left, bottom)
	frame.__scripts.OnDragStart(frame, "LeftButton")
	check(dragged.__moving, "StartMoving on the holder")
	dragged.__left, dragged.__bottom = left, bottom
	frame.__scripts.OnDragStop(frame)
	check(not dragged.__moving, "StopMovingOrSizing")
end

step("minimap: unlock, left-drag the map itself, lock (general unlock mode off)", function()
	local mm = ns.modules.minimap
	local db = ns:ModuleDB("minimap")
	check(not ns.Unlock.active, "general unlock mode is off")
	check(not mm.unlocked, "locked after login")
	check(not (mm.overlay and mm.overlay:IsShown()), "no mover while locked: clicks go to the map")
	-- the first control on the minimap page is the unlock toggle
	local src = assert(io.open(ROOT .. "/Options.lua")):read("*a")
	local page = src:sub((src:find('app:Section("minimap"', 1, true)))
	eq(page:match('app:Widget%(stack, "([^"]+)"'), "minimap.unlocked", "first control on the minimap page")
	slash("minimap.unlocked on")
	check(mm.unlocked, "unlocked from the setting")
	local ov = mm.overlay
	check(ov:IsShown() and ov:IsMouseEnabled(), "mover over the map, taking the mouse")
	eq(ov:GetFrameStrata(), "HIGH", "above the map and its buttons")
	check(ov.handle and ov.lock, "handle with a lock button")
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
	-- dragged half off screen -> back on screen
	drag(ov.handle, mm.holder, -60, 300)
	eq(db.point[1], 70 + mm:BorderPad(), "kept on screen, border included")
	-- wheel: size in 5% steps, saved
	ov.__scripts.OnMouseWheel(ov, 1)
	eq(db.scale, 1.05, "wheel up"); eq(mm.holder:GetScale(), 1.05, "applied")
	ov.__scripts.OnMouseWheel(ov, -1); ov.__scripts.OnMouseWheel(ov, -1)
	eq(db.scale, 0.95, "wheel down")
	-- right-click locks
	ov.__scripts.OnClick(ov, "RightButton")
	check(not mm.unlocked and not ov:IsShown(), "right-click locked it")
	slash("minimap unlock")
	check(mm.unlocked, "chat unlock")
	ov.lock.__scripts.OnClick(ov.lock, "LeftButton")
	check(not mm.unlocked, "Lock button")
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
	check(not mm:SetUnlocked(true), "refused in combat")
	check(logHas("can't be moved in combat"), "says why")
	check(not mm.unlocked)
	MOCK.combat = false
	mm:SetUnlocked(true, true)
	local ov = mm.overlay
	ov.__scripts.OnDragStart(ov, "LeftButton")
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(not mm.holder.__moving, "drag dropped when combat starts")
	check(not mm.unlocked and not ov:IsShown(), "locked for combat")
	check(logHas("locked for combat"), "told")
	-- a drag started in combat does nothing
	mm.unlocked = true; ov:Show(); MOCK.combat = true; MOCK.log = {}
	ov.__scripts.OnDragStart(ov, "LeftButton")
	check(not mm.holder.__moving, "no StartMoving in combat")
	check(logHas("can't be moved in combat"))
	MOCK.combat = false
	mm:SetUnlocked(false, true)
end)

step("minimap: general unlock mode unlocks the minimap too, and locks it again", function()
	local mm = ns.modules.minimap
	ns.Unlock:Start()
	check(mm.unlocked, "unlocked with the rest")
	ns.Unlock:Stop()
	check(not mm.unlocked, "locked with the rest")
	-- unlocked on its own first: general lock leaves it as it was
	mm:SetUnlocked(true, true)
	ns.Unlock:Start(); ns.Unlock:Stop()
	check(mm.unlocked, "still unlocked")
	mm:SetUnlocked(false, true)
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
	has("Everlook Bar v")
	has("Everlook Bar puts info bars on the screen edges")
	has("Bars \194\187 Place:\n- bar.edge: Where. Choice: top = Top of the screen; bottom = Bottom of the screen;")
	has("Now: top (Top of the screen). Default: top (Top of the screen).")
	has("- bar.bg: Background colour and opacity. Colour: hex rrggbb, or r g b a as 0-1 numbers (a = opacity). Now: 0 0 0 0.6 (#000000). Default: 0 0 0 0.6 (#000000).")
	has("- xp.width: XP bar width. Number 40 to 600. Now: ")
	local clock = t:match("\n(%- clock%.enabled:[^\n]*)")
	check(clock and clock:find("On/off. Now: o", 1, true) and clock:find("Default: off.", 1, true), "clock line: " .. tostring(clock))
	has("- minimap.scale: Minimap size. Number 0.5 to 2.5, step 0.05.")
	has("MORE ABOUT EVERLOOK BAR")
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
