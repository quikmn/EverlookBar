-- Everlook Bar: unlock mode. A grid over the screen; drag bars (to an edge, or anywhere), the minimap and the minimap
-- pieces set to "move"; drag plugins between bars and groups. Escape or Done locks again. Never in combat.
local _, ns = ...
local U = ns.Util
local L = ns.Layout

local Unlock = { active = false, movers = {} }
ns.Unlock = Unlock

local grid, panel, ghost

local function screen()
	return ns.Num(UIParent:GetWidth()) or 1920, ns.Num(UIParent:GetHeight()) or 1080
end

local function makeGrid()
	if grid then return end
	local T = ns.Theme
	grid = CreateFrame("Frame", nil, UIParent)
	grid:SetAllPoints(UIParent)
	grid:SetFrameStrata("BACKGROUND")
	grid.lines = {}
	grid:Hide()
end

-- Lines every 2 grid steps; the centre lines in the accent colour. Textures are reused across sizes.
local function drawGrid()
	local W, H = screen()
	local step = math.max(8, (tonumber(ns.db.grid) or 16) * 2)
	local n = 0
	local T = ns.Theme
	local function line(vertical, pos, centre)
		n = n + 1
		local t = grid.lines[n]
		if not t then
			t = grid:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(U.WHITE)
			grid.lines[n] = t
		end
		t:ClearAllPoints()
		if vertical then
			t:SetPoint("TOPLEFT", grid, "TOPLEFT", pos, 0)
			t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", pos, 0)
			t:SetWidth(1)
		else
			t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, pos)
			t:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, pos)
			t:SetHeight(1)
		end
		if centre then t:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.55) else t:SetVertexColor(1, 1, 1, 0.08) end
		t:Show()
	end
	local cx, cy = math.floor(W / 2), math.floor(H / 2)
	for x = cx % step, W, step do line(true, x, x == cx) end
	for y = cy % step, H, step do line(false, y, y == cy) end
	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

------------------------------------------------------------------------
-- Movers: our own boxes that are dragged; the real frame is re-anchored when the drag ends.
------------------------------------------------------------------------
local function newMover(key)
	local T = ns.Theme
	local m = CreateFrame("Button", nil, UIParent)
	m:SetFrameStrata("FULLSCREEN")
	m:SetMovable(true)
	m:SetClampedToScreen(true)
	m:RegisterForDrag("LeftButton")
	m.bg = m:CreateTexture(nil, "BACKGROUND")
	m.bg:SetAllPoints(); m.bg:SetTexture(U.WHITE)
	m.bg:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.18)
	m.border = U.Border(m, 1, T.accent[1], T.accent[2], T.accent[3], 0.9)
	m.label = m:CreateFontString(nil, "OVERLAY")
	U.SetFont(m.label, 11, "OUTLINE")
	m.label:SetPoint("CENTER")
	m.label:SetTextColor(1, 1, 1)
	m:SetScript("OnDragStart", function(self) self:StartMoving() end)
	m:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = ns.Num(self:GetLeft()) or 0, ns.Num(self:GetBottom()) or 0
		local w, h = ns.Num(self:GetWidth()) or 0, ns.Num(self:GetHeight()) or 0
		if ns.db.snap then x, y = L.Snap(x, ns.db.grid), L.Snap(y, ns.db.grid) end
		if self.onStop then ns.SafeCall(ns, self.onStop, x, y, w, h) end
		Unlock:SyncMovers()
	end)
	Unlock.movers[key] = m
	return m
end

local function mover(key, label, x, y, w, h, onStop)
	local m = Unlock.movers[key] or newMover(key)
	m.label:SetText(label)
	m.onStop = onStop
	m:ClearAllPoints()
	m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	m:SetSize(math.max(16, w), math.max(12, h))
	m.used = true
	m:Show()
	return m
end

-- Put every mover over its frame (after a layout change or a drop).
function Unlock:SyncMovers()
	if not self.active then return end
	for _, m in pairs(self.movers) do m.used = false end
	-- the minimap's moved pieces (the minimap itself has its own mover: unlocked with the rest, see Start)
	local mm = ns.modules.minimap
	if mm and mm.running and not mm.stepAside and mm.holder and Minimap then
		local s = (ns.Num(Minimap:GetEffectiveScale()) or 1) / (ns.Num(UIParent:GetEffectiveScale()) or 1)
		local l, b = ns.Num(Minimap:GetLeft()), ns.Num(Minimap:GetBottom())
		local w, h = ns.Num(Minimap:GetWidth()), ns.Num(Minimap:GetHeight())
		if l and b and w and h then
			local cx, cy = (l + w / 2) * s, (b + h / 2) * s
			for _, e in ipairs(mm.ELEMENTS) do
				if mm:Mode(e.key) == "move" then
					local pos = ns:ModuleDB("minimap").elementPos[e.key] or { 0, 0 }
					local ex, ey = cx + (pos[1] or 0) * s, cy + (pos[2] or 0) * s
					mover("mm-" .. e.key, e.label, ex - 40, ey - 10, 80, 20, function(x, y, mw, mh)
						ns:ModuleDB("minimap").elementPos[e.key] = { math.floor((x + mw / 2 - cx) / s + 0.5), math.floor((y + mh / 2 - cy) / s + 0.5) }
						ns.AfterCombat("minimap-elements", function() mm:ApplyElements() end)
					end)
				end
			end
		end
	end
	for _, m in pairs(self.movers) do if not m.used then m:Hide() end end
end

