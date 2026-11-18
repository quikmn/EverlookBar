-- Everlook Bar: bar frames and plugin buttons. Frames are made once and reused; text is set only when it changed;
-- widths are "sticky" (Layout.StickyWidth) so a number ticking from 59 to 60 never shakes the whole bar.
local _, ns = ...
local Bars = { frames = {}, buttons = {}, ready = false }
ns.Bars = Bars
local L = ns.Layout
local U = ns.Util

local ICON = 16
local GAP = 4 -- between icon, widget and text
local LABEL_COLOR = "|cff9aa3b5"
local issecret = ns.IsSecret

------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------
local function newBar(i)
	local f = CreateFrame("Frame", ns.PREFIX .. "Bar" .. i, UIParent)
	f.index = i
	f:SetClampedToScreen(true)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetTexture(U.WHITE)
	f.line = f:CreateTexture(nil, "BORDER")
	f.line:SetTexture(U.WHITE)
	f.buttons = {}
	-- unlock mode: the bar itself is dragged (its plugins sit on top and are dragged on their own)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	-- right-click the bar (between plugins) opens the settings; it takes clicks, not mouse-over
	f:EnableMouse(true)
	if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(false) end
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not (ns.Unlock and ns.Unlock.active) and ns.Options then ns.Options:Open() end
	end)
	f:SetScript("OnDragStart", function(self) if ns.Unlock and ns.Unlock.active then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if not (ns.Unlock and ns.Unlock.active) then return end
		local x, y = ns.Num(self:GetLeft()) or 0, ns.Num(self:GetBottom()) or 0
		local w, h = ns.Num(self:GetWidth()) or 0, ns.Num(self:GetHeight()) or 0
		if ns.db.snap then x, y = L.Snap(x, ns.db.grid), L.Snap(y, ns.db.grid) end
		local W, H = ns.Num(UIParent:GetWidth()) or 1920, ns.Num(UIParent:GetHeight()) or 1080
		Bars:SetEdge(self.index, L.EdgeForDrop(x, y, w, h, W, H, 24), x, y)
	end)
	return f
end

-- Unlock-mode look: an accent outline and the bar's name.
local function showUnlocked(f, bar, on)
	if on and not f.unlockEdges then
		local a = ns.ACCENT
		f.unlockEdges = U.Border(f, 1, a[1], a[2], a[3], 0.9, "OVERLAY")
		f.unlockLabel = f:CreateFontString(nil, "OVERLAY")
		U.SetFont(f.unlockLabel, 10, "OUTLINE")
		f.unlockLabel:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 2)
		f.unlockLabel:SetTextColor(a[1], a[2], a[3])
	end
	if f.unlockEdges then
		f.unlockEdges:SetShown(on)
		f.unlockLabel:SetShown(on)
		if on then f.unlockLabel:SetText((bar.name or "Bar") .. " (" .. bar.edge .. ") - drag to move") end
	end
	if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(on) end
end

-- Moved in unlock mode (or set from settings): a new edge, or free at x, y. Side bars and top/bottom bars keep
-- their own thickness, so a bar moved from the top to the left gets a sensible column width.
function Bars:SetEdge(i, edge, x, y)
	local bar = ns.db.bars[i]
	if not bar then return end
	local wasVertical = L.IsVertical(bar)
	if wasVertical then bar.vLane = bar.laneSize else bar.hLane = bar.laneSize end
	if edge == "free" then
		bar.orient = wasVertical and "vertical" or "horizontal"
		bar.x, bar.y = math.floor((x or bar.x or 0) + 0.5), math.floor((y or bar.y or 0) + 0.5)
	end
	bar.edge = edge
	local isVertical = L.IsVertical(bar)
	if isVertical ~= wasVertical then
		if isVertical then bar.laneSize = bar.vLane or 150 else bar.laneSize = bar.hLane or 22 end
	end
	ns.Host:RefreshAll()
	if ns.Options then ns.Options:Refresh() end
end

