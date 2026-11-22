-- Offline tests for the taskbar, the Start menu and window tiling (loaded by tests/run.lua, which passes its helpers).
local ns, step, check, eq, flush, slash, ROOT = ...
local T = ns.Tiling
local UI = ns.UI

local function near(a, b, what, tol) if math.abs(a - b) > (tol or 1) then error((what or "value") .. ": expected " .. b .. ", got " .. a, 2) end end
local function overlap(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
local function point(f) local p = f.__points[1]; return p and p[4], p and p[5] end

------------------------------------------------------------------------
-- Pure maths
------------------------------------------------------------------------
step("tiling: work area is the screen minus docked bars; free and hidden bars take none", function()
	local bars = {
		{ edge = "top", lanes = 1, laneSize = 22 }, { edge = "bottom", lanes = 1, laneSize = 32, kind = "taskbar" },
		{ edge = "left", lanes = 1, laneSize = 150 }, { edge = "free", lanes = 1, laneSize = 22 },
		{ edge = "right", lanes = 1, laneSize = 100, shown = false },
	}
	local a = T.WorkArea(bars, 1920, 1080)
	eq(a.x, 150, "left bar"); eq(a.y, 32, "taskbar at the bottom"); eq(a.w, 1920 - 150, "width"); eq(a.h, 1080 - 22 - 32, "height")
end)

step("tiling: halves, quarters and thirds fill the area with an even gap", function()
	local area = { x = 0, y = 32, w = 1920, h = 1048 }
	local L, R = T.SnapRect("left", area, 4), T.SnapRect("right", area, 4)
	eq(L.x, 4, "left edge gap"); eq(L.w, 960 - 4 - 2, "left width"); eq(L.y, 36, "bottom gap"); eq(L.h, 1048 - 8, "full height")
	eq(R.x - (L.x + L.w), 4, "gap between halves"); eq(R.x + R.w, 1920 - 4, "right edge gap")
	local m = T.SnapRect("max", area, 0)
	eq(m.x, 0); eq(m.y, 32); eq(m.w, 1920); eq(m.h, 1048)
	local q = { T.SnapRect("topleft", area, 4), T.SnapRect("topright", area, 4), T.SnapRect("bottomleft", area, 4), T.SnapRect("bottomright", area, 4) }
	for i = 1, 4 do for j = i + 1, 4 do check(not overlap(q[i], q[j]), "quarters overlap " .. i .. j) end end
	check(q[1].y > q[3].y, "top quarter above the bottom one")
	local t3 = { T.SnapRect("left3", area, 0), T.SnapRect("center3", area, 0), T.SnapRect("right3", area, 0) }
	near(t3[1].w, 640, "third"); near(t3[2].x, 640, "middle third"); near(t3[3].x + t3[3].w, 1920, "right third ends at the edge")
	check(T.SnapRect("nonsense", area, 0) == nil, "unknown zone")
	for _, z in ipairs(T.ZONES) do check(T.SnapRect(z.id, area, 4), "zone " .. z.id) end
end)

step("tiling: tile all makes a coherent grid with no holes and no overlaps", function()
	local area = { x = 0, y = 0, w = 1920, h = 1080 }
	for n = 1, 9 do
		local r = T.TileRects(n, area, 4)
		eq(#r, n, "count " .. n)
		local sum = 0
		for i = 1, n do
			sum = sum + (r[i].w + 4) * (r[i].h + 4)
			for j = i + 1, n do check(not overlap(r[i], r[j]), n .. " windows: " .. i .. " and " .. j .. " overlap") end
		end
		near(sum, 1916 * 1076, n .. " windows fill the area", 1916 * 1076 * 0.01)
	end
	local cols, rows = T.Grid(4, 16 / 9); eq(cols, 2, "4 in 2 columns"); eq(rows, 2)
	cols, rows = T.Grid(3, 16 / 9); eq(cols, 2, "3: two on top, one across the bottom"); eq(rows, 2)
	cols, rows = T.Grid(3, 4); eq(cols, 3, "3 side by side on a very wide area"); eq(rows, 1)
	local r = T.TileRects(3, { x = 0, y = 0, w = 1000, h = 2000 }, 0)
	check(r[1].y > r[2].y, "a tall area stacks them")
	local five = T.TileRects(5, area, 0)
	check(five[1].y > five[5].y, "row 1 at the top")
	near(five[4].w + five[5].w, 1920, "a short last row spans the width")
	eq(#T.TileRects(0, area, 0), 0, "none")
end)

step("tiling: drag to the top edge maximizes, sides take halves, corners quarters", function()
	eq(T.DragZone(960, 1080, 1920, 1080), "max", "top")
	eq(T.DragZone(0, 540, 1920, 1080), "left", "left")
	eq(T.DragZone(1920, 540, 1920, 1080), "right", "right")
	eq(T.DragZone(0, 1070, 1920, 1080), "topleft", "top left")
	eq(T.DragZone(1919, 2, 1920, 1080), "bottomright", "bottom right")
	eq(T.DragZone(30, 1080, 1920, 1080), "topleft", "along the top edge near a corner")
	check(T.DragZone(960, 540, 1920, 1080) == nil, "middle: no snap")
	check(T.DragZone(960, 0, 1920, 1080) == nil, "bottom middle: no snap (the taskbar is there)")
end)

step("tiling: a window that can't resize keeps its size, centred; limits are kept", function()
	local rect = { x = 0, y = 0, w = 960, h = 1000 }
	local r = T.Fit(rect, { w = 400, h = 300, resizable = false }, 1920, 1080)
	eq(r.w, 400); eq(r.h, 300); eq(r.x, 280, "centred across"); eq(r.y, 700, "top aligned")
	r = T.Fit(rect, { w = 400, h = 300, resizable = true, minW = 1200, minH = 0 }, 1920, 1080)
	eq(r.w, 1200, "never below its minimum"); check(r.x >= 0 and r.x + r.w <= 1920, "stays on screen")
	r = T.Fit(rect, { resizable = true, maxW = 500, maxH = 400 }, 1920, 1080)
	eq(r.w, 500); eq(r.h, 400)
end)

step("tiling: taskbar buttons shrink, then the rest go into a more button", function()
	local size, shown, more = T.Strip(3, 1000, { maxW = 180, minW = 96 })
	eq(size, 180); eq(shown, 3); check(not more, "all fit")
	size, shown, more = T.Strip(10, 1000, { maxW = 180, minW = 96, gap = 2 })
	eq(size, 98, "shrunk"); eq(shown, 10)
	size, shown, more = T.Strip(20, 1000, { maxW = 180, minW = 96, gap = 2, moreW = 32 })
	eq(size, 96); check(more, "more button"); check(shown * 98 + 32 <= 1002, "they fit with the more button")
	size, shown, more = T.Strip(50, 600, { vertical = true, itemH = 28, gap = 2 })
	eq(size, 28); check(more and (shown + 1) * 30 <= 602, "side bar: what fits, then more")
end)

step("tiling: the combat queue runs in order, the newest action per window wins", function()
	local q, ran = T.NewQueue(), {}
	q:Add("a:vis", function() ran[#ran + 1] = "a1" end)
	q:Add("b:geo", function() ran[#ran + 1] = "b" end)
	q:Add("a:vis", function() ran[#ran + 1] = "a2" end)
	eq(q:Count(), 2, "one per key")
	q:Drop("nothing")
	eq(q:Run(), 2)
	eq(table.concat(ran, ","), "b,a2", "order and newest wins")
	eq(q:Count(), 0, "empty after")
end)

step("layout: the taskbar is the outermost bar on its edge; its strip takes the room before the plugins", function()
	local L = ns.Layout
	local bars = { { edge = "bottom", lanes = 1, laneSize = 22 }, { edge = "bottom", lanes = 1, laneSize = 32, kind = "taskbar" } }
	local r = L.BarRects(bars, 1920, 1080)
	eq(r[2].y, 0, "taskbar at the very bottom"); eq(r[1].y, 32, "the other bar above it")
	local bar = { edge = "bottom", lanes = 1, laneSize = 32, spacing = 10, padding = 4 }
	local items = { { key = "clock", w = 60, lane = 1, group = "right", order = 1 }, { key = "a", w = 50, lane = 1, group = "left", order = 1 } }
	local len = L.TaskStripLength(bar, 1920, 32, items, 26)
	eq(len, 1920 - 4 - 60 - 10 - 4 - 50 - 10, "up to the clock, after the left plugin")
	local strip = { key = "__taskbar", len = len, lane = 1, group = "left", order = -1e9 }
	items[#items + 1] = strip
	local pos = L.PlaceItems(bar, 1920, 32, items, 26)
	eq(pos[strip].x, 4, "strip first"); eq(pos[items[2]].x, 4 + len + 10, "left plugin after it")
	check(pos[items[2]].x + 50 + 10 <= pos[items[1]].x, "nothing overlaps the clock")
	local side = { edge = "left", lanes = 1, laneSize = 180, spacing = 2, padding = 4 }
	local sitems = { { key = "x", w = 300, lane = 1, group = "right", order = 1 } }
	eq(L.TaskStripLength(side, 180, 1000, sitems, 26), 1000 - 4 - 26 - 2 - 4, "side bar: the strip runs down to the plugins")
end)

------------------------------------------------------------------------
-- The taskbar in the addon
------------------------------------------------------------------------
local TB, WM = ns.Taskbar, ns.WM

step("taskbar: off until switched on; nothing made, nothing moved", function()
	check(not ns.db.taskbar.enabled, "off by default")
	check(TB:Bar() == nil, "no taskbar bar")
	check(not WM.running, "no window watching")
	check(TB.strip == nil, "no strip")
	eq(ns.db.taskbar.edge, "bottom", "default edge")
end)

-- one of our windows (EverlookUI chrome, movable and resizable)
local function ourWindow(name, title, w, h)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w or 400, h or 300)
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f.title = f:CreateFontString()
	f.title:SetText(title)
	f.drags = 0
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.drags = self.drags + 1 end)
	UI.WindowChrome(f, UI.Theme)
	f:Hide()
	return f
end

local win1, win2, win3
step("taskbar: switched on from chat, a bar at the bottom with Start", function()
	slash("taskbar on")
	flush()
	local i, bar = TB:Bar()
	check(i and bar.kind == "taskbar" and bar.shown ~= false, "taskbar bar made and shown")
	eq(bar.edge, "bottom", "bottom")
	check(WM.running, "watching windows")
	check(TB.strip and TB.strip:IsShown(), "strip shown")
	check(TB.start and TB.start:IsShown(), "Start button")
	local area = WM:WorkArea()
	eq(area.y, 32, "work area above the taskbar")
	slash("taskbar.edge left")
	eq(ns.db.bars[i].edge, "left", "edge from chat")
	check(TB.vertical, "a side taskbar stacks its buttons")
	slash("taskbar bottom")
	eq(ns.db.bars[i].edge, "bottom", "back to the bottom")
	eq(ns.db.bars[i].laneSize, 32, "its thickness came back")
end)

step("taskbar: every one of our windows gets a button with its title; click minimizes and restores it", function()
	win1 = ourWindow("TestRecipes", "Recipes")
	local hides = {}
	win1:HookScript("OnHide", function(self) hides[#hides + 1] = self.eluiMinimizing and "min" or "close" end)
	win1:Show()
	WM:Scan(); flush()
	local rec = WM:Get(win1)
	check(rec and rec.kind == "ours", "listed as ours")
	local b = TB.buttons[1]
	check(b and b:IsShown() and b.winRec == rec, "a button")
	eq(b.text:GetText(), "Recipes", "its title")
	win1:Raise(); WM:Scan()
	b:GetScript("OnClick")(b, "LeftButton")
	flush()
	check(not win1:IsShown(), "click on the window in front minimizes it")
	eq(hides[#hides], "min", "the window knows it is being minimized")
	check(rec.minimized and WM:Get(win1) == rec and b:IsShown(), "still on the taskbar")
	b:GetScript("OnClick")(b, "LeftButton")
	flush()
	check(win1:IsShown() and not rec.minimized, "click again: back")
	win1:Hide(); flush()
	check(WM:Get(win1) == nil, "closed (not minimized): its button goes")
	eq(hides[#hides], "close", "a real close")
	win1:Show(); flush()
	check(WM:Get(win1) ~= nil, "opened again: listed again")
end)

step("taskbar: snap, maximize and restore size; never the game's windows", function()
	local rec = WM:Get(win1)
	win1:ClearAllPoints(); win1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60); win1:SetSize(400, 300)
	check(WM:Snap(rec, "left"), "snapped")
	local area, gap = WM:WorkArea(), WM:Gap()
	local x, y = point(win1)
	eq(x, area.x + gap, "left edge"); eq(win1.__w, math.floor(area.w / 2 - gap - gap / 2 + 0.5), "half the width")
	eq(win1.__h, area.h - 2 * gap, "full height of the work area (not under the bars)")
	eq(rec.snap, "left")
	WM:ToggleMaximize(rec)
	eq(rec.snap, "max", "maximized")
	eq(win1.__w, area.w - 2 * gap, "the whole work area")
	WM:ToggleMaximize(rec)
	check(rec.snap == nil, "restored")
	local p = win1.__points[1]
	eq(p[1], "TOPLEFT", "its own anchor back"); eq(p[4], 50, "x back"); eq(p[5], -60, "y back"); eq(win1.__w, 400, "size back")
	-- from chat-less menus: the window menu has every snap layout
	local b = TB.buttons[1]
	b:GetScript("OnClick")(b, "RightButton")
	check(UI.IsPopupShown(), "right-click menu")
	UI.ClosePopup()
end)

step("taskbar: tile all arranges our windows without overlaps", function()
	win2 = ourWindow("TestCraftList", "Crafting list"); win2:Show()
	win3 = ourWindow("TestFavor", "Merchant's Favor", 300, 200); win3:SetResizable(false); win3:Show()
	WM:Scan(); flush()
	eq(#WM.recs, 3, "three windows")
	eq(TB:TileAll(), 3, "all three tiled")
	local rects = {}
	for _, f in ipairs({ win1, win2, win3 }) do
		local x, y = point(f)
		rects[#rects + 1] = { x = x, y = y, w = f.__w, h = f.__h }
		eq(f.__points[1][1], "BOTTOMLEFT", "placed")
	end
	for i = 1, 3 do for j = i + 1, 3 do check(not overlap(rects[i], rects[j]), "tiles " .. i .. "," .. j .. " overlap") end end
	eq(win3.__w, 300, "a window that can't resize keeps its size")
	check(WM:Get(win2).snap == "tile", "remembered as tiled")
	WM:Unsnap(WM:Get(win2))
	eq(win2.__points[1][1], "CENTER", "restore size puts it back")
end)

step("taskbar: the game's windows open and close through the game's button (secure), never moved", function()
	local micro = CreateFrame("Button", "CharacterMicroButton", UIParent)
	local clicks = 0
	micro:SetScript("OnClick", function() clicks = clicks + 1 end)
	local cf = CreateFrame("Frame", "CharacterFrame", UIParent)
	cf:SetSize(380, 520)
	cf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	cf:Show()
	WM:Scan(); flush()
	local rec = WM:Get(cf)
	check(rec and rec.kind == "blizzard", "listed as the game's")
	eq(WM:Title(rec), CHARACTER_BUTTON or "Character", "its name")
	check(not WM:CanMove(rec) and not WM:Snap(rec, "left"), "never snapped")
	eq(WM:TileAll(), 3, "tile all leaves it out")
	eq(cf.__points[1][1], "TOPLEFT", "its place untouched"); eq(cf.__points[1][4], 16, "x untouched")
	check(not WM:Minimize(rec) and cf:IsShown(), "no plain minimize (that would run the game's code tainted)")
	-- its button: in front -> the secure click closes it, and it stays as minimized
	cf:Raise(); WM:Scan(); TB:Refresh()
	local b
	for _, x in ipairs(TB.buttons) do if x.winRec == rec then b = x end end
	check(b and b:IsShown(), "a button")
	b:GetScript("OnEnter")(b)
	local c = ns.SecureClick:Frame()
	check(c and c:IsShown() and c.owner == b, "secure cover on the button")
	eq(c:GetAttribute("type1"), "click"); eq(c:GetAttribute("clickbutton1"), micro, "clicks the micro button")
	eq(c.__points[1][2], UIParent, "cover anchored to UIParent")
	c.__scripts.PreClick(c, "LeftButton")
	cf:Hide() -- what the micro button does
	c.__scripts.PostClick(c, "LeftButton")
	flush()
	check(rec.minimized and WM:Get(cf) == rec, "closed by its button: kept as minimized")
	c.__scripts.OnLeave(c)
	-- behind another window: no secure click, the plain click raises it
	cf:Show(); flush()
	win1:Raise(); WM:Scan()
	check(WM:Active() ~= rec, "another window in front")
	b:GetScript("OnEnter")(b)
	check(not (c:IsShown() and c.owner == b), "no cover: a plain raise")
	local before = cf.__level
	b:GetScript("OnClick")(b, "LeftButton")
	check(cf.__level > before and cf:IsShown(), "raised, not closed")
	b:GetScript("OnLeave")(b)
	-- closed with its own X: the button goes
	cf:Hide(); flush()
	check(WM:Get(cf) == nil, "gone")
end)

step("taskbar: combat. Protected windows wait; buttons stay put; the game's clicks keep working", function()
	local cf = CharacterFrame
	cf:Show(); flush()
	local rec = WM:Get(cf)
	win1.__protected = true -- e.g. a secure button inside
	local r1 = WM:Get(win1)
	MOCK.Fire("PLAYER_REGEN_DISABLED") -- comes just before the lockdown
	MOCK.combat = true
	-- the taskbar button of the game's window got its cover for the fight
	local b
	for _, x in ipairs(TB.buttons) do if x.winRec == rec then b = x end end
	local covered = ns.SecureClick:Covers()[b]
	check(covered or WM:Active() ~= rec, "the game's window in front has its secure click for combat")
	check(not WM:Snap(r1, "right") and r1.snap ~= "right", "no move in combat")
	check(not WM:Minimize(r1), "protected in combat: waits")
	check(win1:IsShown(), "not hidden in combat")
	check(not WM:Raise(rec), "the game's window: raise waits")
	eq(WM.queue:Count(), 3, "three waiting (one per window and kind)")
	check(#MOCK.errorsShown > 0, "told once")
	-- a window closes in combat: its button stays where it is until combat ends
	local slots = #WM.recs
	win2:Hide(); flush()
	eq(#WM.recs, slots, "nothing taken off in combat")
	check(WM:Get(win2).gone, "marked closed")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED"); flush()
	check(not win1:IsShown() and r1.minimized, "minimized after combat")
	eq(r1.snap, "right", "snapped after combat")
	check(WM:Get(win2) == nil, "the closed one is gone now")
	eq(WM.queue:Count(), 0, "queue empty")
	win1.__protected = nil
	WM:Restore(r1); flush()
	cf:Hide(); flush()
end)

step("taskbar: other addons' windows are listed best effort; HUD frames and ignored ones are not", function()
	local other = CreateFrame("Frame", "SomeAddonMainWindow", UIParent)
	other:SetSize(500, 400); other:SetMovable(true); other:EnableMouse(true); other:SetPoint("CENTER")
	other.CloseButton = CreateFrame("Button", nil, other)
	local hud = CreateFrame("Frame", "SomeAddonActionBarFrame", UIParent)
	hud:SetSize(500, 400); hud:SetMovable(true); hud:EnableMouse(true); hud.CloseButton = CreateFrame("Button", nil, hud)
	local plain = CreateFrame("Frame", "SomeAddonBigPanel", UIParent) -- no close button or title: not a window
	plain:SetSize(500, 400); plain:SetMovable(true); plain:EnableMouse(true)
	local prot = CreateFrame("Frame", "SomeAddonSecureWindow", UIParent)
	prot:SetSize(500, 400); prot:SetMovable(true); prot:EnableMouse(true); prot.CloseButton = other.CloseButton; prot.__protected = true
	WM:Scan(true); flush()
	local rec = WM:Get(other)
	check(rec and rec.kind == "other", "another addon's window")
	eq(WM:Title(rec), "Some Addon Main", "a name from its frame name")
	check(not WM:Get(hud) and not WM:Get(plain) and not WM:Get(prot), "HUD, plain and protected frames left alone")
	check(WM:Minimize(rec) and not other:IsShown(), "minimized")
	check(WM:Restore(rec) and other:IsShown(), "restored")
	check(WM:Snap(rec, "right"), "snapped")
	check(WM:Ignore(rec) and WM:Get(other) == nil and ns.db.taskbar.ignore.SomeAddonMainWindow, "Don't list this window")
	WM:Scan(true)
	check(WM:Get(other) == nil, "stays off")
	ns.db.taskbar.ignore.SomeAddonMainWindow = nil
	other:Hide(); hud:Hide(); plain:Hide(); prot:Hide()
	slash("taskbar.others off")
	other:Show(); WM:Scan(true)
	check(WM:Get(other) == nil, "setting off: not listed")
	slash("taskbar.others on")
	other:Hide(); WM:Scan(true)
end)

step("taskbar: drag one of our windows to a screen edge to snap it; drag it off to get its size back", function()
	win1:Show(); WM:Scan(); flush()
	local rec = WM:Get(win1)
	WM:Unsnap(rec)
	win1:SetSize(420, 320)
	win1:GetScript("OnDragStart")(win1)
	MOCK.cursorX, MOCK.cursorY = 0, 540 -- the left edge
	WM:DragTick()
	local pv = WM:Preview()
	check(pv:IsShown() and pv.zone == "left", "preview of the left half")
	win1:GetScript("OnDragStop")(win1)
	eq(win1.drags, 1, "the window's own drag stop still ran")
	eq(rec.snap, "left", "snapped on drop")
	check(not pv:IsShown(), "preview gone")
	-- drag it again: off the snap, its own size back
	win1:GetScript("OnDragStart")(win1)
	eq(win1.__w, 420, "own width back"); eq(win1.__h, 320, "own height back")
	MOCK.cursorX, MOCK.cursorY = 900, 500
	WM:DragTick()
	check(pv.zone == nil, "no snap in the middle")
	win1:GetScript("OnDragStop")(win1)
	check(rec.snap == nil, "stays where dropped")
	ns.db.taskbar.snap = false
	win1:GetScript("OnDragStart")(win1)
	MOCK.cursorX, MOCK.cursorY = 0, 540
	win1:GetScript("OnDragStop")(win1)
	check(rec.snap == nil, "setting off: no snapping")
	ns.db.taskbar.snap = true
	MOCK.cursorX, MOCK.cursorY = 0, 0
end)

------------------------------------------------------------------------
-- The Start menu
------------------------------------------------------------------------
local SM = ns.StartMenu
step("start menu: lists EverlookDB windows and pages, the game's panels, professions and launchers", function()
	local micro = CharacterMicroButton
	QuestLogMicroButton = CreateFrame("Button", "QuestLogMicroButton", UIParent)
	local list, byId = SM:Entries()
	check(byId["app:EverlookDB Bar"], "our own window")
	check(byId["page:EverlookDB Bar:taskbar"] and byId["page:EverlookDB Bar:taskbar"].hidden, "its pages, for the search")
	check(byId["game:character"] and byId["game:quests"], "game panels with a button")
	check(byId["game:map"], "the map: a plain way when the game has no button")
	check(not byId["game:spellbook"], "no spellbook entry without the game's button (opening it from addon code taints it)")
	check(byId["game:macros"] and byId["game:keybindings"] and byId["game:settings"], "macros, key bindings, settings")
	check(byId["prof:186"], "a profession (Mining)")
	local found = SM:Find(list, "task")
	check(found[1] and found[1].id == "page:EverlookDB Bar:taskbar", "search finds a page")
	found = SM:Find(list, "gear")
	eq(found[1] and found[1].id, "game:character", "keywords: gear -> Character")
	check(#SM:Find(list, "zzzz") == 0, "nothing")
	-- an EverlookDB addon with an older copy of the window library: opened with its slash command
	MOCK.loaded.EverlookDBMail = true
	local opened
	SlashCmdList.EVERLOOKMAIL = function(msg) opened = msg end
	list, byId = SM:Entries()
	check(byId["app:EverlookDB Mail"], "found by its slash command")
	byId["app:EverlookDB Mail"].run()
	eq(opened, "", "bare slash command opens it")
	MOCK.loaded.EverlookDBMail = nil; SlashCmdList.EVERLOOKMAIL = nil
	-- launchers
	local ldb = LibStub("LibDataBroker-1.1")
	local clicked
	ldb:NewDataObject("SomeLauncher", { type = "launcher", label = "Some Launcher", icon = 134400, OnClick = function(_, m) clicked = m end })
	flush()
	list, byId = SM:Entries()
	check(byId["ldb:SomeLauncher"], "an addon launcher")
	byId["ldb:SomeLauncher"].run(UIParent)
	eq(clicked, "LeftButton", "its click")
end)

step("start menu: opens at Start, search filters, Enter opens the first, recent and pinned", function()
	slash("start")
	check(SM:IsShown(), "/ebar start opens it")
	eq(SM.frame.__points[1][2], TB.start, "next to the Start button")
	check(SM.tiles[1] and SM.tiles[1]:IsShown(), "pinned tiles")
	SM.box:SetText("everlookdb bar")
	eq(SM.results[1].id, "app:EverlookDB Bar", "first result")
	SM.box:GetScript("OnEnterPressed")(SM.box)
	check(not SM:IsShown(), "Enter opened it and the menu closed")
	check(ns.app:IsShown(), "the settings window is open")
	eq(ns.db.taskbar.recent[1], "app:EverlookDB Bar", "remembered as recent")
	ns.app:Close()
	-- pin and unpin
	SM:SetPinned("game:quests", false)
	check(not SM:IsPinned("game:quests"), "unpinned")
	SM:SetPinned("game:quests", true)
	check(SM:IsPinned("game:quests"), "pinned")
	-- Start toggles; Escape in the search closes it
	TB.start:GetScript("OnClick")(TB.start, "LeftButton")
	check(SM:IsShown(), "Start opens it")
	SM.box:GetScript("OnEscapePressed")(SM.box)
	check(not SM:IsShown(), "Escape closes it")
end)

step("start menu: the game's panels open through the game's buttons; Enter arms a second press", function()
	local micro = CharacterMicroButton
	SM:Show("character")
	local row = SM.rows[1]
	eq(row.entry.id, "game:character", "the row")
	row:GetScript("OnEnter")(row)
	local c = ns.SecureClick:Frame()
	check(c:IsShown() and c.owner == row, "secure cover on the row")
	eq(c:GetAttribute("clickbutton1"), micro, "clicks the micro button")
	c.__scripts.PostClick(c, "LeftButton")
	check(not SM:IsShown(), "the menu closed after the secure click")
	check(not (c:IsShown() and c.owner == row), "and its cover went with it")
	eq(ns.db.taskbar.recent[1], "game:character", "recent")
	-- Enter: a key can't click securely, so it arms Enter once more
	SM:Show("character")
	SM.box:GetScript("OnEnterPressed")(SM.box)
	check(SM:IsShown(), "still open")
	eq(MOCK.bindings.ENTER, ns.PREFIX .. "StartEnter", "Enter bound to the secure button")
	eq(SM.enterButton:GetAttribute("clickbutton"), micro, "which clicks the micro button")
	SM.enterButton.__scripts.PostClick(SM.enterButton)
	check(not SM:IsShown(), "second Enter opened it")
	check(MOCK.bindings.ENTER == nil, "binding cleared")
	-- combat: the menu closes when it starts; a game panel says to use its key
	SM:Show("character")
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(not SM:IsShown(), "closed at combat start")
	MOCK.combat = true
	SM:Show("character")
	local n = #MOCK.errorsShown
	check(not SM:Run(SM.results[1], nil, true), "not opened from addon code in combat")
	check(#MOCK.errorsShown > n, "told why")
	SM:Hide()
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED"); flush()
end)

step("taskbar: off again: minimized windows come back, the bar hides, nothing keeps running", function()
	win1:Show(); WM:Scan(); flush()
	WM:Minimize(WM:Get(win1))
	check(not win1:IsShown(), "minimized")
	slash("taskbar off")
	flush()
	check(win1:IsShown(), "minimized window back")
	check(not WM.running and #WM.recs == 0, "stopped")
	local _, bar = TB:Bar()
	check(bar and bar.shown == false, "bar hidden (kept for next time)")
	check(not TB.strip:IsShown(), "strip hidden")
	eq(WM:WorkArea().y, 0, "no room taken at the bottom")
	win1:Hide(); win2:Hide(); win3:Hide()
	-- deleting the taskbar's bar switches it off too
	slash("taskbar on")
	local i = TB:Bar()
	ns.Bars:RemoveBar(i)
	check(not ns.db.taskbar.enabled and not WM.running, "deleted bar: taskbar off")
end)

step("taskbar: no taint. The game's panels are never opened, closed, moved or hidden from addon code", function()
	for _, file in ipairs({ "Windows.lua", "Taskbar.lua", "StartMenu.lua", "Tiling.lua" }) do
		local src = assert(io.open(ROOT .. "/" .. file)):read("*a")
		for _, bad in ipairs({ "ToggleCharacter", "ShowUIPanel", "HideUIPanel", "ToggleSpellBook", "ToggleTalentFrame",
			"COMBAT_LOG_EVENT", "UISpecialFrames", "UIPanelWindows%[[^%]]+%]%s*=", "CloseAllWindows", "SetAttribute%(\"type\", \"macro\"" }) do
			check(not src:find(bad), file .. " uses " .. bad)
		end
	end
	-- the window manager never writes into a game frame's fields
	local src = assert(io.open(ROOT .. "/Windows.lua")):read("*a")
	check(src:find("function WM:CanMinimize%(rec%)%s+if rec.kind == \"blizzard\" then return false end"), "the game's windows are never hidden by the window manager")
end)
