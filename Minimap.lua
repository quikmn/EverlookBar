-- Everlook Bar: clean minimap. Move and scale the minimap, square or round, an optional thin border; hide or move the
-- zone text, day/night indicator, clock, coordinates and the tracking/calendar/mail decorations; collect every addon's
-- minimap button into one small drawer (or hide them all).
--
-- Rules: nothing here runs in combat (it waits for combat to end). Blizzard's frames are never dragged directly; a
-- mover of ours is dragged and the frame is re-anchored after. When another addon already manages the minimap
-- (BasicMinimap, SexyMap...) Everlook Bar steps aside for the parts they would fight over and says so once in chat.
local _, ns = ...
local U = ns.Util

local M = ns:NewModule({
	id = "minimap", title = "Clean minimap",
	desc = "Move, scale and tidy the minimap; collect addon buttons into one drawer.",
	defaults = {
		locked = true,
		point = nil,           -- { x, y }: the minimap's centre on screen (UIParent units, from bottom-left)
		scale = 1,
		shape = "round",       -- round | square
		border = true,
		borderColor = { 0, 0, 0, 1 },
		wheelZoom = true,
		elements = {},         -- [key] = "show" | "hide" | "move"
		elementPos = {},       -- [key] = { x, y } from the minimap's centre (for "move")
		buttons = "drawer",    -- drawer | hide | leave
		drawerCorner = "BOTTOMLEFT",
		drawerCols = 6,
		drawerPos = nil,       -- { x, y } centre, once you drag the drawer somewhere
		grab = {},             -- [frameName] = true: always collect
		ignore = {},           -- [frameName] = true: never collect
	},
})