function Bars:Init()
	for i in ipairs(ns.db.bars) do self.frames[i] = self.frames[i] or newBar(i) end
	ns.On("DISPLAY_SIZE_CHANGED", self, function() ns.Soon(Bars.LayoutAll, Bars) end)
	ns.On("UI_SCALE_CHANGED", self, function() ns.Soon(Bars.LayoutAll, Bars) end)
	ns.On("PLAYER_ENTERING_WORLD", self, function() ns.Soon(Bars.LayoutAll, Bars) end)
	self.ready = true
end

function Bars:AddBar(spec)
	local bar = U.FillDefaults(spec or {}, ns.BAR_DEFAULTS)
	table.insert(ns.db.bars, bar)
	local i = #ns.db.bars
	self.frames[i] = self.frames[i] or newBar(i)
	self:LayoutAll()
	return i
end

function Bars:RemoveBar(i)
	if not ns.db.bars[i] or #ns.db.bars <= 1 then return false end
	table.remove(ns.db.bars, i)
	ns.Host:BarRemoved(i)
	-- the last frame is now spare: hide it (frames are never destroyed; it is reused by the next new bar)
	local last = self.frames[#ns.db.bars + 1]
	if last then last:Hide() end
	ns.Host:RefreshAll()
	return true
end

-- Font settings of a bar applied to one font string.
local function applyFont(fs, bar)
	local ok = fs:SetFont(ns.FontPath(bar.font), bar.fontSize or 12, bar.outline or "")
	if not ok then fs:SetFontObject(GameFontHighlightSmall) end
end

local function styleBar(f, bar, rect)
	local c = bar.bg or ns.BAR_DEFAULTS.bg
	f.bg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0.6)
	f:SetFrameStrata(bar.strata or "MEDIUM")
	f.line:ClearAllPoints()
	if bar.line then
		local a = ns.ACCENT
		f.line:SetVertexColor(a[1], a[2], a[3], 0.55)
		local e = bar.edge
		if e == "top" then f.line:SetPoint("BOTTOMLEFT"); f.line:SetPoint("BOTTOMRIGHT"); f.line:SetHeight(1)
		elseif e == "bottom" then f.line:SetPoint("TOPLEFT"); f.line:SetPoint("TOPRIGHT"); f.line:SetHeight(1)
		elseif e == "left" then f.line:SetPoint("TOPRIGHT"); f.line:SetPoint("BOTTOMRIGHT"); f.line:SetWidth(1)
		elseif e == "right" then f.line:SetPoint("TOPLEFT"); f.line:SetPoint("BOTTOMLEFT"); f.line:SetWidth(1)
		else f.line:SetPoint("BOTTOMLEFT"); f.line:SetPoint("BOTTOMRIGHT"); f.line:SetHeight(1) end
		f.line:Show()
	else
		f.line:Hide()
	end
end

-- Height of one plugin in a side (vertical) bar.
local function itemHeight(bar)
	return math.max(ICON, (bar.fontSize or 12)) + 8
end

