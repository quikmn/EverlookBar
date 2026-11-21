-- EverlookDB Bar: edit mode ("Unlock to move" in the settings, /ebar unlock). A grid over the screen; drag bars (to an
-- edge, or anywhere), the minimap and the pieces around it; drag plugins between bars and groups. A small control in
-- the middle of the minimap has Done and Reset positions; Escape ends it too. Never in combat.
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
-- The pieces around the minimap: a labelled box over each one that is switched on. Dragging a box moves the piece
-- along the minimap's edge (the round ring or the square's outline), snapping to the corners and the middle of the
-- sides; with Shift held it goes anywhere. The piece itself is never dragged: it is re-anchored as the box moves.
------------------------------------------------------------------------
local function minimapModule()
	local mm = ns.modules.minimap
	if mm and mm.running and not mm.stepAside and mm.holder and Minimap then return mm end
end
Unlock.Minimap = minimapModule

-- The minimap's size on screen against UIParent's: its own units times this are UIParent units.
local function mapScale()
	return (ns.Num(Minimap:GetEffectiveScale()) or 1) / (ns.Num(UIParent:GetEffectiveScale()) or 1)
end

-- The cursor from the minimap's centre, in the minimap's own units.
function Unlock:CursorOnMap()
	local cx, cy = GetCursorPosition()
	local ui = ns.Num(UIParent:GetEffectiveScale()) or 1
	local mx, my = Minimap:GetCenter()
	cx, cy, mx, my = ns.Num(cx), ns.Num(cy), ns.Num(mx), ns.Num(my)
	if not (cx and cy and mx and my) then return nil end
	local s = mapScale()
	return (cx / ui - mx * s) / s, (cy / ui - my * s) / s
end

