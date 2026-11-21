-- EverlookDB Bar: drag and drop on the settings window's Plugins page. Drag a plugin row (by its grip, or anywhere on
-- the row but its buttons) to another place in its group, to another group or bar, or down to "Not on a bar"; drag
-- from there onto a bar to add it. A ghost of the row follows the cursor, a thin blue line shows where it lands and
-- the group under the cursor lights up; the page scrolls near its top and bottom edges. Right-click or Escape
-- cancels. The drop goes through Host:Place / Host:Remove, the same calls unlock mode and the buttons use.
-- Plain frames of our own only, so it works in combat too.
local _, ns = ...
local U = ns.Util
local L = ns.Layout

local D = { zones = {} }
ns.PluginDrag = D

local GAP = 2       -- UI.List puts rows 2 px apart
local EDGE = 36     -- auto-scroll starts this close to the page's top or bottom edge
local SPEED = 14    -- most pixels scrolled per frame

-- The line, the ghost and the highlight are in the Lattice blue (the shared look's accent), not the addon's gold:
-- gold is kept for the one primary button.
local function blue() return ns.UI.Theme.accent end

------------------------------------------------------------------------
-- Zones: one per group list on the page, and "Not on a bar"
------------------------------------------------------------------------
-- Forget the zones of a page that is being built again.
function D:Reset()
	if self.drag then self:Cancel() end
	wipe(self.zones)
end

-- zone = { list = UI.List frame, title = frame above it (its heading), items = fn() -> names shown,
--          bar = bar index (nil for "Not on a bar"), group = "left" | "center" | "right", rowH = row height }
function D:AddZone(zone)
	self.zones[#self.zones + 1] = zone
	zone.list.dragZone = zone
	local list = zone.list
	local refresh = list.Refresh
	function list:Refresh(...)
		refresh(self, ...)
		for _, r in ipairs(self.rows) do D:DecorateRow(r, zone) end
	end
	list:Refresh()
	return zone
end

-- The scroll frame of the page a list sits on (its ScrollBy comes from EverlookUI's scroll bar).
local function pageScroll(frame)
	local p = frame:GetParent()
	while p do
		if rawget(p, "ScrollBy") then return p end
		p = p:GetParent()
	end
end

-- A list listed in search results right now (EverlookUI borrows a page's controls there): no dragging.
local function borrowed(list)
	local e = list.stackEntry
	return e and e.borrowed and true or false
end

------------------------------------------------------------------------
-- Rows: a grip on the left, and dragging
------------------------------------------------------------------------
function D:DecorateRow(r, zone)
	if r.dragGrip then return end
	local T = ns.UI.ThemeOf(r)
	-- two columns of three dots: the row can be picked up
	local grip = CreateFrame("Frame", nil, r)
	grip:SetSize(8, 14)
	grip:SetPoint("LEFT", 5, 0)
	grip.dots = {}
	for col = 0, 1 do
		for row = 0, 2 do
			local d = grip:CreateTexture(nil, "ARTWORK")
			d:SetTexture(U.WHITE)
			d:SetSize(2, 2)
			d:SetPoint("TOPLEFT", col * 4 + 1, -(row * 5 + 2))
			d:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.55)
			grip.dots[#grip.dots + 1] = d
		end
	end
	r.dragGrip = grip
	-- the icon and the name move right to make room for the grip
	if r.icon then
		r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 18, 0)
		r.title:ClearAllPoints(); r.title:SetPoint("LEFT", 44, 0)
	else
		r.title:ClearAllPoints(); r.title:SetPoint("LEFT", 18, 0)
	end
	local function lit(on)
		for _, d in ipairs(grip.dots) do
			if on then d:SetVertexColor(T.text[1], T.text[2], T.text[3], 0.9)
			else d:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.55) end
		end
	end
	r:HookScript("OnEnter", function() lit(true) end)
	r:HookScript("OnLeave", function() lit(false) end)
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function(self)
		if self.item ~= nil then D:Start(self.item, self:GetParent().dragZone or zone, self) end
	end)
	r:SetScript("OnDragStop", function() D:Drop() end)
end

------------------------------------------------------------------------
-- Drag pieces: ghost, insertion line, group highlight (made on the first drag)
------------------------------------------------------------------------
local ghost, line, glow

local function makePieces()
	if ghost then return end
	local T = ns.Theme
	local B = blue()
	ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(300, 28)
	U.Solid(ghost, "BACKGROUND", T.surfaceHi[1], T.surfaceHi[2], T.surfaceHi[3], 0.96):SetAllPoints()
	U.Border(ghost, 1, B[1], B[2], B[3], 1)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(18, 18)
	ghost.icon:SetPoint("LEFT", 18, 0)
	ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ghost.text = ns.UI.Text(ghost, T.font, T.text)
	ghost.text:SetWordWrap(false)
	ghost:Hide()

	line = CreateFrame("Frame", nil, UIParent)
	line:SetHeight(2)
	U.Solid(line, "OVERLAY", B[1], B[2], B[3], 1):SetAllPoints()
	-- a small knob at the line's left end, like a text cursor lying down
	local knob = U.Solid(line, "OVERLAY", B[1], B[2], B[3], 1)
	knob:SetSize(6, 6)
	knob:SetPoint("LEFT", 0, 0)
	line:Hide()

	glow = CreateFrame("Frame", nil, UIParent)
	U.Solid(glow, "BACKGROUND", B[1], B[2], B[3], 0.07):SetAllPoints()
	U.Border(glow, 1, B[1], B[2], B[3], 0.7)
	glow:Hide()
end

local function iconOf(name)
	local rec = ns.Host.plugins[name]
	local i = rec and rec.obj.icon
	if i ~= nil and not ns.IsSecret(i) and (type(i) == "string" or type(i) == "number") then return i end
end

------------------------------------------------------------------------
-- Start, follow the cursor, drop, cancel
------------------------------------------------------------------------
local function cursor(scale)
	local x, y = GetCursorPosition()
	scale = scale or 1
	return (ns.Num(x) or 0) / scale, (ns.Num(y) or 0) / scale
end

-- Escape cancels a drag through the window's own Escape handler (EverlookUI calls frame.eluiEscape first).
local function hookWindow(win)
	if not win or win.eluiDragHooked then return end
	win.eluiDragHooked = true
	local prev = win.eluiEscape
	win.eluiEscape = function(self)
		if D.drag then D:Cancel() return true end
		if prev then return prev(self) end
	end
	win:HookScript("OnHide", function() if D.drag then D:Cancel() end end)
end

function D:Start(name, zone, row)
	if self.drag or not zone or borrowed(zone.list) then return end
	local scroll = pageScroll(zone.list)
	if not scroll then return end
	makePieces()
	local scale = ns.Num(row:GetEffectiveScale()) or 1
	local cx, cy = cursor(scale)
	local left, top = ns.Num(row:GetLeft()) or cx, ns.Num(row:GetTop()) or cy
	self.drag = { name = name, from = zone, row = row, scroll = scroll, scale = scale,
		grabX = cx - left, grabY = top - cy }
	hookWindow(ns.app and ns.app.window)
	ns.UI.ClosePopup()
	GameTooltip:Hide()
	row:SetAlpha(0.35)
	-- the ghost: the row lifted off the page, the same size, following the cursor
	local uiScale = ns.Num(UIParent:GetEffectiveScale()) or 1
	ghost:SetScale(scale / uiScale)
	ghost:SetSize(ns.Num(row:GetWidth()) or 300, zone.rowH or 28)
	local icon = iconOf(name)
	ghost.icon:SetShown(icon ~= nil)
	if icon then ghost.icon:SetTexture(icon) end
	ghost.text:ClearAllPoints()
	ghost.text:SetPoint("LEFT", 44, 0)
	ghost.text:SetPoint("RIGHT", -8, 0)
	ghost.text:SetText(ns.Host:Title(name))
	ghost:SetScript("OnUpdate", function() D:Update() end)
	ghost:Show()
	self:Update()
end

-- Where the cursor would drop: zone and slot, or nil off the page.
function D:TargetAt(x, y)
	local s = (self.drag and self.drag.scroll) or (self.zones[1] and pageScroll(self.zones[1].list))
	if not s then return end
	local l, r = ns.Num(s:GetLeft()), ns.Num(s:GetRight())
	local top, bottom = ns.Num(s:GetTop()), ns.Num(s:GetBottom())
	if not (l and r and top and bottom) then return end
	-- off the page sideways (the scroll bar counts as the page), or well above or below it: nowhere
	if x < l - 8 or x > r + 24 or y > top + 60 or y < bottom - 60 then return end
	y = math.max(bottom + 1, math.min(top - 1, y))
	local bands, shown = {}, {}
	for _, z in ipairs(self.zones) do
		if z.list:IsVisible() then
			local zt = ns.Num((z.title or z.list):GetTop())
			local zb = ns.Num(z.list:GetBottom())
			if zt and zb then
				bands[#bands + 1] = { top = -zt, bottom = -zb }
				shown[#shown + 1] = z
			end
		end
	end
	local i = L.NearestZone(bands, -y)
	local zone = i and shown[i]
	if not zone then return end
	local listTop = ns.Num(zone.list:GetTop()) or y
	local items = zone.items()
	local slot = L.InsertSlot(L.RowCentres(#items, zone.rowH, GAP), listTop - y)
	return zone, slot
end

function D:SetTarget(zone, slot)
	local d = self.drag
	if not d then return end
	d.zone, d.slot = zone, slot
	if not zone then line:Hide(); glow:Hide() return end
	-- both sit on the page itself, above its rows, so the page's scrolling clips them like the rows
	local page = zone.list:GetParent()
	if glow:GetParent() ~= page then
		glow:SetParent(page); line:SetParent(page)
		glow:SetFrameStrata(page:GetFrameStrata()); line:SetFrameStrata(page:GetFrameStrata())
		glow:SetFrameLevel((page:GetFrameLevel() or 1) + 40); line:SetFrameLevel((page:GetFrameLevel() or 1) + 41)
	end
	-- the group lights up: its heading and its rows
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", zone.title or zone.list, "TOPLEFT", 0, 4)
	glow:SetPoint("BOTTOMRIGHT", zone.list, "BOTTOMRIGHT", 0, -4)
	glow:Show()
	-- the line sits in the gap above row `slot`; "Not on a bar" keeps its own order, so it has no line
	if zone.bar and slot then
		local off = (slot - 1) * (zone.rowH + GAP) - GAP / 2
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", zone.list, "TOPLEFT", 0, -off + 1)
		line:SetPoint("TOPRIGHT", zone.list, "TOPRIGHT", 0, -off + 1)
		line:Show()
	else
		line:Hide()
	end
end

function D:Update()
	local d = self.drag
	if not d then return end
	if IsMouseButtonDown and IsMouseButtonDown("RightButton") then self:Cancel() return end
	if not d.scroll:IsVisible() then self:Cancel() return end -- the page was left (search, another page)
	local x, y = cursor(d.scale)
	local gs = ns.Num(ghost:GetEffectiveScale()) or 1
	local gx, gy = cursor(gs)
	ghost:ClearAllPoints()
	ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (gx - d.grabX * d.scale / gs), (gy + d.grabY * d.scale / gs))
	-- near the top or bottom edge the page scrolls, faster the closer the cursor gets
	local top, bottom = ns.Num(d.scroll:GetTop()), ns.Num(d.scroll:GetBottom())
	local l, r = ns.Num(d.scroll:GetLeft()), ns.Num(d.scroll:GetRight())
	if top and bottom and l and r and x >= l - 8 and x <= r + 24 then
		local step = 0
		if y > top - EDGE and y < top + 60 then step = -math.max(2, math.floor(SPEED * math.min(1, (y - (top - EDGE)) / EDGE)))
		elseif y < bottom + EDGE and y > bottom - 60 then step = math.max(2, math.floor(SPEED * math.min(1, ((bottom + EDGE) - y) / EDGE))) end
		if step ~= 0 then d.scroll:ScrollBy(step) end
	end
	self:SetTarget(self:TargetAt(x, y))
	-- the button came up somewhere OnDragStop did not hear about
	if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self:Drop() end
end

local function finish()
	local d = D.drag
	D.drag = nil
	if ghost then ghost:SetScript("OnUpdate", nil); ghost:Hide() end
	if line then line:Hide() end
	if glow then glow:Hide() end
	if d and d.row then d.row:SetAlpha(1) end
	return d
end

function D:Cancel() finish() end

-- What a drop of `name` on zone/slot does. Returns "remove", or "place", bar, lane, group, index, or nil (nothing).
function D:Resolve(name, zone, slot)
	if not zone then return end
	local p = ns.db.placement[name]
	if not zone.bar then
		if p then return "remove" end
		return
	end
	local b = ns.db.bars[zone.bar]
	if not b then return end
	local items = zone.items()
	local lanes, skip = {}, nil
	for i, n in ipairs(items) do
		local q = ns.db.placement[n]
		lanes[i] = q and q.lane or 1
		if n == name then skip = i end
	end
	local nLanes = math.max(1, math.floor(tonumber(b.lanes) or 1))
	local fallback = (p and p.bar == zone.bar and p.lane) or 1
	local lane, index = L.ListDrop(lanes, slot or (#items + 1), skip, math.min(nLanes, fallback))
	return "place", zone.bar, math.min(nLanes, lane), zone.group, index
end

function D:Drop()
	local d = finish()
	if not d then return end
	local what, bar, lane, group, index = self:Resolve(d.name, d.zone, d.slot)
	if what == "remove" then
		ns.Host:Remove(d.name)
	elseif what == "place" then
		ns.Host:Place(d.name, bar, lane, group, index)
	end
	return what
end