-- Position every bar and every button.
function Bars:LayoutAll()
	if not self.ready then return end
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	W, H = ns.Num(W) or 1920, ns.Num(H) or 1080
	local rects = L.BarRects(ns.db.bars, W, H)
	self.rects = rects
	-- buttons per bar
	local perBar = {}
	for name, rec in pairs(ns.Host.plugins) do
		local p = ns.db.placement[name]
		if ns.Host:Wanted(name) then
			local b = rec.button or Bars:MakeButton(rec)
			perBar[p.bar] = perBar[p.bar] or {}
			table.insert(perBar[p.bar], rec)
		elseif rec.button then
			rec.button:Hide()
		end
	end
	for i, bar in ipairs(ns.db.bars) do
		local f = self.frames[i] or newBar(i)
		self.frames[i] = f
		local r = rects[i]
		f.vertical = r.vertical
		f.rect = r
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r.x, r.y)
		f:SetSize(r.w, r.h)
		styleBar(f, bar, r)
		showUnlocked(f, bar, ns.Unlock and ns.Unlock.active or false)
		f:SetShown(bar.shown ~= false)
		local recs = perBar[i] or {}
		local items = {}
		for _, rec in ipairs(recs) do
			local p = ns.db.placement[rec.key]
			local b = rec.button
			if b:GetParent() ~= f then b:SetParent(f) end
			if b.styleBar ~= bar or b.styleSize ~= bar.fontSize or b.styleFont ~= bar.font or b.styleOutline ~= bar.outline
				or b.styleVertical ~= r.vertical or b.styleLane ~= bar.laneSize then
				Bars:StyleButton(rec, bar, r.vertical)
			end
			items[#items + 1] = { key = rec.key, rec = rec, w = b.wantW or 40, lane = p.lane or 1, group = p.group, order = p.order or 0 }
		end
		local pos = L.PlaceItems(bar, r.w, r.h, items, itemHeight(bar))
		for _, it in ipairs(items) do
			local q = pos[it]
			local b = it.rec.button
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", f, "TOPLEFT", q.x, -q.y)
			b:SetSize(q.w, q.h)
			b.pos = q
			b:Show()
		end
		f.items = items
	end
	for i = #ns.db.bars + 1, #self.frames do self.frames[i]:Hide() end
	if ns.Unlock and ns.Unlock.active then ns.Unlock:SyncMovers() end
end

------------------------------------------------------------------------
-- Tooltips: placed away from the bar's edge.
------------------------------------------------------------------------
function Bars:AnchorTooltip(tip, owner)
	local f = owner:GetParent()
	local bar = f and f.index and ns.db.bars[f.index]
	tip:ClearAllPoints()
	local e = bar and bar.edge or "top"
	if e == "free" then
		local _, y = owner:GetCenter()
		y = ns.Num(y) or 0
		e = y > (ns.Num(UIParent:GetHeight()) or 1080) / 2 and "top" or "bottom"
		if bar and bar.orient == "vertical" then
			local x = ns.Num((owner:GetCenter())) or 0
			e = x < (ns.Num(UIParent:GetWidth()) or 1920) / 2 and "left" or "right"
		end
	end
	if e == "top" then tip:SetPoint("TOP", owner, "BOTTOM", 0, -4)
	elseif e == "bottom" then tip:SetPoint("BOTTOM", owner, "TOP", 0, 4)
	elseif e == "left" then tip:SetPoint("LEFT", owner, "RIGHT", 4, 0)
	else tip:SetPoint("RIGHT", owner, "LEFT", -4, 0) end
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
local function errorLine(rec)
	if rec.errors and rec.errors > 0 then
		return "|cffff6060Error (" .. rec.errors .. "):|r " .. U.Escape(rec.lastError or "?")
	end
end

local function onEnter(self)
	local rec = self.rec
	self.hl:Show()
	if ns.Unlock and ns.Unlock.active then
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		Bars:AnchorTooltip(GameTooltip, self)
		GameTooltip:AddLine(ns.Host:Title(rec.key), 1, 1, 1)
		GameTooltip:AddLine("Drag to another place or bar.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
		return
	end
	local obj = rec.obj
	local tipFrame = obj.tooltip
	if type(tipFrame) == "table" and tipFrame.Show then
		self.shownTip = tipFrame
		ns.SafeCall(rec, function()
			if tipFrame.SetOwner then tipFrame:SetOwner(self, "ANCHOR_NONE") end
			Bars:AnchorTooltip(tipFrame, self)
			tipFrame:Show()
		end)
		return
	end
	if type(obj.OnEnter) == "function" then
		ns.SafeCall(rec, obj.OnEnter, self)
		return
	end
	local show = obj.OnTooltipShow
	local err = errorLine(rec)
	if type(show) == "function" or err then
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		Bars:AnchorTooltip(GameTooltip, self)
		if type(show) == "function" then
			ns.SafeCall(rec, show, GameTooltip)
		else
			GameTooltip:AddLine(ns.Host:Title(rec.key), 1, 1, 1)
		end
		err = errorLine(rec) -- the call above may have failed just now
		if err then GameTooltip:AddLine(err, 1, 1, 1, true) end
		GameTooltip:Show()
		self.shownTip = GameTooltip
	end
end

local function onLeave(self)
	local rec = self.rec
	self.hl:Hide()
	if self.shownTip then
		local t = self.shownTip
		self.shownTip = nil
		if t == GameTooltip then GameTooltip:Hide() else ns.SafeCall(rec, t.Hide, t) end
	elseif ns.Unlock and ns.Unlock.active then
		GameTooltip:Hide()
	end
	if type(rec.obj.OnLeave) == "function" then ns.SafeCall(rec, rec.obj.OnLeave, self) end
end

local function onClick(self, mouse)
	if ns.Unlock and ns.Unlock.active then return end
	local rec = self.rec
	local fn = rec.obj.OnClick
	if type(fn) == "function" then
		-- the tooltip would sit on top of a menu the click opens
		if self.shownTip == GameTooltip then GameTooltip:Hide(); self.shownTip = nil end
		ns.SafeCall(rec, fn, self, mouse)
	elseif mouse == "RightButton" and ns.Options then
		-- a plugin with no clicks of its own: right-click opens the settings, like the bar itself
		if self.shownTip == GameTooltip then GameTooltip:Hide(); self.shownTip = nil end
		ns.Options:Open()
	end
end

function Bars:MakeButton(rec)
	local name = ns.PREFIX .. "Plugin" .. (rec.key:gsub("[^%w]", ""))
	if _G[name] then name = nil end
	local b = CreateFrame("Button", name, UIParent)
	b.rec = rec
	rec.button = b
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnEnter", onEnter)
	b:SetScript("OnLeave", onLeave)
	b:SetScript("OnClick", onClick)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self) if ns.Unlock and ns.Unlock.active then ns.Unlock:StartPluginDrag(self.rec) end end)
	b:SetScript("OnDragStop", function(self) if ns.Unlock and ns.Unlock.active then ns.Unlock:StopPluginDrag(self.rec) end end)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetTexture(U.WHITE)
	b.hl:SetVertexColor(1, 1, 1, 0.07)
	b.hl:Hide()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON, ICON)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetWordWrap(false)
	b.text:SetJustifyH("LEFT")
	b.text:SetTextColor(0.92, 0.93, 0.95, 1)
	b.err = b:CreateTexture(nil, "OVERLAY")
	b.err:SetSize(5, 5)
	b.err:SetPoint("TOPRIGHT", -1, -2)
	b.err:SetTexture(U.WHITE)
	b.err:SetVertexColor(1, 0.25, 0.25, 1)
	b.err:Hide()
	b:Hide()
	local w = ns.API and ns.API.widgets[rec.key]
	if w then Bars:AttachWidget(rec, w) end
	if rec.errors and rec.errors > 0 then b.err:Show() end
	return b
