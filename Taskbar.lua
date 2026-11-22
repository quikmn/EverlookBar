-- EverlookDB Bar: the taskbar. One bar (kind "taskbar") docked to an edge: the Start button, then a button for
-- every open window (icon and title), then the bar's plugins as on any bar. Off until the player switches it on.
-- Click a window's button: bring it to the front, or minimize the one in front, or bring a minimized one back.
-- Right-click: minimize, maximize or restore, snap to halves, quarters and thirds, tile all, close.
-- The game's windows open and close through the game's own buttons (a secure click laid over the taskbar button, as
-- the bar's plugins do: SecureClick.lua), so nothing of the game's runs tainted. In combat the buttons stay where they
-- are (their secure clicks can't move); new windows join at the end, closed ones go when combat ends.
local _, ns = ...
local UI, U = ns.UI, ns.Util
local Tiling = ns.Tiling
local rgba = U.rgba

local TB = { buttons = {} }
ns.Taskbar = TB
-- The taskbar's look: EverlookUI's own (slate and blue), not the bar's gold settings accent.
local T = UI.MakeTheme(nil)
ns.TaskTheme = T

local ICON = 16
local GAP = 2

local function db() return ns.db.taskbar end
local function WM() return ns.WM end

ns.TASKBAR_DEFAULTS = {
	enabled = false,
	edge = "bottom",
	size = 32,             -- thickness of a top or bottom taskbar
	sideWidth = 180,       -- width of a left or right one
	labels = true,         -- window titles on the buttons (else icons only)
	snap = true,           -- drag one of our windows to a screen edge to snap it
	others = true,         -- list other addons' windows
	blizzard = true,       -- list the game's windows
	gap = 4,               -- pixels around snapped and tiled windows
	pinned = { "game:character", "game:spellbook", "game:quests", "game:map", "game:bags", "app:EverlookDB Bar" },
	recent = {},
	ignore = {},           -- [frame name] = true: never listed
}

------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------
function TB:Bar()
	for i, bar in ipairs(ns.db.bars) do
		if bar.kind == "taskbar" then return i, bar end
	end
end

local function vertical(edge) return edge == "left" or edge == "right" end

function TB:IsOn() return db().enabled and true or false end

-- Switch it on (the first time: a new bar on the chosen edge) or off (the bar hides; minimized windows come back).
function TB:SetEnabled(on)
	if not on and InCombatLockdown() and WM().running then
		-- minimized windows come back when it goes off, and some of them may have to wait for combat's end
		ns.AfterCombat("taskbaroff", function() TB:SetEnabled(false) end)
		ns:Print("the taskbar goes off when combat ends.")
		return
	end
	db().enabled = on and true or false
	local i, bar = self:Bar()
	if on then
		if not bar then
			local e = db().edge
			i = ns.Bars:AddBar({ name = "Taskbar", kind = "taskbar", edge = e, lanes = 1,
				laneSize = vertical(e) and db().sideWidth or db().size, hLane = db().size, vLane = db().sideWidth,
				bg = { 0.047, 0.052, 0.063, 0.94 }, spacing = 10, padding = 4, strata = "HIGH" })
			bar = ns.db.bars[i]
		end
		bar.shown = true
		WM():Start()
	else
		if bar then bar.shown = false end
		WM():Stop()
		if self.strip then self.strip:Hide() end
		if ns.StartMenu then ns.StartMenu:Hide() end
	end
	ns.Host:RefreshAll()
	if ns.Options then ns.Options:Refresh() end
end

function TB:SetEdge(e)
	if e ~= "top" and e ~= "bottom" and e ~= "left" and e ~= "right" then return false end
	db().edge = e
	local i = self:Bar()
	if i then ns.Bars:SetEdge(i, e) end
	return true
end

function TB:SetSize(n)
	local i, bar = self:Bar()
	if vertical(db().edge) then db().sideWidth = n else db().size = n end
	if bar then bar.laneSize = n end
	ns.Host:RefreshAll()
end
function TB:Size() return vertical(db().edge) and db().sideWidth or db().size end

-- A bar was deleted: was it the taskbar?
function TB:BarsChanged()
	if db().enabled and not self:Bar() then
		db().enabled = false
		WM():Stop()
		if self.strip then self.strip:Hide() end
	end
end

------------------------------------------------------------------------
-- The strip: Start button and window buttons, laid where Bars.lua leaves room (L.TaskStripLength)
------------------------------------------------------------------------
local function hideTip(b) if GameTooltip:IsOwned(b) then GameTooltip:Hide() end end

-- Tooltips sit on the screen side of the taskbar.
local function anchorTip(b)
	GameTooltip:SetOwner(b, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	local e = TB.edge or "bottom"
	if e == "top" then GameTooltip:SetPoint("TOP", b, "BOTTOM", 0, -4)
	elseif e == "left" then GameTooltip:SetPoint("LEFT", b, "RIGHT", 4, 0)
	elseif e == "right" then GameTooltip:SetPoint("RIGHT", b, "LEFT", -4, 0)
	else GameTooltip:SetPoint("BOTTOM", b, "TOP", 0, 4) end
end

local function setIcon(tex, ic)
	if not ic then tex:Hide() return end
	if ic.tex then
		tex:SetTexture(ic.tex)
		local c = ic.coords or { 0, 1, 0, 1 }
		tex:SetTexCoord(c[1], c[2], c[3], c[4])
		tex:SetVertexColor(1, 1, 1)
		tex:Show()
		return
	end
	if UI.SetIcon(tex, ic.icon) then
		if UI.IsIconName(ic.icon) then tex:SetVertexColor(rgba(T.text)) else tex:SetVertexColor(1, 1, 1) end
	end
end

-- The little line on a button's screen-edge side: long and blue for the window in front, short for the others.
local function placeIndicator(b, edge, active)
	local ind = b.ind
	ind:ClearAllPoints()
	local long = active and 0.6 or 0.25
	local w, h = (b:GetWidth() or 0), (b:GetHeight() or 0)
	if edge == "top" then ind:SetPoint("TOP", 0, -1); ind:SetSize(math.max(6, w * long), 2)
	elseif edge == "left" then ind:SetPoint("LEFT", 1, 0); ind:SetSize(2, math.max(6, h * long))
	elseif edge == "right" then ind:SetPoint("RIGHT", -1, 0); ind:SetSize(2, math.max(6, h * long))
	else ind:SetPoint("BOTTOM", 0, 1); ind:SetSize(math.max(6, w * long), 2) end
	if active then ind:SetVertexColor(rgba(T.accent)) else ind:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.8) end
end

local function makeButton(parent, name)
	local b = CreateFrame("Button", name, parent)
	b.eluiTheme = T
	b:RegisterForClicks("AnyUp")
	b.bg = U.Round(b, 4, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetVertexColor(rgba(T.surfaceHi))
	b.bg:Hide()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON, ICON)
	b.text = UI.Text(b, T.font, T.text)
	b.text:SetWordWrap(false)
	b.text:SetJustifyH("LEFT")
	b.ind = U.Solid(b, "OVERLAY", rgba(T.accent))
	b.ind:Hide()
	return b
end

-- Secure clicks for the game's windows: the taskbar button's left click "clicks" the game's own button (the micro
-- button), which opens or closes the window from secure code. A window that is open but behind another gets no
-- secure click: the plain click raises it.
local function secureFor(b)
	return function()
		local rec = b.winRec
		if not rec or rec.kind ~= "blizzard" then return nil end
		local toggle = WM():Toggle(rec)
		if not toggle then return nil end
		if not rec.minimized and not rec.gone and WM():Active() ~= rec then return nil end
		return { type = "click", clickbutton = toggle }
	end
end

local function winEnter(b)
	b.bg:Show()
	local rec = b.winRec
	if rec and rec.kind == "blizzard" and ns.SecureClick:Owner() ~= b then ns.SecureClick:Cover(b) end
	anchorTip(b)
	if rec then
		GameTooltip:AddLine(WM():Title(rec), 1, 1, 1)
		local hint
		if rec.kind == "blizzard" then
			hint = WM():Toggle(rec) and "Click: bring to front, or close it. Right-click: more." or "Click: bring to front. Right-click: more."
		else
			hint = rec.minimized and "Click: bring it back. Right-click: more." or "Click: bring to front, or minimize. Right-click: more."
		end
		GameTooltip:AddLine(hint, 0.7, 0.72, 0.76, true)
	end
	GameTooltip:Show()
end

local function winLeave(b)
	if not b.active then b.bg:Hide() end
	hideTip(b)
end

local function winClick(b, mouse)
	hideTip(b)
	local rec = b.winRec
	if not rec then return end
	if mouse == "RightButton" then TB:WindowMenu(b, rec) return end
	if rec.kind == "blizzard" and (rec.minimized or rec.gone) then
		-- no secure click here (in combat, or the game has no button for it): it opens with its own key
		if UIErrorsFrame then UIErrorsFrame:AddMessage(ns.NAME .. ": open it with its key or button (combat).", 1, 0.3, 0.3) end
		return
	end
	WM():Activate(rec)
	TB:Refresh()
end

local function windowButton(i)
	local b = TB.buttons[i]
	if b then return b end
	b = makeButton(TB.strip, ns.PREFIX .. "TaskButton" .. i)
	b.rec = { name = "Taskbar", obj = { ebarSecure = secureFor(b) } } -- SecureClick reads b.rec.obj.ebarSecure
	b.ebarPreSecure = function(self)
		local rec = self.winRec
		if rec and not rec.minimized and not rec.gone and rec.frame:IsShown() then rec.minimizing = true end
	end
	b.ebarAfterSecure = function() C_Timer.After(0.1, function() WM():Scan() TB:Refresh() end) end
	b:SetScript("OnEnter", winEnter)
	b:SetScript("OnLeave", winLeave)
	b:SetScript("OnClick", winClick)
	TB.buttons[i] = b
	return b
end

function TB:MakeStrip()
	if self.strip then return self.strip end
	local s = CreateFrame("Frame", ns.PREFIX .. "TaskStrip", UIParent)
	self.strip = s
	s:EnableMouse(true)
	if s.SetMouseMotionEnabled then s:SetMouseMotionEnabled(false) end
	s:SetScript("OnMouseUp", function(_, mouse) if mouse == "RightButton" then TB:StripMenu(s) end end)
	local st = makeButton(s, ns.PREFIX .. "StartButton")
	self.start = st
	st.text:SetText("Start")
	UI.SetIcon(st.icon, "grid")
	st.icon:SetVertexColor(rgba(T.accent))
	st:SetScript("OnEnter", function(b)
		b.bg:Show()
		anchorTip(b)
		GameTooltip:AddLine("Start", 1, 1, 1)
		GameTooltip:AddLine("Every window you can open, with a search. Right-click: tile, minimize all, settings.", 0.7, 0.72, 0.76, true)
		GameTooltip:Show()
	end)
	st:SetScript("OnLeave", function(b) if not (ns.StartMenu and ns.StartMenu:IsShown()) then b.bg:Hide() end hideTip(b) end)
	st:SetScript("OnClick", function(b, mouse)
		hideTip(b)
		if mouse == "RightButton" then TB:StripMenu(b) else ns.StartMenu:Toggle() end
	end)
	self.more = makeButton(s, ns.PREFIX .. "TaskMore")
	self.more.text:SetText("")
	UI.SetIcon(self.more.icon, "chevron")
	self.more:SetScript("OnEnter", function(b) b.bg:Show() end)
	self.more:SetScript("OnLeave", function(b) b.bg:Hide() end)
	self.more:SetScript("OnClick", function(b) TB:MoreMenu(b) end)
	WM().onChange = function() TB:Refresh() end
	return s
end

-- Bars.lua laid the taskbar out: the strip takes rectangle q of bar frame f. In combat the strip stays where it is.
function TB:PlaceStrip(f, q, isVertical, bar)
	if not db().enabled or bar.shown == false or not q then
		if self.strip then self.strip:Hide() end
		return
	end
	local s = self:MakeStrip()
	if InCombatLockdown() and self.placed then return end
	if s:GetParent() ~= f then s:SetParent(f) end
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", f, "TOPLEFT", q.x, -q.y)
	s:SetSize(math.max(1, q.w), math.max(1, q.h))
	s:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
	s:Show()
	self.placed = true
	self.vertical, self.edge = isVertical, bar.edge
	self.len = isVertical and q.h or q.w
	self.thick = isVertical and q.w or q.h
	self:Refresh()
end

local function styleButton(b, rec, w, h, labels)
	b:SetSize(w, h)
	setIcon(b.icon, rec and WM():Icon(rec) or nil)
	b.icon:ClearAllPoints()
	local showText = labels and w >= 60
	if showText then
		b.icon:SetPoint("LEFT", 8, 0)
		b.text:ClearAllPoints()
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
		b.text:SetPoint("RIGHT", -6, 0)
		b.text:SetText(rec and WM():Title(rec) or "")
	else
		b.icon:SetPoint("CENTER")
	end
	b.text:SetShown(showText)
end

-- Draw every button again: positions (not in combat, except new ones at the end), titles, icons, which is in front.
function TB:Refresh()
	local s = self.strip
	if not s or not s:IsShown() then return end
	local wm = WM()
	local recs = wm.recs
	local combat = InCombatLockdown()
	local vert, thick, len = self.vertical, self.thick or 30, self.len or 0
	local labels = db().labels ~= false
	local itemH = vert and 28 or thick
	-- Start: a square on a top or bottom bar, a full-width row with its name on a side bar
	local st = self.start
	local startLen = vert and itemH or thick
	if not combat or not self.laidOut then
		st:ClearAllPoints()
		st:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
		if vert then
			st:SetSize(thick, itemH)
			st.icon:ClearAllPoints(); st.icon:SetPoint("LEFT", 8, 0)
			st.text:ClearAllPoints(); st.text:SetPoint("LEFT", st.icon, "RIGHT", 6, 0); st.text:Show()
		else
			st:SetSize(thick, thick)
			st.icon:ClearAllPoints(); st.icon:SetPoint("CENTER"); st.text:Hide()
		end
	end
	st.bg:SetShown(ns.StartMenu and ns.StartMenu:IsShown() or false)
	local room = math.max(0, len - startLen - 6)
	local size, shown, more
	if combat and self.laidOut then
		size = self.lastSize
		shown = vert and math.floor((room + GAP) / (size + GAP)) or math.floor((room + GAP) / (size + GAP))
		shown = math.min(#recs, shown)
		more = shown < #recs
	else
		size, shown, more = Tiling.Strip(#recs, room, { vertical = vert, itemH = itemH, gap = GAP,
			maxW = labels and 180 or thick + 8, minW = labels and 96 or thick, moreW = thick })
		self.lastSize = size
	end
	local active = wm:Active()
	local pos = startLen + 6
	for i = 1, math.max(#recs, #self.buttons) do
		local b = (i <= shown) and windowButton(i) or self.buttons[i]
		local rec = i <= shown and recs[i] or nil
		if b then
			if rec then
				local was = b.winRec
				b.winRec = rec
				ns.SecureClick:Track(b, rec.kind == "blizzard")
				if not combat or not b:IsShown() or was ~= rec then
					b:ClearAllPoints()
					if vert then
						b:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -pos)
						styleButton(b, rec, thick, size, labels)
					else
						b:SetPoint("TOPLEFT", s, "TOPLEFT", pos, 0)
						styleButton(b, rec, size, thick, labels)
					end
				end
				b.active = rec == active
				b.bg:SetShown(b.active or b:IsMouseOver())
				if b.active then b.bg:SetVertexColor(rgba(T.accentDim)) else b.bg:SetVertexColor(rgba(T.surfaceHi)) end
				b.text:SetTextColor(rgba((rec.minimized or rec.gone) and T.muted or T.text))
				b.icon:SetAlpha((rec.minimized or rec.gone) and 0.55 or 1)
				placeIndicator(b, self.edge, b.active)
				b.ind:Show()
				b:Show()
			elseif not combat then
				ns.SecureClick:Track(b, false)
				b.winRec = nil
				b:Hide()
			end
		end
		pos = pos + size + GAP
	end
	-- the rest: one "more" button listing them
	local m = self.more
	if more and shown < #recs then
		m:ClearAllPoints()
		local at = startLen + 6 + shown * (size + GAP)
		if vert then m:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -at); m:SetSize(thick, itemH)
		else m:SetPoint("TOPLEFT", s, "TOPLEFT", at, 0); m:SetSize(thick, thick) end
		m.icon:ClearAllPoints(); m.icon:SetPoint("CENTER")
		self.overflow = shown
		m:Show()
	else
		self.overflow = nil
		m:Hide()
	end
	self.laidOut = true