local function newMover(key)
	local T = ns.Theme
	local mm = ns.modules.minimap
	local e = mm.ELEMENT[key]
	local m = CreateFrame("Button", nil, UIParent)
	m.key = key
	-- above the control in the middle of the map: on a small map the two overlap, and the boxes stay in reach
	m:SetFrameStrata("FULLSCREEN_DIALOG")
	m:SetFrameLevel(30)
	m:RegisterForDrag("LeftButton")
	m:RegisterForClicks("RightButtonUp")
	m.bg = m:CreateTexture(nil, "BACKGROUND")
	m.bg:SetAllPoints(); m.bg:SetTexture(U.WHITE)
	m.border = U.Border(m, 1, T.accent[1], T.accent[2], T.accent[3], 1)
	m.tag = m:CreateFontString(nil, "OVERLAY")
	U.SetFont(m.tag, 10, "OUTLINE")
	m.tag:SetTextColor(1, 1, 1)
	m.tag:SetText(e.short or e.label)
	function m:Paint()
		local hot = self.dragging or self.hover
		if hot then
			self.bg:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.5)
		elseif self.inside then
			-- the name is inside the box (a wide piece, mostly text): a dark box, so the name reads
			self.bg:SetVertexColor(T.bg[1], T.bg[2], T.bg[3], 0.85)
		else
			self.bg:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.25)
		end
	end
	m:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		GameTooltip:Hide()
		self.dragging = true
		self:Paint()
		-- this OnUpdate exists only while a piece is being dragged
		self:SetScript("OnUpdate", function(mv)
			local x, y = Unlock:CursorOnMap()
			if x then mm:DragPieceTo(mv.key, x, y, IsShiftKeyDown and IsShiftKeyDown() and true or false) end
			Unlock:SyncMovers()
		end)
	end)
	m:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		self:Paint()
		Unlock:SyncMovers()
		if ns.Options then ns.Options:Refresh() end
	end)
	m:SetScript("OnClick", function(self, button)
		if button == "RightButton" then mm:ResetPiece(self.key); if ns.Options then ns.Options:Refresh() end end
	end)
	m:SetScript("OnEnter", function(self)
		self.hover = true; self:Paint()
		if self.dragging then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine(e.label, 1, 1, 1)
		GameTooltip:AddLine("Drag it along the minimap's edge. Hold Shift to put it anywhere. Right-click: back to its own place.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	m:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); GameTooltip:Hide() end)
	m:Paint()
	Unlock.movers[key] = m
	return m
end

-- Put a box over every piece that is on (after a toggle, a drag, a new minimap size or shape).
function Unlock:SyncMovers()
	if not self.active then return end
	if panel and panel.onMap then self:PlacePanel() end -- its size follows the map's
	for _, m in pairs(self.movers) do m.used = false end
	local mm = minimapModule()
	if mm then
		local s = mapScale()
		for _, e in ipairs(mm.ELEMENTS) do
			local parts = not e.fixed and mm:PieceShown(e.key) and mm:Parts(e) or nil
			if parts and #parts > 0 then
				local m = self.movers[e.key] or newMover(e.key)
				local w, h = mm:PieceSize(e)
				local x, y = mm:PieceXY(e.key)
				local bw, bh = (math.max(18, w) + 4) * s, (math.max(14, h) + 4) * s
				m:SetSize(bw, bh)
				m:ClearAllPoints()
				m:SetPoint("CENTER", Minimap, "CENTER", x * s, y * s)
				-- the name: inside a box wide enough for it, else beside the box on the side away from the map
				-- (the other side when that would be off the screen)
				local tw = ns.Num(m.tag:GetStringWidth()) or 40
				m.tag:ClearAllPoints()
				m.inside = bw >= tw + 6
				if m.inside then
					m.tag:SetPoint("CENTER", m, "CENTER", 0, 0)
				else
					local a = mm:PiecePos(e.key) % 360
					local side = (a > 45 and a < 135) and "top" or (a > 225 and a < 315) and "bottom" or (a <= 45 or a >= 315) and "right" or "left"
					local W, H = screen()
					local mx, my = Minimap:GetCenter()
					local cx, cy = ((ns.Num(mx) or 0) + x) * s, ((ns.Num(my) or 0) + y) * s
					if side == "right" and cx + bw / 2 + 4 + tw > W then side = "left"
					elseif side == "left" and cx - bw / 2 - 4 - tw < 0 then side = "right"
					elseif side == "top" and cy + bh / 2 + 16 > H then side = "bottom"
					elseif side == "bottom" and cy - bh / 2 - 16 < 0 then side = "top" end
					if side == "top" then m.tag:SetPoint("BOTTOM", m, "TOP", 0, 3)
					elseif side == "bottom" then m.tag:SetPoint("TOP", m, "BOTTOM", 0, -3)
					elseif side == "right" then m.tag:SetPoint("LEFT", m, "RIGHT", 4, 0)
					else m.tag:SetPoint("RIGHT", m, "LEFT", -4, 0) end
				end
				m:Paint()
				m.used = true
				m:Show()
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
-- The control: Done and Reset positions with one line of help, in the middle of the minimap (it stays there when
-- the minimap moves or changes size, and it is never at a screen edge, where the bars are). Without a minimap of
-- ours (the clean minimap off, or another addon managing it) it is a small panel in the middle of the screen.
-- Dragging the control moves the minimap (or, in the middle of the screen, the control itself).
------------------------------------------------------------------------
local HINT_MAP = "Drag the pieces \194\183 snaps to the edge"
local HINT_BARS = "Drag bars and plugins"
local HELP = "Drag bars to an edge or anywhere, plugins between bars, the minimap, and the pieces around it. "
	.. "A piece sticks to the minimap's edge; hold Shift to put it anywhere. Mouse wheel over the minimap: its size. "
	.. "Done or Escape ends it."

local function makePanel()
	if panel then return end
	local T = ns.Theme
	panel = CreateFrame("Frame", ns.PREFIX .. "UnlockPanel", UIParent)
	panel.eluiTheme = T
	panel:SetSize(172, 78) -- narrower than the map, so the pieces on its left and right edge stay free
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(5)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self)
		if self.onMap then
			local mm = minimapModule()
			if mm then mm:StartDrag() end
		else
			self:StartMoving()
		end
	end)
	panel:SetScript("OnDragStop", function(self)
		if self.onMap then
			local mm = ns.modules.minimap
			if mm then mm:StopDrag() end
		else
			self:StopMovingOrSizing()
		end
	end)
	U.Solid(panel, "BACKGROUND", T.bg[1], T.bg[2], T.bg[3], 0.96):SetAllPoints()
	local top = U.Solid(panel, "ARTWORK", T.accent[1], T.accent[2], T.accent[3], 1)
	top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
	U.Border(panel, 1, T.border[1], T.border[2], T.border[3], 1)
	local hint = ns.UI.Text(panel, T.fontSmall - 1, T.text)
	hint:SetPoint("TOP", 0, -11)
	hint:SetWidth(168)
	hint:SetJustifyH("CENTER")
	hint:SetWordWrap(false)
	panel.hint = hint
	-- the one gold button
	local done = ns.UI.Button(panel, "Done", function() Unlock:Stop() end, 54, "accent")
	done:SetHeight(24)
	done:SetPoint("BOTTOMLEFT", 6, 23)
	local reset = ns.UI.ConfirmButton(panel, "Reset positions", function() Unlock:ResetPositions() end, 100, "plain")
	reset:SetHeight(24)
	reset:SetPoint("BOTTOMRIGHT", -6, 23)
	-- the minimap's size, changed with the mouse wheel over the map
	local size = ns.UI.Text(panel, T.fontSmall - 1, T.muted)
	size:SetPoint("BOTTOM", 0, 7)
	size:SetWidth(168)
	size:SetJustifyH("CENTER")
	size:SetWordWrap(false)
	panel.done, panel.reset, panel.size = done, reset, size
	panel:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(ns.NAME .. ": moving things", 1, 1, 1)
		GameTooltip:AddLine(HELP, 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel:SetScript("OnHide", function() if Unlock.active then Unlock:Stop() end end)
	ns.UI.CloseOnEscape(panel)
	Unlock.panel = panel
end

-- In the middle of the minimap when it is ours to move, else in the middle of the screen.
function Unlock:PlacePanel()
	if not panel then return end
	local mm = minimapModule()
	local onMap = mm ~= nil and mm.unlocked == true
	panel.onMap = onMap
	panel:ClearAllPoints()
	panel:SetScale(1)
	if onMap then
		-- a little smaller on a small map, so the boxes on the map's edge stay clear of it
		local room = (ns.Num(Minimap:GetWidth()) or 140) * mapScale() - 24
		panel:SetScale(math.max(0.8, math.min(1, room / 172)))
		panel:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
		panel.hint:SetText(HINT_MAP)
		panel.size:SetText("Mouse wheel on the map: size " .. mm:SizePercent() .. "%")
		panel.reset:Show()
		panel.done:ClearAllPoints()
		panel.done:SetPoint("BOTTOMLEFT", 6, 23)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		panel.hint:SetText(HINT_BARS)
		panel.size:SetText("Escape ends it too")
		panel.reset:Hide()
		panel.done:ClearAllPoints()
		panel.done:SetPoint("BOTTOM", 0, 23)
	end
end

-- Every piece back to its own place on the edge, the minimap back in the top-right corner at 100%.
function Unlock:ResetPositions()
	local mm = minimapModule()
	if not mm then return end
	mm:ResetPiece()
	if mm:ResetPosition(true) then ns:Print("the minimap is back in the top-right corner at 100%, its pieces in their own places.") end
	self:SyncMovers()
	if ns.Options then ns.Options:Refresh() end
end

------------------------------------------------------------------------
-- Start / stop
------------------------------------------------------------------------
function Unlock:Start()
	if self.active then return true end
	if InCombatLockdown() then ns:Print("you can't move things in combat. Try again when combat ends.") return false end
	self.active = true
	if ns.SecureClick then ns.SecureClick:Uncover() end
	makeGrid()
	makePanel()
	drawGrid()
	grid:Show()
	ns.Host:RefreshAll()
	local mm = ns.modules.minimap
	if mm and mm.running and not mm.stepAside then mm:SetUnlocked(true, true) end
	self:PlacePanel()
	panel:Show()
	self:SyncMovers()
	if ns.Options then ns.Options:Refresh() end
	return true
end

function Unlock:Stop()
	if not self.active then return end
	self.active = false
	if grid then grid:Hide() end
	if panel and panel:IsShown() then panel:Hide() end
	if ghost then ghost:SetScript("OnUpdate", nil); ghost:Hide() end
	for _, m in pairs(self.movers) do
		m.dragging = false
		m:SetScript("OnUpdate", nil)
		m:Hide()
	end
	local mm = ns.modules.minimap
	if mm and mm.unlocked then mm:SetUnlocked(false, true) end
	ns.Host:RefreshAll()
	if ns.Options then ns.Options:Refresh() end
end

function Unlock:Toggle() if self.active then self:Stop() else self:Start() end end

ns.On("PLAYER_REGEN_DISABLED", Unlock, function() if Unlock.active then Unlock:Stop(); ns.SayLockedForCombat() end end)