end

function Bars:ShowError(rec)
	if rec.button then rec.button.err:Show() end
end

-- A custom widget from EverlookBar.API.RegisterWidget, made once per button.
function Bars:AttachWidget(rec, spec)
	local b = rec.button
	if not b or b.widget then return end
	local wf = CreateFrame("Frame", nil, b)
	b.widget = wf
	b.widgetSpec = spec
	wf:SetPoint("LEFT")
	wf:SetSize(tonumber(spec.width) or 60, 10)
	if type(spec.create) == "function" then ns.SafeCall(rec, spec.create, wf, rec.obj, rec.key) end
end

function Bars:StyleButton(rec, bar, vertical)
	local b = rec.button
	applyFont(b.text, bar)
	b.styleBar, b.styleSize, b.styleFont, b.styleOutline, b.styleVertical, b.styleLane =
		bar, bar.fontSize, bar.font, bar.outline, vertical, bar.laneSize
	b.lastText = nil -- force SetText and a new width
	b.textW = nil
	self:UpdateButton(rec)
end

local function widgetWidth(b, rec)
	local spec = b.widgetSpec
	if not spec then return 0 end
	local w = spec.width
	if type(w) == "function" then
		local ok, v = ns.SafeCall(rec, w, rec.obj, rec.key)
		w = ok and v or 0
	end
	return math.max(0, ns.Num(w) or 0)