-- The decorations, the frames that may hold them in this client (tried in order) and name patterns to discover the
-- rest (searched among the minimap's children). Default mode: what the owner asked for.
M.ELEMENTS = {
	{ key = "zone", label = "Zone text", default = "hide",
		paths = { "MinimapZoneTextButton", "MinimapCluster.ZoneTextButton", "MinimapBorderTop", "MinimapCluster.BorderTop" }, match = { "ZoneText" } },
	{ key = "daynight", label = "Day/night indicator", default = "hide",
		paths = { "GameTimeFrame", "MinimapCluster.Diel", "Minimap.Diel", "MinimapCluster.DielFrame", "DielFrame", "MinimapDiel" }, match = { "Diel", "DayNight" } },
	{ key = "clock", label = "Clock", default = "hide", paths = { "TimeManagerClockButton" } },
	-- Blizzard's own player coordinates sit in MinimapCluster.MinimapContainer, centred under the minimap
	{ key = "coords", label = "Coordinates", default = "hide",
		paths = { "MinimapCluster.MinimapContainer.PlayerCoords", "MinimapCluster.PlayerCoords", "MinimapCluster.Coordinates", "MinimapCoordinates" },
		match = { "Coord" } },
	{ key = "calendar", label = "Calendar button", default = "hide", paths = { "MinimapCluster.Calendar", "MiniMapCalendar" }, match = { "Calendar" } },
	{ key = "tracking", label = "Tracking", default = "hide",
		paths = { "MiniMapTrackingFrame", "MiniMapTracking", "MiniMapTrackingButton", "MinimapCluster.Tracking", "MinimapCluster.TrackingFrame" } },
	{ key = "mail", label = "Mail icon", default = "hide",
		paths = { "MiniMapMailFrame", "MinimapCluster.IndicatorFrame.MailFrame", "MinimapCluster.MailFrame" } },
	{ key = "zoom", label = "Zoom buttons", default = "hide", paths = { "MinimapZoomIn", "MinimapZoomOut", "Minimap.ZoomIn", "Minimap.ZoomOut" } },
	{ key = "worldmap", label = "World map button", default = "hide", paths = { "MiniMapWorldMapButton", "MinimapToggleButton" } },
	{ key = "compartment", label = "Addon compartment", default = "hide", paths = { "AddonCompartmentFrame", "MinimapCluster.AddonCompartmentFrame" } },
	{ key = "difficulty", label = "Instance difficulty", default = "show",
		paths = { "MiniMapInstanceDifficulty", "MinimapCluster.InstanceDifficulty" } },
	{ key = "ringart", label = "Round border art", default = "hide",
		paths = { "MinimapBorder", "MinimapBackdrop", "MinimapCompassTexture", "MinimapNorthTag" } },
}

-- Addons that also move or reshape the minimap, and addons that also collect its buttons.
M.FRAME_RIVALS = { "BasicMinimap", "SexyMap", "SquareMap", "ElvUI", "pfUI", "OmniMapClassic", "OmniMap", "Chinchilla", "MinimapAlert", "SenMinimap" }
M.BUTTON_RIVALS = { "MinimapButtonButton", "MBB", "HidingBar", "MinimapButtonBag", "SexyMap", "ElvUI" }

local hider = CreateFrame("Frame")
hider:Hide()
M.hider = hider

local holder, borderFrame, roundBorder, drawer, drawerToggle
local taken = {}      -- [object] = { points = { {...} }, key, mode, want } while we hold it
local memo = setmetatable({}, { __mode = "k" }) -- the same record again after a release (hooks are set once)
local held = {}       -- addon buttons we hold: [button] = { parent, points, strata, level, drag }
local heldList = {}   -- ordered
local placing = false -- guard against our own SetPoint calls in hooks
M.stepAside = nil     -- name of the addon that manages the minimap frame
M.buttonRival = nil   -- name of the addon that collects buttons

local function loaded(name)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return f and f(name) and true or false
end

local function resolve(path)
	local t = _G
	for k in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[k]
	end
	if type(t) == "table" and type(t.GetObjectType) == "function" then return t end
end
M.Resolve = resolve

local function mdb() return ns:ModuleDB("minimap") end
function M:Mode(key)
	local m = mdb().elements[key]
	if m then return m end
	for _, e in ipairs(M.ELEMENTS) do if e.key == key then return e.default end end
	return "show"
end

------------------------------------------------------------------------
-- Who else is managing the minimap?
------------------------------------------------------------------------
function M:DetectRivals()
	self.stepAside, self.buttonRival = nil, nil
	for _, n in ipairs(M.FRAME_RIVALS) do
		if loaded(n) then self.stepAside = n break end
	end
	-- Leatrix Plus only touches the minimap with its "Enhance minimap" option on
	if not self.stepAside and loaded("Leatrix_Plus") and type(LeaPlusDB) == "table" and LeaPlusDB.MinimapModder == "On" then
		self.stepAside = "Leatrix Plus (Enhance minimap)"
	end
	for _, n in ipairs(M.BUTTON_RIVALS) do
		if loaded(n) then self.buttonRival = n break end
	end
end

------------------------------------------------------------------------
-- Holding a Blizzard piece: hide it or move it; put it back on "show".
--
-- Blizzard's pieces are never re-parented and none of their methods is replaced. Their own code calls into their
-- parent (the mail and crafting-order icons call IndicatorFrame:Layout() on UPDATE_PENDING_MAIL), so a piece moved
-- under a plain frame of ours breaks Blizzard's event handler. Hiding is a plain Hide() plus a post-hook on Show and
-- SetShown that hides it again; what Blizzard wanted (shown or not) is remembered so "show" can give it back.
-- Moving keeps the parent and only re-anchors the piece to the minimap.
------------------------------------------------------------------------
local function savePoints(obj)
	local pts = {}
	local n = obj.GetNumPoints and ns.Num(obj:GetNumPoints()) or 0
	for i = 1, n do pts[i] = { obj:GetPoint(i) } end
	return pts
end

local function place(obj, key)
	local pos = mdb().elementPos[key] or { 0, 0 }
	placing = true
	pcall(function()
		obj:ClearAllPoints()
		obj:SetPoint("CENTER", Minimap, "CENTER", pos[1] or 0, pos[2] or 0)
	end)
	placing = false
end

-- Hide a piece we hold in "hide" mode (our own Hide calls do not count as Blizzard's wish).
local function suppress(obj)
	placing = true
	pcall(obj.Hide, obj)
	placing = false
end

local function hookPiece(obj, t)
	if t.hooked then return end
	t.hooked = true
	if obj.Show then
		hooksecurefunc(obj, "Show", function(o)
			local h = taken[o]
			if not h then return end
			h.want = true
			if h.mode == "hide" and not placing then suppress(o) end
		end)
	end
	if obj.Hide then
		hooksecurefunc(obj, "Hide", function(o)
			local h = taken[o]
			if h and not placing then h.want = false end
		end)
	end
	if obj.SetShown then
		hooksecurefunc(obj, "SetShown", function(o, shown)
			local h = taken[o]
			if not h or placing then return end
			h.want = shown and true or false
			if shown and h.mode == "hide" then suppress(o) end
		end)
	end
	if obj.SetPoint then
		hooksecurefunc(obj, "SetPoint", function(o)
			local h = taken[o]
			if placing or not h or h.mode ~= "move" then return end
			place(o, h.key)
		end)
	end
end

local function restore(obj)
	local t = taken[obj]
	if not t then return end
	taken[obj] = nil
	placing = true
	pcall(function()
		if t.moved and #t.points > 0 then
			obj:ClearAllPoints()
			for _, p in ipairs(t.points) do obj:SetPoint(unpack(p)) end
		end
		if t.want and obj.Show then obj:Show() end
	end)
	placing = false
end

local function take(obj, key, mode)
	if not obj or obj == Minimap or obj == holder then return end
	if obj.IsProtected and obj:IsProtected() and InCombatLockdown() then return end
	local t = taken[obj]
	if not t then
		t = memo[obj] or {}
		memo[obj] = t
		t.points, t.moved = savePoints(obj), false
		t.want = obj.IsShown and obj:IsShown() and true or false
		taken[obj] = t
		hookPiece(obj, t)
	end
	t.key, t.mode = key, mode
	if mode == "hide" then
		suppress(obj)
	else
		t.moved = true
		if t.want then placing = true; pcall(obj.Show, obj); placing = false end
		place(obj, key)
	end
end
M.Taken = function(obj) return taken[obj] end

-- The frames found for one element (known paths, then name/key discovery among the minimap's children).
function M:Find(e)
	local found, seen = {}, {}
	local function add(o) if o and not seen[o] then seen[o] = true; found[#found + 1] = o end end
	for _, p in ipairs(e.paths or {}) do add(resolve(p)) end
	if e.match then
		for _, parent in ipairs({ MinimapCluster, MinimapCluster and MinimapCluster.MinimapContainer or false, Minimap }) do
			if type(parent) == "table" then
				for k, v in pairs(parent) do
					if type(k) == "string" and type(v) == "table" and type(v.GetObjectType) == "function" and v ~= Minimap then
						for _, pat in ipairs(e.match) do if k:find(pat) then add(v) end end
					end
				end
				for _, child in ipairs({ parent:GetChildren() }) do
					local n = child.GetName and child:GetName()
					if n then for _, pat in ipairs(e.match) do if n:find(pat) and not n:find("^" .. ns.PREFIX) then add(child) end end end
				end
			end
		end
	end
	return found
end

function M:ApplyElements()
	if self.stepAside then return end
	for _, e in ipairs(M.ELEMENTS) do
		local mode = self:Mode(e.key)
		for _, obj in ipairs(self:Find(e)) do
			if mode == "show" then restore(obj) else take(obj, e.key, mode) end
		end
	end
end

-- Report what was found (for /ebar minimap scan).
function M:Report()
	for _, e in ipairs(M.ELEMENTS) do
		local names = {}
		for _, obj in ipairs(self:Find(e)) do names[#names + 1] = (obj.GetName and obj:GetName()) or "(unnamed)" end
		ns:Print(e.label .. " [" .. self:Mode(e.key) .. "]: " .. (#names > 0 and table.concat(names, ", ") or "|cff8d94a3not in this client|r"))
	end
	ns:Print("addon buttons held: " .. #heldList .. (self.buttonRival and (" (|cffffd25a" .. self.buttonRival .. " collects them|r)") or ""))
end

------------------------------------------------------------------------
-- Position, scale, shape, border
------------------------------------------------------------------------
function M:Center()
	local p = mdb().point
	if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then return p[1], p[2] end
	-- first run: where the minimap is now, so nothing jumps
	local x, y = Minimap:GetCenter()
	local s = (ns.Num(Minimap:GetEffectiveScale()) or 1) / (ns.Num(UIParent:GetEffectiveScale()) or 1)
	x, y = ns.Num(x), ns.Num(y)
	if x and y then return x * s, y * s end
	return (ns.Num(UIParent:GetWidth()) or 1920) - 120, (ns.Num(UIParent:GetHeight()) or 1080) - 120
end

function M:ApplyFrame()
	if self.stepAside then return end
	local db = mdb()
	if not holder then
		holder = CreateFrame("Frame", ns.PREFIX .. "MinimapHolder", UIParent)
		holder:SetFrameStrata("LOW")
		M.holder = holder
	end
	local w, h = Minimap:GetSize()
	w, h = ns.Num(w) or 140, ns.Num(h) or 140
	local x, y = self:Center()
	local scale = math.max(0.5, math.min(2.5, tonumber(db.scale) or 1))
	holder:SetScale(scale)
	holder:SetSize(w, h)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	placing = true
	Minimap:SetParent(holder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", holder, "CENTER", 0, 0)
	placing = false
	if not self.minimapHooked then
		self.minimapHooked = true
		hooksecurefunc(Minimap, "SetPoint", function()
			if placing or not M.running or M.stepAside or not holder then return end
			ns.AfterCombat("minimap-anchor", function()
				placing = true
				Minimap:ClearAllPoints()
				Minimap:SetPoint("CENTER", holder, "CENTER", 0, 0)
				placing = false
			end)
		end)
	end
	-- shape
	local square = db.shape == "square"
	pcall(Minimap.SetMaskTexture, Minimap, square and "Interface\\Buttons\\WHITE8X8" or "Textures\\MinimapMask")
	-- addons ask this global for the shape (LibDBIcon and others); define it only if nobody else has
	if GetMinimapShape == nil or M.ownsShapeFunc then
		M.ownsShapeFunc = true
		GetMinimapShape = function() return mdb().shape == "square" and "SQUARE" or "ROUND" end
	end
	-- border
	local c = db.borderColor or { 0, 0, 0, 1 }
	if not borderFrame then
		borderFrame = CreateFrame("Frame", nil, holder)
		borderFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
		borderFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
		borderFrame.edges = U.Border(borderFrame, 1, 0, 0, 0, 1, "OVERLAY")
		roundBorder = holder:CreateTexture(nil, "BACKGROUND")
		roundBorder:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		roundBorder:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1.5, 1.5)
		roundBorder:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1.5, -1.5)
	end
	borderFrame:SetFrameLevel((ns.Num(Minimap:GetFrameLevel()) or 1) + 5)
	borderFrame.edges:SetColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
	borderFrame:SetShown(db.border and square)
	roundBorder:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
	roundBorder:SetShown(db.border and not square)
	-- mouse wheel zoom (only when nobody set a wheel script)
	if db.wheelZoom and not self.wheelSet and not Minimap:GetScript("OnMouseWheel") then
		self.wheelSet = true
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", function(mm, delta)
			if not mdb().wheelZoom then return end
			local z, max = ns.Num(mm:GetZoom()) or 0, ns.Num(mm:GetZoomLevels()) or 5
			z = math.max(0, math.min(max - 1, z + (delta > 0 and 1 or -1)))
			mm:SetZoom(z)
		end)
	end
end

-- Mover dropped: the new centre in UIParent units.
function M:SetCenter(x, y)
	mdb().point = { math.floor(x + 0.5), math.floor(y + 0.5) }
	ns.AfterCombat("minimap-frame", function() M:ApplyFrame() end)
end

------------------------------------------------------------------------
-- Addon buttons: LibDBIcon buttons through the library, loose ones found among the minimap's children.
------------------------------------------------------------------------
local BLIZZARD = { "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^GarrisonLandingPage",
	"^ExpansionLandingPage", "^AddonCompartment", "^Diel", "^MinimapCluster", "^LFG", "^Battlefield", "^HelpOpen" }
local NOT_BUTTONS = { "Pin", "Note", "Questie", "HandyNotes", "Gather", "TomTom", "Arrow", "POI", "Blip", "Node" }

-- Is this child of the minimap an addon's minimap button?
function M.IsAddonButton(obj, name)
	if type(obj) ~= "table" or not obj.GetObjectType then return false end
	name = name or (obj.GetName and obj:GetName())
	if not name or name == "" then return false end
	local db = mdb()
	if db.ignore[name] then return false end
	if db.grab[name] then return true end
	if name:find("^" .. ns.PREFIX) then return false end
	if name:find("^LibDBIcon10_") then return true end
	local kind = obj:GetObjectType()
	if kind ~= "Button" and kind ~= "CheckButton" then return false end
	if obj.IsProtected and obj:IsProtected() then return false end
	for _, p in ipairs(BLIZZARD) do
		if name:find(p) then return false end
	end
	for _, p in ipairs(NOT_BUTTONS) do if name:find(p) then return false end end
	local w, h = obj:GetSize()
	w, h = ns.Num(w), ns.Num(h)
	if not w or not h or w < 14 or h < 14 or w > 52 or h > 52 then return false end
	return true
end

local function relayoutDrawer()
	if not drawer then return end
	local cols = math.max(1, math.min(12, tonumber(mdb().drawerCols) or 6))
	local cell, pad = 32, 6
	local n = 0
	placing = true
	for _, b in ipairs(heldList) do
		local info = held[b]
		if info and not info.hiddenByOwner then
			local col, row = n % cols, math.floor(n / cols)
			pcall(function()
				b:ClearAllPoints()
				b:SetPoint("CENTER", drawer, "TOPLEFT", pad + col * cell + cell / 2, -pad - row * cell - cell / 2)
			end)
			n = n + 1
		end
	end
	placing = false
	local rows = math.max(1, math.ceil(n / cols))
	drawer:SetSize(pad * 2 + math.min(n, cols) * cell + (n == 0 and cell or 0), pad * 2 + rows * cell)
	drawer.empty:SetShown(n == 0)
	if drawerToggle then drawerToggle.count = n end
end
M.RelayoutDrawer = relayoutDrawer

local function makeDrawer()
	if drawer then return end
	local T = ns.Theme
	drawerToggle = CreateFrame("Button", ns.PREFIX .. "MinimapDrawerButton", Minimap)
	drawerToggle:SetSize(18, 18)
	drawerToggle:SetFrameLevel((ns.Num(Minimap:GetFrameLevel()) or 1) + 10)
	local bg = drawerToggle:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetTexture(U.WHITE); bg:SetVertexColor(0, 0, 0, 0.65)
	-- four small squares: a "grid of buttons"
	for i = 0, 3 do
		local sq = drawerToggle:CreateTexture(nil, "ARTWORK")
		sq:SetTexture(U.WHITE)
		sq:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
		sq:SetSize(5, 5)
		sq:SetPoint("TOPLEFT", 3 + (i % 2) * 7, -3 - math.floor(i / 2) * 7)
	end
	drawerToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Minimap buttons", 1, 1, 1)
		GameTooltip:AddLine((self.count or 0) .. " addon buttons. Click to show or hide them.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	drawerToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	drawerToggle:SetScript("OnClick", function()
		GameTooltip:Hide()
		drawer:SetShown(not drawer:IsShown())
	end)

	drawer = CreateFrame("Frame", ns.PREFIX .. "MinimapDrawer", UIParent)
	drawer:SetFrameStrata("DIALOG")
	drawer:SetClampedToScreen(true)
	drawer:EnableMouse(true)
	drawer:Hide()
	local dbg = drawer:CreateTexture(nil, "BACKGROUND")
	dbg:SetAllPoints(); dbg:SetTexture(U.WHITE); dbg:SetVertexColor(T.bg[1], T.bg[2], T.bg[3], 0.96)
	U.Border(drawer, 1, T.border[1], T.border[2], T.border[3], 1)
	drawer.empty = drawer:CreateFontString(nil, "OVERLAY")
	U.SetFont(drawer.empty, 10)
	drawer.empty:SetPoint("CENTER")
	drawer.empty:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
	drawer.empty:SetText("none")
	-- a window like any other: drag it where you like (remembered), Escape closes it through its own key handler
	drawer:SetMovable(true)
	drawer:RegisterForDrag("LeftButton")
	drawer:SetScript("OnDragStart", drawer.StartMoving)
	drawer:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		x, y = ns.Num(x), ns.Num(y)
		if x and y then mdb().drawerPos = { math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	ns.UI.CloseOnEscape(drawer)
	M.drawer, M.drawerToggle = drawer, drawerToggle
end

local CORNERS = {
	TOPLEFT = { "TOPLEFT", 2, -2, "TOPRIGHT", "TOPLEFT", -4, 0 },
	TOPRIGHT = { "TOPRIGHT", -2, -2, "TOPLEFT", "TOPRIGHT", 4, 0 },
	BOTTOMLEFT = { "BOTTOMLEFT", 2, 2, "BOTTOMRIGHT", "BOTTOMLEFT", -4, 0 },
	BOTTOMRIGHT = { "BOTTOMRIGHT", -2, 2, "BOTTOMLEFT", "BOTTOMRIGHT", 4, 0 },
}

local function anchorDrawer()
	local c = CORNERS[mdb().drawerCorner] or CORNERS.BOTTOMLEFT
	drawerToggle:ClearAllPoints()
	drawerToggle:SetPoint(c[1], Minimap, c[1], c[2], c[3])
	drawer:ClearAllPoints()
	local pos = mdb().drawerPos
	if type(pos) == "table" and tonumber(pos[1]) then
		drawer:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
	else
		drawer:SetPoint(c[4], drawerToggle, c[5], c[6], c[7])
	end
end

local function hold(b)
	if held[b] or not b then return end
	if b.IsProtected and b:IsProtected() then return end
	local info = { parent = b:GetParent(), points = savePoints(b) }
	held[b] = info
	heldList[#heldList + 1] = b
	-- dragging it around the minimap would fight the drawer
	if b.RegisterForDrag then pcall(b.RegisterForDrag, b) end
	if not info.hooked then
		info.hooked = true
		hooksecurefunc(b, "SetPoint", function(o)
			if placing or not held[o] then return end
			ns.Soon(relayoutDrawer)
		end)
		b:HookScript("OnShow", function(o) if held[o] then held[o].hiddenByOwner = nil; ns.Soon(relayoutDrawer) end end)
		b:HookScript("OnHide", function(o)
			if held[o] and o:GetParent() == drawer then held[o].hiddenByOwner = true; ns.Soon(relayoutDrawer) end
		end)
	end
	-- a LibDBIcon button its owner hid stays out of the grid
	if b.db and type(b.db) == "table" and b.db.hide then info.hiddenByOwner = true end
	if mdb().buttons == "hide" then
		pcall(b.SetParent, b, hider)
	else
		pcall(b.SetParent, b, drawer)
		pcall(b.SetFrameStrata, b, "DIALOG")
	end
end

function M:CollectButtons()
	if self.buttonRival or mdb().buttons == "leave" then return end
	makeDrawer()
	anchorDrawer()
	drawerToggle:SetShown(mdb().buttons == "drawer")
	local icon = LibStub("LibDBIcon-1.0", true)
	if icon and icon.GetButtonList then
		for _, name in ipairs(icon:GetButtonList()) do
			local b = icon:GetMinimapButton(name)
			if b then hold(b) end
		end
		if not self.iconCallback and icon.RegisterCallback then
			self.iconCallback = true
			icon.RegisterCallback(M, "LibDBIcon_IconCreated", function(_, b)
				ns.AfterCombat("minimap-buttons", function() if M.running and mdb().buttons ~= "leave" then hold(b); relayoutDrawer() end end)
			end)
		end
	end
	for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
		if type(parent) == "table" and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if child ~= drawerToggle and M.IsAddonButton(child) then hold(child) end
			end
		end
	end
	relayoutDrawer()
end

-- Give the buttons back (mode changed to "leave", or a button put on the ignore list).
function M:ReleaseButtons(only)
	placing = true
	for i = #heldList, 1, -1 do
		local b = heldList[i]
		local name = b.GetName and b:GetName()
		if not only or only == name then
			local info = held[b]
			pcall(function()
				b:SetParent(info.parent)
				b:ClearAllPoints()
				for _, p in ipairs(info.points) do b:SetPoint(unpack(p)) end
				if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
			end)
			held[b] = nil
			table.remove(heldList, i)
		end
	end
	placing = false
	relayoutDrawer()
end

function M:Held() return heldList end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function M:ApplyAll()
	ns.AfterCombat("minimap-all", function()
		if not M.running then return end
		M:ApplyFrame()
		M:ApplyElements()
		M:CollectButtons()
	end)
end

function M:Enable()
	if not Minimap then return end
	local function start()
		M:DetectRivals()
		if M.stepAside and not M.toldStepAside then
			M.toldStepAside = true
			ns:Print(M.stepAside .. " is managing the minimap, so " .. ns.NAME .. " leaves the minimap frame alone. "
				.. "To use " .. ns.NAME .. "'s clean minimap instead, disable " .. M.stepAside .. " (Esc > AddOns) and /reload.")
		end
		if M.buttonRival and not M.toldButtons then
			M.toldButtons = true
			ns:Print(M.buttonRival .. " already collects minimap buttons, so " .. ns.NAME .. " leaves them to it.")
		end
		M:ApplyAll()
	end
	if IsLoggedIn and IsLoggedIn() then start() else ns.On("PLAYER_LOGIN", self, start) end
	-- buttons made late (addons that wait for login or load on demand)
	ns.On("PLAYER_ENTERING_WORLD", self, function()
		C_Timer.After(3, function() if M.running then M:ApplyAll() end end)
	end)
	ns.On("ADDON_LOADED", self, function(_, _, name)
		if name == "Blizzard_TimeManager" or name == "Blizzard_Calendar" then
			ns.Soon(M.ApplyAll, M)
		elseif not M.rescanQueued then
			M.rescanQueued = true
			C_Timer.After(2, function() M.rescanQueued = false; if M.running then M:ApplyAll() end end)
		end
	end)
end

function M:Disable()
	for obj in pairs(taken) do restore(obj) end
	self:ReleaseButtons()
	if drawerToggle then drawerToggle:Hide() end
	if drawer then drawer:Hide() end
	ns:Print("the minimap goes back to the game's own place after /reload.")
end

-- The settings that move or reshape the minimap changed.
function M:Redraw()
	if not self.running then return end
	self:ApplyAll()
end