end

------------------------------------------------------------------------
-- Menus
------------------------------------------------------------------------
local function popup(owner, items, onPick, width)
	UI.OpenPopup(owner, items, nil, function(v) ns.SafeCall(TB, onPick, v) end, { atCursor = true, width = width or 210 })
end

function TB:WindowMenu(b, rec)
	local wm = WM()
	local items = { { title = true, text = wm:Title(rec) } }
	if rec.kind == "blizzard" then
		items[#items + 1] = { title = true, text = wm:Toggle(rec) and "Click its button to open or close it" or "Close it with its own X" }
		if wm:Toggle(rec) and not wm:CanMove(rec) then
			items[#items + 1] = { title = true, text = "The game keeps it in its place" }
		end
	else
		if rec.minimized then items[#items + 1] = { value = "restore", text = "Restore" }
		else items[#items + 1] = { value = "min", text = "Minimize" } end
		if wm:CanMove(rec) then
			items[#items + 1] = { value = "max", text = rec.snap == "max" and "Restore size" or "Maximize" }
			if rec.snap and rec.snap ~= "max" then items[#items + 1] = { value = "unsnap", text = "Restore size" } end
			items[#items + 1] = { title = true, text = "Snap" }
			for _, z in ipairs(Tiling.ZONES) do
				if z.id ~= "max" then items[#items + 1] = { value = "snap:" .. z.id, text = z.text } end
			end
		end
	end
	items[#items + 1] = { value = "tile", text = "Tile all windows" }
	if wm:CanClose(rec) then items[#items + 1] = { value = "close", text = "Close" } end
	if rec.kind ~= "ours" and ns.Str(rec.frame:GetName()) then items[#items + 1] = { value = "ignore", text = "Don't list this window" } end
	popup(b, items, function(v)
		if v == "restore" then wm:Restore(rec)
		elseif v == "min" then wm:Minimize(rec)
		elseif v == "max" then wm:ToggleMaximize(rec)
		elseif v == "unsnap" then wm:Unsnap(rec)
		elseif v == "tile" then TB:TileAll()
		elseif v == "close" then wm:Close(rec)
		elseif v == "ignore" then wm:Ignore(rec)
		elseif type(v) == "string" and v:find("^snap:") then wm:Snap(rec, v:sub(6)) end
		TB:Refresh()
	end)
end

function TB:StripMenu(owner)
	popup(owner, {
		{ title = true, text = "Taskbar" },
		{ value = "tile", text = "Tile all windows" },
		{ value = "minall", text = "Minimize all" },
		{ value = "restoreall", text = "Restore all" },
		{ value = "settings", text = "Taskbar settings..." },
	}, function(v)
		if v == "tile" then TB:TileAll()
		elseif v == "minall" then WM():MinimizeAll()
		elseif v == "restoreall" then WM():RestoreAll()
		elseif v == "settings" then ns.Options:Open("taskbar") end
		TB:Refresh()
	end)
end

function TB:MoreMenu(owner)
	local items = { { title = true, text = "More windows" } }
	local recs = WM().recs
	for i = (self.overflow or 0) + 1, #recs do
		items[#items + 1] = { value = i, text = WM():Title(recs[i]) .. (recs[i].minimized and " (minimized)" or "") }
	end
	popup(owner, items, function(i)
		local rec = WM().recs[i]
		if rec then WM():Activate(rec) end
		TB:Refresh()
	end, 240)
end

function TB:TileAll()
	local n = WM():TileAll()
	if n == 0 then ns:Print("no windows to tile (the game's own windows keep their place).") end
	return n
end

------------------------------------------------------------------------
-- Boot: after the saved settings are read
------------------------------------------------------------------------
function TB:Init()
	ns.db.taskbar = U.FillDefaults(ns.db.taskbar or {}, ns.TASKBAR_DEFAULTS)
	local _, bar = self:Bar()
	if db().enabled and bar then
		bar.shown = true
		WM():Start()
	elseif bar then
		bar.shown = false
	end
	-- combat starts: the Start menu closes (its secure clicks can't follow it in combat)
	ns.On("PLAYER_REGEN_DISABLED", self, function()
		if ns.StartMenu and ns.StartMenu:IsShown() then ns.StartMenu:Hide() end
	end)
	ns.On("PLAYER_REGEN_ENABLED", self, function() C_Timer.After(0, function() TB:Refresh() end) end)
end

-- The key bindings (Bindings.xml) and the public table.
BINDING_HEADER_EVERLOOKBAR = ns.NAME
BINDING_NAME_EVERLOOKBAR_START = "Open the Start menu"
BINDING_NAME_EVERLOOKBAR_TILE = "Tile all windows"
local public = _G[ns.GLOBAL]
function public.ToggleStart() if ns.db then ns.StartMenu:Toggle() end end
function public.TileAll() if ns.db and db().enabled then TB:TileAll() end end