end

-- Text a plugin shows: label, text (or value + suffix). May return a secret as is (shown, never compared).
function Bars:Compose(rec, cfg)
	local obj = rec.obj
	local text
	if cfg.text ~= false then
		local t = obj.text
		if t ~= nil and issecret(t) then return t, true end
		text = ns.Str(t)
		if not text then
			local v, s = obj.value, obj.suffix
			if v ~= nil and issecret(v) then return v, true end
			v = ns.Str(v)
			if v then text = v .. (ns.Str(s) and (" " .. ns.Str(s)) or "") end
		end
	end
	local label
	if cfg.label then
		label = ns.Str(obj.label) or rec.key
		if issecret(obj.label) then label = rec.key end
	end
	if label and text and text ~= "" then return LABEL_COLOR .. label .. "|r " .. text, false end
	if label then return label, false end
	return text or "", false
end

-- Redraw one button. Returns true when its width changed (the bar must be laid out again).
function Bars:UpdateButton(rec)
	local b = rec.button
	if not b then return false end
	local f = b:GetParent()
	local bar = f and f.index and ns.db.bars[f.index]
	local vertical = f and f.vertical
	local cfg = ns.Host:Config(rec.key)
	local obj = rec.obj

	-- icon
	local icon = obj.icon
	local hasIcon = cfg.icon ~= false and icon ~= nil and not issecret(icon) and (type(icon) == "string" or type(icon) == "number")
	if hasIcon then
		if b.lastIcon ~= icon then b.icon:SetTexture(icon); b.lastIcon = icon end
		local c = obj.iconCoords
		if type(c) == "table" and not issecret(c) then
			b.icon:SetTexCoord(ns.Num(c[1]) or 0, ns.Num(c[2]) or 1, ns.Num(c[3]) or 0, ns.Num(c[4]) or 1)
		else
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local r, g, bl = ns.Num(obj.iconR), ns.Num(obj.iconG), ns.Num(obj.iconB)
		b.icon:SetVertexColor(r or 1, g or 1, bl or 1)
	end
	b.icon:SetShown(hasIcon)

	-- custom widget
	local ww = 0
	if b.widget then
		ww = widgetWidth(b, rec)
		b.widget:SetShown(ww > 0)
		if ww > 0 and b.widgetSpec.update then ns.SafeCall(rec, b.widgetSpec.update, b.widget, obj, rec.key) end
	end

	-- text
	local text, secret = self:Compose(rec, cfg)
	local textW
	if secret then
		b.text:SetText(text) -- allowed with a secret; never compared or measured
		b.lastText = nil
		textW = b.textW or 60
	elseif b.lastText ~= text then
		b.lastText = text
		b.text:SetText(text)
		local w = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()
		textW = math.ceil(ns.Num(w) or 0)
		b.textW = textW
	else
		textW = b.textW or 0
	end
	local hasText = text ~= nil and (secret or text ~= "")
	b.text:SetShown(hasText)

	-- arrange icon, widget, text from the left
	local x = 0
	b.icon:ClearAllPoints()
	if hasIcon then b.icon:SetPoint("LEFT", b, "LEFT", 0, 0); x = ICON + GAP end
	if b.widget and ww > 0 then
		b.widget:ClearAllPoints()
		b.widget:SetPoint("LEFT", b, "LEFT", x, 0)
		local h = bar and math.max(4, math.min(tonumber(bar.laneSize) or 22, 40) - 10) or 10
		b.widget:SetSize(ww, h)
		x = x + ww + GAP
	end
	b.text:ClearAllPoints()
	b.text:SetPoint("LEFT", b, "LEFT", x, 0)
	if vertical and bar then
		b.text:SetPoint("RIGHT", b, "RIGHT", -2, 0) -- side bars: cut long text at the bar's width
	end
	local want = x + (hasText and textW or 0)
	if not hasText and x > 0 then want = x - GAP end
	if want < 1 then want = 1 end
	local old = b.wantW
	b.wantW = L.StickyWidth(old, want, 10)
	return old ~= b.wantW
end