------------------------------------------------------------------------
-- Dragging plugins between bars
------------------------------------------------------------------------
function Unlock:StartPluginDrag(rec)
	if not ghost then
		ghost = CreateFrame("Frame", nil, UIParent)
		ghost:SetFrameStrata("TOOLTIP")
		ghost:SetSize(120, 20)
		local bg = ghost:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetTexture(U.WHITE); bg:SetVertexColor(0, 0, 0, 0.8)
		U.Border(ghost, 1, ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
		ghost.text = ghost:CreateFontString(nil, "OVERLAY")
		U.SetFont(ghost.text, 11)
		ghost.text:SetPoint("CENTER")
	end
	ghost.text:SetText(ns.Host:Title(rec.key))
	ghost.rec = rec
	-- this OnUpdate exists only while a plugin is being dragged
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local s = ns.Num(UIParent:GetEffectiveScale()) or 1
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (ns.Num(x) or 0) / s, (ns.Num(y) or 0) / s + 14)
	end)
	ghost:Show()
	if rec.button then rec.button:SetAlpha(0.35) end
end

-- Which bar is under the cursor, and where in it.
function Unlock:DropAt(x, y, skipKey)
	for i, f in ipairs(ns.Bars.frames) do
		local bar = ns.db.bars[i]
		local r = ns.Bars.rects and ns.Bars.rects[i]
		if bar and r and bar.shown ~= false and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
			local placed = {}
			for _, it in ipairs(f.items or {}) do
				if it.key ~= skipKey and it.rec.button and it.rec.button.pos then
					local p = it.rec.button.pos
					placed[#placed + 1] = { key = it.key, x = p.x, y = p.y, w = p.w, h = p.h, lane = it.lane, group = it.group }
				end
			end
			local lane, group, index = L.DropTarget(bar, r.w, r.h, x - r.x, (r.y + r.h) - y, placed)
			return i, lane, group, index
		end
	end
end

function Unlock:StopPluginDrag(rec)
	if not ghost or ghost.rec ~= rec then return end
	ghost:SetScript("OnUpdate", nil)
	ghost:Hide()
	ghost.rec = nil
	if rec.button then rec.button:SetAlpha(1) end
	local x, y = GetCursorPosition()
	local s = ns.Num(UIParent:GetEffectiveScale()) or 1
	local bar, lane, group, index = self:DropAt((ns.Num(x) or 0) / s, (ns.Num(y) or 0) / s, rec.key)
	if bar then ns.Host:Place(rec.key, bar, lane, group, index) end
end

------------------------------------------------------------------------
-- Start / stop
------------------------------------------------------------------------
local function makePanel()
	if panel then return end
	local T = ns.Theme
	panel = CreateFrame("Frame", ns.PREFIX .. "UnlockPanel", UIParent)
	panel.eluiTheme = T
	panel:SetSize(360, 96)
	local saved = ns.db.unlockPanel
	if type(saved) == "table" and tonumber(saved[1]) then
		panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved[1], saved[2])
	else
		panel:SetPoint("TOP", 0, -120)
	end
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		x, y = ns.Num(x), ns.Num(y)
		if x and y then ns.db.unlockPanel = { math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	U.Solid(panel, "BACKGROUND", T.bg[1], T.bg[2], T.bg[3], 0.97):SetAllPoints()
	local top = U.Solid(panel, "ARTWORK", T.accent[1], T.accent[2], T.accent[3], 1)
	top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
	U.Border(panel, 1, T.border[1], T.border[2], T.border[3], 1)
	local title = ns.UI.Text(panel, T.fontTitle, T.text)
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText(ns.NAME .. " is unlocked")
	local hint = ns.UI.Text(panel, T.fontSmall + 1, T.muted)
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	hint:SetWidth(332)
	hint:SetText("Drag bars to an edge or anywhere, the minimap where you like, plugins between bars. Escape locks.")
	local done = ns.UI.Button(panel, "Done", function() Unlock:Stop() end, 90, "accent")
	done:SetPoint("BOTTOMRIGHT", -12, 10)
	local snap = ns.UI.Button(panel, "", function(b)
		ns.db.snap = not ns.db.snap
		b:SetText(ns.db.snap and "Snap to grid: on" or "Snap to grid: off")
	end, 150)
	snap:SetPoint("BOTTOMLEFT", 12, 10)
	panel.snap = snap
	panel:SetScript("OnShow", function() snap:SetText(ns.db.snap and "Snap to grid: on" or "Snap to grid: off") end)
	panel:SetScript("OnHide", function() if Unlock.active then Unlock:Stop() end end)
	ns.UI.CloseOnEscape(panel)
end

function Unlock:Start()
	if self.active then return end
	if InCombatLockdown() then ns:Print("unlock after combat.") return end
	self.active = true
	makeGrid()
	makePanel()
	drawGrid()
	grid:Show()
	panel:Show()
	ns.Host:RefreshAll()
	self:SyncMovers()
	local mm = ns.modules.minimap
	if mm and mm.running and not mm.stepAside and not mm.unlocked then
		self.unlockedMinimap = mm:SetUnlocked(true, true)
	end
	if ns.Options then ns.Options:Refresh() end
end

function Unlock:Stop()
	if not self.active then return end
	self.active = false
	if grid then grid:Hide() end
	if panel and panel:IsShown() then panel:Hide() end
	if ghost then ghost:SetScript("OnUpdate", nil); ghost:Hide() end
	for _, m in pairs(self.movers) do m:Hide() end
	-- lock the minimap again only if unlock mode unlocked it
	local mm = ns.modules.minimap
	if self.unlockedMinimap and mm and mm.unlocked then mm:SetUnlocked(false, true) end
	self.unlockedMinimap = nil
	ns.Host:RefreshAll()
	if ns.Options then ns.Options:Refresh() end
end

function Unlock:Toggle() if self.active then self:Stop() else self:Start() end end

ns.On("PLAYER_REGEN_DISABLED", Unlock, function() if Unlock.active then Unlock:Stop(); ns:Print("locked for combat.") end end)
