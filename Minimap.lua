-- EverlookDB Bar: clean minimap. Move and scale the minimap, square or round, an optional thin border; switch the
-- pieces around it on or off (zone name, tracking, mail, calendar, clock, coordinates...) and put each on the
-- minimap's edge; collect every addon's minimap button into one small drawer (or hide them all).
--
-- Rules: the minimap frame itself is never touched in combat (it waits for combat to end); a piece is switched at
-- once unless the game protects it in combat, then it waits too. Blizzard's frames are never dragged directly; a
-- mover of ours is dragged and the frame is re-anchored. When another addon already manages the minimap
-- (BasicMinimap, SexyMap...) EverlookDB Bar steps aside for the parts they would fight over and says so once in chat.
local _, ns = ...
local U = ns.Util

local M = ns:NewModule({
	id = "minimap", title = "Clean minimap",
	desc = "Move, scale and tidy the minimap; collect addon buttons into one drawer.",
	defaults = {
		snapEdges = false,     -- off by default: a dropped minimap stays exactly where it is put (on: snaps within 12 px)
		zoneLabel = "off",     -- our own zone line: off | subzone | zone | both
		zoneLabelPos = "top",  -- top | bottom
		point = nil,           -- { x, y }: the minimap's centre on screen (UIParent units, from bottom-left)
		scale = 1,
		shape = "square",      -- round | square (square for new players; a saved shape stays)
		border = true,
		borderSize = 2,        -- px (1-8)
		borderColor = { 0, 0, 0, 1 },
		wheelZoom = true,
		pieceOn = {},          -- [key] = true | false: a piece around the minimap switched on or off (nil = its default)
		piecePos = {},         -- [key] = { a = degrees, d = px from the edge }: where a moved piece sits (nil = default)
		-- before the pieces had switches: elements[key] = "show" | "hide" | "move", elementPos[key] = { x, y }
		-- (see MigratePieces)
		buttons = "drawer",    -- drawer | hide | leave
		drawerCorner = "BOTTOMLEFT",
		drawerCols = 6,
		grab = {},             -- [frameName] = true: always collect
		ignore = {},           -- [frameName] = true: never collect
	},
})

-- The pieces around the minimap. Each is switched on or off; one that is on sits on the minimap's edge at an angle
-- (degrees, 0 = right, 90 = top) and a distance from the edge (d, in the minimap's own pixels; 0 = centred on the
-- edge). That is how a place is saved too, so the same saved place works on a round and on a square minimap and at
-- any size.
--   parts: the frames of the piece. Each part lists the names the frame may have in this client (the first that
--          exists is used) and its offset from the piece's place.
--   also:  more frames that are hidden with the piece but never placed (old clients' border art).
--   match: name patterns to find the frame among the minimap's children when no listed name exists.
--   fixed: on/off only, it has no place of its own. all: every listed name, not only the first.
--   keep:  shown all the time while on (the game shows the zoom buttons only under the mouse).
--   default: on for a new player? icon: the line icon when the piece has no art to preview.
-- WoW Forever's minimap is the retail-style cluster: tracking, zone name, calendar and mail sit in a header strip
-- above the map (children of MinimapCluster, anchored to it), the zoom buttons and the round frame art on the map.
M.ELEMENTS = {
	{ key = "zone", label = "Zone name", short = "Zone", icon = "map", default = false, a = 90, d = 10,
		desc = "The game's bar with the name of the zone.",
		keywords = { "zone", "text", "name", "location", "header" },
		parts = { { "MinimapCluster.ZoneTextButton", "MinimapZoneTextButton" } },
		also = { "MinimapBorderTop", "MinimapCluster.BorderTop" }, match = { "ZoneText" } },
	{ key = "tracking", label = "Tracking button", short = "Tracking", icon = "search", default = false, a = 135, d = 0,
		desc = "Mailbox, trainers, Find Herbs... Off: the Tracking plugin on a bar does the same.",
		keywords = { "tracking", "track", "mailbox", "trainer", "herbs", "minerals", "find" },
		parts = { { "MinimapCluster.Tracking", "MiniMapTrackingFrame", "MiniMapTracking", "MiniMapTrackingButton", "MinimapCluster.TrackingFrame" } } },
	{ key = "mail", label = "Mail icon", short = "Mail", icon = "note", default = false, a = 160, d = 0,
		desc = "Lights up when you have new mail.",
		keywords = { "mail", "letter", "post", "crafting", "order" },
		parts = { { "MinimapCluster.IndicatorFrame", "MiniMapMailFrame", "MinimapCluster.MailFrame" } } },
	{ key = "calendar", label = "Calendar button", short = "Calendar", icon = "page", default = false, a = 20, d = 0,
		desc = "Opens the calendar.",
		keywords = { "calendar", "date", "events", "invite" },
		parts = { { "GameTimeFrame", "MinimapCluster.Calendar", "MiniMapCalendar" } }, match = { "Calendar" } },
	{ key = "daynight", label = "Day and night dial", short = "Day/night", icon = "globe", default = false, a = 225, d = 0,
		desc = "The small sun or moon.",
		keywords = { "day", "night", "sun", "moon", "time", "dial" },
		parts = { { "MinimapCluster.DielFrame", "MinimapCluster.Diel", "Minimap.Diel", "DielFrame", "MinimapDiel" } },
		match = { "Diel", "DayNight" } },
	{ key = "clock", label = "Clock", short = "Clock", icon = "clock", default = false, a = 270, d = 2,
		desc = "The game's clock.",
		keywords = { "clock", "time", "hour" },
		parts = { { "TimeManagerClockButton" } } },
	-- Blizzard's own player coordinates sit in MinimapCluster.MinimapContainer, centred under the minimap
	{ key = "coords", label = "Coordinates", short = "Coords", icon = "target", default = false, a = 270, d = 22,
		desc = "Where you stand, as two numbers.",
		keywords = { "coordinates", "coords", "position", "xy" },
		parts = { { "MinimapCluster.MinimapContainer.PlayerCoords", "MinimapCluster.PlayerCoords", "MinimapCluster.Coordinates", "MinimapCoordinates" } },
		match = { "Coord" } },
	{ key = "zoom", label = "Zoom buttons", short = "Zoom", icon = "plus", default = false, a = 315, d = 10, keep = true,
		desc = "Plus and minus. Off: the mouse wheel still zooms.",
		keywords = { "zoom", "plus", "minus", "in", "out" },
		parts = { { "Minimap.ZoomIn", "MinimapZoomIn", dx = 8, dy = 8 }, { "Minimap.ZoomOut", "MinimapZoomOut", dx = -8, dy = -8 } } },
	{ key = "compartment", label = "Addon menu button", short = "Addons", icon = "puzzle", default = false, a = 340, d = 0,
		desc = "The small numbered button that lists addons.",
		keywords = { "addon", "addons", "compartment", "menu", "list" },
		parts = { { "AddonCompartmentFrame", "MinimapCluster.AddonCompartmentFrame" } } },
	{ key = "worldmap", label = "World map button", short = "World map", icon = "map", default = false, a = 200, d = 0,
		desc = "Opens the world map.",
		keywords = { "world", "map", "button" },
		parts = { { "MiniMapWorldMapButton", "MinimapToggleButton" } } },
	{ key = "difficulty", label = "Dungeon difficulty flag", short = "Difficulty", icon = "flag", default = true, a = 180, d = 0,
		desc = "Shows in a dungeon or raid.",
		keywords = { "instance", "dungeon", "raid", "difficulty", "heroic", "flag" },
		parts = { { "MiniMapInstanceDifficulty", "MinimapCluster.InstanceDifficulty" } } },
	{ key = "ringart", label = "The game's round frame", short = "Frame art", icon = "dot", default = false, fixed = true,
		desc = "The game's own ring around a round minimap.",
		keywords = { "border", "ring", "art", "frame", "compass", "round" },
		parts = { { "MinimapBorder" }, { "MinimapBackdrop" }, { "MinimapCompassTexture" }, { "MinimapNorthTag" } } },
}
M.ELEMENT = {}
for _, e in ipairs(M.ELEMENTS) do M.ELEMENT[e.key] = e end

-- Addons that also move or reshape the minimap, and addons that also collect its buttons.
M.FRAME_RIVALS = { "BasicMinimap", "SexyMap", "SquareMap", "ElvUI", "pfUI", "OmniMapClassic", "OmniMap", "Chinchilla", "MinimapAlert", "SenMinimap" }
M.BUTTON_RIVALS = { "MinimapButtonButton", "MBB", "HidingBar", "MinimapButtonBag", "SexyMap", "ElvUI" }

local hider = CreateFrame("Frame")
hider:Hide()
M.hider = hider

local holder, borderFrame, drawer, drawerToggle
local taken = {}      -- [object] = { points = { {...} }, key, mode, want } while we hold it
local memo = setmetatable({}, { __mode = "k" }) -- the same record again after a release (hooks are set once)
local held = {}       -- addon buttons we hold: [button] = { parent, points, strata, level, drag }
local heldList = {}   -- ordered
local hooked = setmetatable({}, { __mode = "k" }) -- addon buttons we have hooked (once each)
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
local function screenSize() return ns.Num(UIParent:GetWidth()) or 1920, ns.Num(UIParent:GetHeight()) or 1080 end
------------------------------------------------------------------------
-- Where a piece sits: pure maths, the same call for a round and a square minimap.
-- A place is an angle (degrees, 0 = right, 90 = top) and d, the distance from the minimap's edge (0 = centred on
-- it). `half` is half the minimap's width, border included. On a square minimap the edge is the square's outline,
-- so the same angle and distance stay on the edge when the shape changes.
------------------------------------------------------------------------
function M.PiecePoint(a, d, shape, half)
	local r = math.rad(a)
	local c, s = math.cos(r), math.sin(r)
	local reach = half + d
	if shape == "square" then reach = reach / math.max(math.abs(c), math.abs(s)) end
	return reach * c, reach * s
end

function M.PieceFromXY(x, y, shape, half)
	if x == 0 and y == 0 then return 90, -half end
	local a = math.deg(math.atan2(y, x)) % 360
	local reach = shape == "square" and math.max(math.abs(x), math.abs(y)) or math.sqrt(x * x + y * y)
	return a, reach - half
end

local function angleGap(a, b)
	local g = math.abs(a - b) % 360
	return g > 180 and 360 - g or g
end

-- Snap points. Square: the corners first (they pull from further away), then the middle of each side. Round: every
-- 45 degrees. Between them a piece slides freely along the edge.
function M.SnapAngle(a, shape)
	a = a % 360
	if shape == "square" then
		for c = 45, 315, 90 do if angleGap(a, c) <= 10 then return c end end
		for c = 0, 270, 90 do if angleGap(a, c) <= 5 then return c end end
		return a
	end
	for c = 0, 315, 45 do if angleGap(a, c) <= 5 then return c end end
	return a
end

-- Half the minimap's width with its border, in the minimap's own units.
function M:Half()
	local w = Minimap and ns.Num(Minimap:GetWidth()) or 140
	return w / 2 + self:BorderPad()
end

function M:PieceOn(key)
	local v = mdb().pieceOn[key]
	if v ~= nil then return v and true or false end
	local e = M.ELEMENT[key]
	return e and e.default and true or false
end

-- On, and something to show for it: the game's ring art is for a round minimap only.
function M:PieceShown(key)
	if not self:PieceOn(key) then return false end
	if key == "ringart" and mdb().shape == "square" then return false end
	return true
end

-- "show" or "hide" (the Tracking plugin and older code ask this way).
function M:Mode(key) return self:PieceOn(key) and "show" or "hide" end

-- The saved place of a piece, else its default one: angle, distance from the edge.
function M:PiecePos(key)
	local e = M.ELEMENT[key]
	local p = mdb().piecePos[key]
	if type(p) == "table" and tonumber(p.a) and tonumber(p.d) then return p.a, p.d end
	return e and e.a or 0, e and e.d or 0
end

function M:IsMoved(key) return mdb().piecePos[key] ~= nil end

-- Where a piece's centre is from the minimap's centre, in the minimap's own units.
function M:PieceXY(key)
	local a, d = self:PiecePos(key)
	return M.PiecePoint(a, d, mdb().shape, self:Half())
end

-- A drag in edit mode: the cursor is at x, y from the minimap's centre (the minimap's own units). The piece sticks
-- to the edge at its own distance and snaps to the shape's snap points; free = true puts it exactly there.
function M:DragPieceTo(key, x, y, free)
	local e = M.ELEMENT[key]
	if not e or e.fixed then return end
	local half, shape = self:Half(), mdb().shape
	local a, d = M.PieceFromXY(x, y, shape, half)
	if not free then a, d = M.SnapAngle(a, shape), e.d or 0 end
	d = math.max(-half, math.min(400, d))
	mdb().piecePos[key] = { a = math.floor(a * 10 + 0.5) / 10, d = math.floor(d + 0.5) }
	self:ApplyElements()
end

function M:SetPieceOn(key, on)
	if not M.ELEMENT[key] then return end
	mdb().pieceOn[key] = on and true or false
	self:ApplyElements()
	if ns.Unlock then ns.Unlock:SyncMovers() end
end

-- One piece (or all of them) back to its default place.
function M:ResetPiece(key)
	if key then mdb().piecePos[key] = nil else wipe(mdb().piecePos) end
	self:ApplyElements()
	if ns.Unlock then ns.Unlock:SyncMovers() end
end

-- Settings from before the pieces had on/off switches: elements[key] = "show" | "hide" | "move" and
-- elementPos[key] = { x, y } from the minimap's centre. "show" and "move" become on, a moved piece keeps its place
-- (as an angle and a distance, so it also works on the other shape). Nothing is dropped.
function M.MigratePieces(db, half)
	db.pieceOn = type(db.pieceOn) == "table" and db.pieceOn or {}
	db.piecePos = type(db.piecePos) == "table" and db.piecePos or {}
	local old, oldPos = db.elements, db.elementPos
	if type(old) == "table" then
		for key, mode in pairs(old) do
			if M.ELEMENT[key] and db.pieceOn[key] == nil then
				db.pieceOn[key] = mode ~= "hide"
				local p = type(oldPos) == "table" and oldPos[key]
				local x, y = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
				-- a piece set to "move" and never dragged sat in the middle of the map: it gets its default place
				if mode == "move" and x and y and (x ~= 0 or y ~= 0) and not M.ELEMENT[key].fixed then
					local a, d = M.PieceFromXY(x, y, db.shape, half or 70)
					db.piecePos[key] = { a = math.floor(a * 10 + 0.5) / 10, d = math.floor(d + 0.5) }
				end
			end
		end
		-- the calendar button (GameTimeFrame) used to follow the day/night setting
		if old.daynight ~= nil and old.calendar == nil and db.pieceOn.calendar == nil then
			db.pieceOn.calendar = old.daynight ~= "hide"
		end
	end
	db.elements, db.elementPos = nil, nil
end

-- Core calls this for every module once its saved settings are filled in.
function M:Migrate(db)
	M.MigratePieces(db, Minimap and (ns.Num(Minimap:GetWidth()) or 140) / 2 or 70)
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
-- Holding a Blizzard piece: hidden when off, on the minimap's edge when on. Given back when the module is off.
--
-- Blizzard's pieces are never re-parented and none of their methods is replaced. Their own code calls into their
-- parent (the mail and crafting-order icons call IndicatorFrame:Layout() on UPDATE_PENDING_MAIL), so a piece moved
-- under a plain frame of ours breaks Blizzard's event handler. Hiding is a plain Hide() plus a post-hook on Show and
-- SetShown that hides it again; what Blizzard wanted (shown or not) is remembered so the piece can be given back.
--
-- A piece that is on keeps its parent and is anchored to the minimap. Most pieces live in the header strip of
-- MinimapCluster, which stays in the screen's corner when the minimap is moved, so left alone they would sit there,
-- away from the map and under a top bar. Their scale follows the minimap's and their strata and level are set above
-- the map, so nothing hides under the minimap or its border.
------------------------------------------------------------------------
local function savePoints(obj)
	local pts = {}
	local n = obj.GetNumPoints and ns.Num(obj:GetNumPoints()) or 0
	for i = 1, n do pts[i] = { obj:GetPoint(i) } end
	return pts
end

-- A protected piece cannot be touched in combat (even inside pcall the client reports a blocked action): it waits.
local function lockedNow(obj)
	return InCombatLockdown() and obj.IsProtected and obj:IsProtected()
end

-- A change that combat blocked: applied when combat ends; the settings page says so meanwhile.
M.waiting = {} -- [piece key] = true
local function wait(key)
	M.waiting[key] = true
	ns.AfterCombat("minimap-elements", function() M:ApplyElements(); if ns.Options then ns.Options:Refresh() end end)
end

local function effScale(f) return (f and f.GetEffectiveScale and ns.Num(f:GetEffectiveScale())) or 1 end

local PIECE_LEVEL = 6 -- above the minimap (and under our drawer button, 10 above it)

-- Put a held, shown piece at its place: anchored to the minimap's centre, scaled with it, drawn above it.
local function place(obj)
	local t = taken[obj]
	if not t or t.fixed then return end
	if lockedNow(obj) then wait(t.key) return end
	placing = true
	pcall(function()
		local x, y = t.x or 0, t.y or 0
		local ms = effScale(Minimap)
		local parent = obj.GetParent and obj:GetParent()
		if obj.SetScale and parent then
			local want = ms / effScale(parent)
			if want > 0 and math.abs((ns.Num(obj:GetScale()) or 1) - want) > 0.001 then obj:SetScale(want) end
		else
			local f = ms / effScale(obj)
			x, y = x * f, y * f
		end
		obj:ClearAllPoints()
		obj:SetPoint("CENTER", Minimap, "CENTER", x, y)
		if obj.SetFrameStrata and obj.SetFrameLevel then
			local strata = Minimap:GetFrameStrata()
			if strata and obj:GetFrameStrata() ~= strata then obj:SetFrameStrata(strata) end
			obj:SetFrameLevel((ns.Num(Minimap:GetFrameLevel()) or 2) + PIECE_LEVEL)
		end
	end)
	placing = false
end

-- Hide a piece that is off (our own Hide calls do not count as Blizzard's wish).
local function suppress(obj)
	local t = taken[obj]
	if lockedNow(obj) then wait(t and t.key or "?") return end
	placing = true
	pcall(obj.Hide, obj)
	placing = false
end

local function reveal(obj)
	if lockedNow(obj) then return end
	placing = true
	pcall(obj.Show, obj)
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
			if not h or placing then return end
			h.want = false
			-- the zoom buttons: the game hides them when the mouse leaves the map; switched on, they stay
			if h.keep and h.mode == "place" then reveal(o) end
		end)
	end
	if obj.SetShown then
		hooksecurefunc(obj, "SetShown", function(o, shown)
			local h = taken[o]
			if not h or placing then return end
			h.want = shown and true or false
			if shown and h.mode == "hide" then suppress(o)
			elseif not shown and h.keep and h.mode == "place" then reveal(o) end
		end)
	end
	if obj.SetPoint then
		-- Blizzard lays its header out again (edit mode, a new mail): back to our place
		hooksecurefunc(obj, "SetPoint", function(o)
			local h = taken[o]
			if placing or not h or h.mode ~= "place" then return end
			place(o)
		end)
	end
end

-- Give a piece back to the game: its own anchors, scale, strata and level, shown if Blizzard wanted it shown.
local function restore(obj)
	local t = taken[obj]
	if not t then return end
	if lockedNow(obj) then return end
	taken[obj] = nil
	placing = true
	pcall(function()
		if t.moved then
			if t.scale0 and obj.SetScale then obj:SetScale(t.scale0) end
			if t.strata0 and obj.SetFrameStrata then obj:SetFrameStrata(t.strata0) end
			if t.level0 and obj.SetFrameLevel then obj:SetFrameLevel(t.level0) end
			if #t.points > 0 then
				obj:ClearAllPoints()
				for _, p in ipairs(t.points) do obj:SetPoint(unpack(p)) end
			end
		end
		if t.want and obj.Show then obj:Show() end
	end)
	placing = false
end

-- Hold one frame of a piece. on: shown at x, y from the minimap's centre (fixed: shown where it is); else hidden.
local function take(obj, e, on, x, y, fixed)
	if not obj or obj == Minimap or obj == holder then return end
	if lockedNow(obj) then wait(e.key) return end
	local t = taken[obj]
	if not t then
		t = memo[obj] or {}
		memo[obj] = t
		t.points, t.moved = savePoints(obj), false
		t.scale0 = obj.GetScale and ns.Num(obj:GetScale()) or nil
		t.strata0 = obj.GetFrameStrata and obj:GetFrameStrata() or nil
		t.level0 = obj.GetFrameLevel and ns.Num(obj:GetFrameLevel()) or nil
		t.want = obj.IsShown and obj:IsShown() and true or false
		taken[obj] = t
		hookPiece(obj, t)
	end
	t.key, t.mode, t.fixed, t.keep = e.key, on and "place" or "hide", fixed and true or false, e.keep
	if not on then
		suppress(obj)
		return
	end
	t.x, t.y = x, y
	if t.want or t.keep then reveal(obj) end
	if not t.fixed then
		t.moved = true
		place(obj)
	end
end
M.Taken = function(obj) return taken[obj] end

-- The frames of one piece in this client: { obj = frame, part = its entry (dx, dy), also = true for a frame that is
-- only hidden with the piece }. Each part is the first of its names that exists; with none of them, the frame is
-- looked for by name among the minimap's children.
function M:Parts(e)
	local out, seen = {}, {}
	local function add(o, part, also)
		if o and not seen[o] and o ~= Minimap then seen[o] = true; out[#out + 1] = { obj = o, part = part, also = also } end
	end
	for _, part in ipairs(e.parts or {}) do
		for _, p in ipairs(part) do
			local o = resolve(p)
			if o then add(o, part) break end
		end
	end
	if #out == 0 and e.match then
		for _, parent in ipairs({ MinimapCluster or false, MinimapCluster and MinimapCluster.MinimapContainer or false, Minimap or false }) do
			if type(parent) == "table" and #out == 0 then
				for k, v in pairs(parent) do
					if #out == 0 and type(k) == "string" and type(v) == "table" and type(v.GetObjectType) == "function" and v ~= Minimap then
						for _, pat in ipairs(e.match) do if k:find(pat) then add(v, {}) break end end
					end
				end
				for _, child in ipairs({ parent:GetChildren() }) do
					local n = child.GetName and child:GetName()
					if #out == 0 and n and not n:find("^" .. ns.PREFIX) then
						for _, pat in ipairs(e.match) do if n:find(pat) then add(child, {}) break end end
					end
				end
			end
		end
	end
	for _, p in ipairs(e.also or {}) do add(resolve(p), {}, true) end
	return out
end

-- The frames found for one piece.
function M:Find(e)
	local found = {}
	for i, p in ipairs(self:Parts(e)) do found[i] = p.obj end
	return found
end

-- How much room a piece takes (its frames together), in its own units.
function M:PieceSize(e)
	local w, h = 0, 0
	for _, p in ipairs(self:Parts(e)) do
		if not p.also then
			local pw, ph = p.obj:GetSize()
			w = math.max(w, (ns.Num(pw) or 0) + 2 * math.abs(p.part.dx or 0))
			h = math.max(h, (ns.Num(ph) or 0) + 2 * math.abs(p.part.dy or 0))
		end
	end
	return w, h
end

-- How far the pieces that are on stick out past the minimap's edge: left, right, top, bottom (the minimap's units).
function M:Overhang()
	local l, r, t, b = 0, 0, 0, 0
	if not self.running or self.stepAside or not Minimap then return l, r, t, b end
	local half = self:Half()
	for _, e in ipairs(M.ELEMENTS) do
		if not e.fixed and self:PieceShown(e.key) then
			local w, h = self:PieceSize(e)
			if w > 0 and h > 0 then
				local x, y = self:PieceXY(e.key)
				r, l = math.max(r, x + w / 2 - half), math.max(l, -(x - w / 2) - half)
				t, b = math.max(t, y + h / 2 - half), math.max(b, -(y - h / 2) - half)
			end
		end
	end
	return l, r, t, b
end

-- Does this client have the piece at all? (No world map button or difficulty flag in WoW Forever.)
function M:Present(key)
	local e = M.ELEMENT[key]
	return e ~= nil and #self:Parts(e) > 0
end

-- Art to show for a piece in the settings: { atlas = name } or { file = texture, coords = {...} }, with its size;
-- nil when the piece is text only (the row then shows a line icon). ART: where the picture is inside the frame.
local ART = {
	tracking = { "Button.StateTexture" }, mail = { "MailFrame.MailIcon", "MailIcon" }, calendar = { "StateTexture" },
	compartment = { "StateTexture" }, daynight = { "Background" }, ringart = {}, zoom = {}, worldmap = {}, difficulty = {},
}
function M:Preview(key)
	local e = M.ELEMENT[key]
	if not e or not ART[key] then return nil end
	local obj = self:Parts(e)[1]
	obj = obj and obj.obj
	if not obj then return nil end
	local tex
	for _, path in ipairs(ART[key]) do
		local t = obj
		for k in path:gmatch("[^%.]+") do t = type(t) == "table" and t[k] or nil end
		if type(t) == "table" and t.GetTexture then tex = t break end
	end
	if not tex and key == "ringart" and type(MinimapCompassTexture) == "table" then tex = MinimapCompassTexture end
	if not tex and obj.GetObjectType and obj:GetObjectType() == "Texture" then tex = obj end
	if not tex and obj.GetNormalTexture then tex = obj:GetNormalTexture() end
	if type(tex) ~= "table" or not tex.GetTexture then return nil end
	local w, h = tex:GetSize()
	local atlas = tex.GetAtlas and ns.Str(tex:GetAtlas())
	if atlas and atlas ~= "" then return { atlas = atlas, w = ns.Num(w), h = ns.Num(h) } end
	local file = tex:GetTexture()
	if file == nil or ns.IsSecret(file) or (type(file) ~= "string" and type(file) ~= "number") then return nil end
	return { file = file, coords = { tex:GetTexCoord() }, w = ns.Num(w), h = ns.Num(h) }
end

function M:ApplyElements()
	if self.stepAside or not self.running or not Minimap then return end
	wipe(self.waiting)
	local half, shape = self:Half(), mdb().shape
	for _, e in ipairs(M.ELEMENTS) do
		local on = self:PieceShown(e.key)
		local px, py = 0, 0
		if on and not e.fixed then
			local a, d = self:PiecePos(e.key)
			px, py = M.PiecePoint(a, d, shape, half)
		end
		for _, p in ipairs(self:Parts(e)) do
			take(p.obj, e, on, px + (p.part.dx or 0), py + (p.part.dy or 0), e.fixed or p.also)
		end
	end
end

-- Is anything on the minimap page waiting for combat to end?
function M:Waiting()
	return self.frameWaiting or next(self.waiting) ~= nil
end

-- Report what was found (for /ebar minimap scan).
function M:Report()
	for _, e in ipairs(M.ELEMENTS) do
		local names = {}
		for _, obj in ipairs(self:Find(e)) do names[#names + 1] = (obj.GetName and obj:GetName()) or "(unnamed)" end
		ns:Print(e.label .. " [" .. (self:PieceOn(e.key) and "on" or "off") .. "]: " .. (#names > 0 and table.concat(names, ", ") or "|cff8d94a3not in this client|r"))
	end
	ns:Print("addon buttons held: " .. #heldList .. (self.buttonRival and (" (|cffffd25a" .. self.buttonRival .. " collects them|r)") or ""))
	for n, why in pairs(M.skipped) do
		if not held[_G[n] or false] then ns:Print("left on the minimap: " .. U.Escape(n) .. " (" .. why .. ")") end
	end
	for _, c in ipairs(self:ForeignCoords()) do ns:Print("|cffffd25a" .. c.addon .. "|r: " .. c.fix) end
	local found = self:ScanText()
	if #found == 0 then
		ns:Print("no other text shown around the minimap.")
	else
		ns:Print("text shown around the minimap (not ours):")
		for _, f in ipairs(found) do
			ns:Print("  " .. U.Escape(f.name) .. " (" .. f.owner .. "): \"" .. U.Escape(f.text) .. "\"")
		end
	end
end

------------------------------------------------------------------------
-- Coordinates from other addons. Blizzard's own (MinimapCluster.MinimapContainer.PlayerCoords) is the "coords"
-- element above and is hidden cleanly. Another addon's own feature is not fought: we say which setting turns it off.
------------------------------------------------------------------------
function M:ForeignCoords()
	local out = {}
	local q = type(Questie) == "table" and type(Questie.db) == "table" and type(Questie.db.profile) == "table" and Questie.db.profile
	if q and q.minimapCoordinatesEnabled == true then
		out[#out + 1] = { addon = "Questie", fix = "puts coordinates in the minimap zone text. Turn it off: /questie > General > untick \"Show Minimap Coordinates\"." }
	end
	local tt = type(TomTom) == "table" and type(TomTom.profile) == "table" and TomTom.profile.block
	if type(tt) == "table" and tt.enable and TomTomBlock and TomTomBlock.IsShown and TomTomBlock:IsShown() then
		out[#out + 1] = { addon = "TomTom", fix = "shows a coordinate block. Turn it off: /tomtom > Coordinate Block > untick \"Enable coordinate block\"." }
	end
	return out
end

-- Tell once ever, in chat, about another addon's coordinates (after that: /ebar status and /ebar minimap).
function M:TellForeignCoords()
	for _, c in ipairs(self:ForeignCoords()) do
		if ns.TellOnce("coords:" .. c.addon) then
			ns:Print("coordinates near the minimap come from |cffffd25a" .. c.addon .. "|r, which " .. c.fix)
		end
	end
end

-- Lines for /ebar status: who else manages the minimap, its buttons or coordinates.
function M:StatusLines()
	local out = {}
	if not self.running then return out end
	if self.stepAside then
		out[#out + 1] = "Minimap: " .. self.stepAside .. " manages it, so " .. ns.NAME .. " leaves it alone (disable "
			.. self.stepAside .. " and /reload to use ours)."
	end
	if self.buttonRival then out[#out + 1] = "Minimap buttons: " .. self.buttonRival .. " collects them; the drawer is off." end
	for _, c in ipairs(self:ForeignCoords()) do out[#out + 1] = "Coordinates: " .. c.addon .. " " .. c.fix end
	return out
end

-- The loaded addon a frame most likely belongs to, from its name.
local function ownerOf(name)
	if not name or name == "" then return "unknown addon" end
	if name:find("^Minimap") or name:find("^MiniMap") or name:find("^GameTime") or name:find("^TimeManager") then return "Blizzard" end
	local n = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or 0
	local best
	for i = 1, n do
		local a = C_AddOns.GetAddOnInfo(i)
		if type(a) == "string" and loaded(a) then
			local stem = a:gsub("[_%-%s]", "")
			if (name:sub(1, #a) == a or name:sub(1, #stem) == stem) and (not best or #a > #best) then best = a end
		end
	end
	return best or "unknown addon"
end
M.OwnerOf = ownerOf

-- "Parent.Key" for an unnamed frame, else its name.
local function nameOf(f)
	local n = f.GetName and f:GetName()
	if n then return n end
	local p = f.GetParent and f:GetParent()
	if p then
		local pn = p.GetName and p:GetName()
		for k, v in pairs(p) do
			if v == f and type(k) == "string" then return (pn or "?") .. "." .. k end
		end
		if pn then return pn .. ".(child)" end
	end
	return "(unnamed)"
end

-- Every visible text near the minimap that is not ours: FontStrings of shown frames within 60 px of the map.
function M:ScanText()
	local found = {}
	local s = (ns.Num(Minimap:GetEffectiveScale()) or 1)
	local l, b, w, h = ns.Num(Minimap:GetLeft()), ns.Num(Minimap:GetBottom()), ns.Num(Minimap:GetWidth()), ns.Num(Minimap:GetHeight())
	if not (l and b and w and h) or not EnumerateFrames then return found end
	local m = 60
	local L, B, R, T = l * s - m, b * s - m, (l + w) * s + m, (b + h) * s + m
	local f, guard = EnumerateFrames(), 0
	while f and guard < 30000 do
		guard = guard + 1
		local name = f.GetName and f:GetName()
		if f.IsVisible and f:IsVisible() and f.GetRegions and not (name and name:find("^" .. ns.PREFIX)) and f ~= M.overlay
			and not (M.overlay and f:GetParent() == M.overlay) then
			for _, r in ipairs({ f:GetRegions() }) do
				if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsVisible() then
					local text = ns.Str(r:GetText())
					if text and text:find("%S") then
						local es = ns.Num(r:GetEffectiveScale()) or s
						local x, y = r:GetCenter()
						x, y = ns.Num(x), ns.Num(y)
						if x and y and x * es >= L and x * es <= R and y * es >= B and y * es <= T then
							local fname = nameOf(f)
							found[#found + 1] = { name = fname, owner = ownerOf(name or fname), text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") }
						end
					end
				end
			end
		end
		f = EnumerateFrames(f)
	end
	return found
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

-- Masks. The round one is our own texture (Media\MinimapRound.tga: white, alpha circle): a mask path that does not
-- exist in this client leaves the minimap black, so we never rely on the game's own mask files for it.
M.MASKS = {
	round = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\MinimapRound",
	square = "Interface\\Buttons\\WHITE8X8",
}

local function applyShape(square)
	local mask = square and M.MASKS.square or M.MASKS.round
	pcall(Minimap.SetMaskTexture, Minimap, mask)
	M.mask = mask
	-- the indoor/hybrid map has its own canvas mask
	local hy = HybridMinimap
	if type(hy) == "table" and hy.MapCanvas and hy.CircleMask then
		pcall(function()
			hy.MapCanvas:SetUseMaskTexture(false)
			hy.CircleMask:SetTexture(mask)
			hy.MapCanvas:SetUseMaskTexture(true)
		end)
	end
	-- the quest/archaeology blob rings are drawn for a round map; on a square one they leave a ring of "waffle" marks
	local ring = square and 0 or 1
	if square or M.blobRingsOff then
		M.blobRingsOff = square
		for _, f in ipairs({ "SetArchBlobRingScalar", "SetArchBlobRingAlpha", "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
			"SetTaskBlobRingScalar", "SetTaskBlobRingAlpha" }) do
			if Minimap[f] then pcall(Minimap[f], Minimap, ring) end
		end
	end
	-- addons ask this global for the shape (LibDBIcon and others); define it only if nobody else has
	if GetMinimapShape == nil or M.ownsShapeFunc then
		M.ownsShapeFunc = true
		GetMinimapShape = function() return mdb().shape == "square" and "SQUARE" or "ROUND" end
	end
end
M.ApplyShape = applyShape

-- The border: a solid colour a little larger than the minimap, cut to the same shape, BEHIND the minimap (its own
-- frame at BACKGROUND strata). The minimap covers the middle, so only a ring (or square frame) shows.
local function applyBorder(square)
	local db = mdb()
	if not borderFrame then
		borderFrame = CreateFrame("Frame", nil, holder)
		borderFrame:SetFrameStrata("BACKGROUND")
		borderFrame:SetFrameLevel(1)
		borderFrame:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
		borderFrame.tex = borderFrame:CreateTexture(nil, "BACKGROUND")
		borderFrame.tex:SetAllPoints()
		borderFrame.tex:SetTexture(U.WHITE)
		if borderFrame.CreateMaskTexture and borderFrame.tex.AddMaskTexture then
			borderFrame.mask = borderFrame:CreateMaskTexture()
			borderFrame.mask:SetAllPoints(borderFrame.tex)
			borderFrame.tex:AddMaskTexture(borderFrame.mask)
		end
		M.borderFrame = borderFrame
	end
	local t = math.max(1, math.min(8, math.floor(tonumber(db.borderSize) or 2)))
	local w, h = Minimap:GetSize()
	w, h = ns.Num(w) or 140, ns.Num(h) or 140
	borderFrame:SetSize(w + 2 * t, h + 2 * t)
	local c = db.borderColor or { 0, 0, 0, 1 }
	borderFrame.tex:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
	if borderFrame.mask then borderFrame.mask:SetTexture(square and M.MASKS.square or M.MASKS.round) end
	-- without mask support only the square border can be drawn
	borderFrame:SetShown(db.border and (square or borderFrame.mask ~= nil))
end

function M:ApplyFrame()
	if self.stepAside then return end
	local db = mdb()
	if not db.snapDefaultOff then db.snapDefaultOff = true; db.snapEdges = false end
	if not holder then
		holder = CreateFrame("Frame", ns.PREFIX .. "MinimapHolder", UIParent)
		holder:SetFrameStrata("LOW")
		holder:SetFrameLevel(1)
		holder:SetMovable(true)
		holder:SetClampedToScreen(true)
		M.holder = holder
	end
	local w, h = Minimap:GetSize()
	w, h = ns.Num(w) or 140, ns.Num(h) or 140
	local scale = M.ClampScale(db.scale)
	local cx, cy = self:Center()
	local W, H = screenSize()
	local pad = 2 * self:BorderPad()
	local x, y = M.SnapCenter(cx, cy, (w + pad) * scale, (h + pad) * scale, W, H, 0)
	holder:SetScale(scale)
	local b = self:BorderPad()
	if holder.SetClampRectInsets then holder:SetClampRectInsets(-b, b, b, -b) end
	holder:SetSize(w, h)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	placing = true
	if Minimap:GetParent() ~= holder then Minimap:SetParent(holder) end
	-- a new parent resets strata and level; keep Blizzard's (LOW) and stay above the holder and our border
	if Minimap:GetFrameStrata() ~= "LOW" then Minimap:SetFrameStrata("LOW") end
	if (ns.Num(Minimap:GetFrameLevel()) or 0) < 2 then Minimap:SetFrameLevel(2) end
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", holder, "CENTER", 0, 0)
	placing = false
	-- the minimap cluster stays in the corner (zone text and friends live there); it must not eat clicks there
	if MinimapCluster and MinimapCluster.IsMouseEnabled and MinimapCluster:IsMouseEnabled() and not self.clusterMouseOff then
		if pcall(MinimapCluster.EnableMouse, MinimapCluster, false) then self.clusterMouseOff = true end
	end
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
	local square = db.shape == "square"
	applyShape(square)
	applyBorder(square)
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
	if self.ApplyUnlock then self:ApplyUnlock() end
	if self.ApplyZoneLabel then self:ApplyZoneLabel() end
	-- the pieces sit on the edge: a new size, shape or border moves them with it
	if self.running and next(taken) ~= nil then self:ApplyElements() end
	if ns.Unlock and ns.Unlock.active then ns.Unlock:SyncMovers() end
end

function M.ClampScale(v) return math.max(0.5, math.min(2.5, tonumber(v) or 1)) end

-- Mover dropped: the new centre in UIParent units.
function M:SetCenter(x, y)
	mdb().point = { math.floor(x + 0.5), math.floor(y + 0.5) }
	ns.AfterCombat("minimap-frame", function() M:ApplyFrame() end)
end

-- The minimap's size on screen, in UIParent units.
-- The border's thickness counts as part of the minimap, so keeping it on screen never swallows one side of it.
function M:BorderPad()
	local db = mdb()
	if not db.border then return 0 end
	return math.max(1, math.min(8, math.floor(tonumber(db.borderSize) or 2)))
end

function M:ScreenSize()
	local w, h = Minimap:GetSize()
	local sc = M.ClampScale(mdb().scale)
	local pad = 2 * self:BorderPad()
	return ((ns.Num(w) or 140) + pad) * sc, ((ns.Num(h) or 140) + pad) * sc
end

-- Keep a centre on screen and pull it flush to an edge (or the screen's middle line) when within `dist`.
-- inset: { left, right, top, bottom } taken at the screen's edges (our bars), kept clear of as well.
function M.SnapCenter(x, y, w, h, W, H, dist, inset)
	local hw, hh = w / 2, h / 2
	dist = dist or 0
	local l, r, t, b = 0, 0, 0, 0
	if inset then l, r, t, b = inset[1] or 0, inset[2] or 0, inset[3] or 0, inset[4] or 0 end
	if x - hw - l < dist then x = l + hw elseif (W - r) - (x + hw) < dist then x = W - r - hw end
	if y - hh - b < dist then y = b + hh elseif (H - t) - (y + hh) < dist then y = H - t - hh end
	if dist > 0 and math.abs(x - W / 2) < dist then x = W / 2 end
	if w > W - l - r then x = (l + W - r) / 2 end
	if h > H - t - b then y = (b + H - t) / 2 end
	return x, y
end

-- The room our own bars take at the screen's edges: left, right, top, bottom. A minimap that is dropped, resized or
-- reset stays clear of them, so the map and the pieces on its edge are not under a bar. (A minimap already saved
-- under a bar is left where it is.)
function M.BarInsets()
	local W, H = screenSize()
	local l, r, t, b = 0, 0, 0, 0
	local rects = ns.Bars and ns.Bars.frames
	for i, bar in ipairs(ns.db and ns.db.bars or {}) do
		local f = rects and rects[i]
		local rc = f and f.rect
		if rc and bar.shown ~= false then
			if bar.edge == "top" then t = math.max(t, H - rc.y)
			elseif bar.edge == "bottom" then b = math.max(b, rc.y + rc.h)
			elseif bar.edge == "left" then l = math.max(l, rc.x + rc.w)
			elseif bar.edge == "right" then r = math.max(r, W - rc.x) end
		end
	end
	return { l, r, t, b }
end

-- The bars' room plus what the pieces need past the minimap's edge: a dropped or resized minimap keeps its pieces on
-- screen and out from under the bars too.
function M:Insets()
	local inset = M.BarInsets()
	local sc = M.ClampScale(mdb().scale)
	local l, r, t, b = self:Overhang()
	return { inset[1] + l * sc, inset[2] + r * sc, inset[3] + t * sc, inset[4] + b * sc }
end

-- Where a reset puts it: the top-right corner, clear of a top bar.
function M:DefaultCenter()
	local W, H = screenSize()
	local w, h = self:ScreenSize()
	local inset = self:Insets()
	return W - inset[2] - w / 2 - 16, H - h / 2 - math.max(34, inset[3] + 12)
end

function M:ResetPosition(quiet)
	if InCombatLockdown() then self:SayCombat() return false end
	if self.stepAside then ns:Print(self.stepAside .. " manages the minimap, so reset it there.") return false end
	local db = mdb()
	db.scale = 1
	local x, y = self:DefaultCenter()
	db.point = { math.floor(x + 0.5), math.floor(y + 0.5) }
	self:ApplyFrame()
	if drawer and drawer:IsShown() then M.AnchorDrawer() end
	if not quiet then ns:Print("minimap back in the top-right corner at 100%.") end
	if ns.Options then ns.Options:Refresh() end
	return true
end

------------------------------------------------------------------------
-- Moving: in edit mode (Unlock.lua) a mover of ours covers the map. Drag it to move the minimap, mouse wheel over
-- it to resize. A guide shows the edge the pieces stick to: a ring on a round map, the square's outline on a square
-- one, with a larger dot at every snap point. Locked, the mover is hidden and every click goes to the map as normal.
------------------------------------------------------------------------
M.unlocked = false
local overlay

function M:SayCombat()
	ns:Print("the minimap can't be moved in combat (the game locks its frames). Try again when combat ends.")
end

local function holderCenter()
	local x, y = holder:GetCenter()
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y then return nil end
	local s = (ns.Num(holder:GetEffectiveScale()) or 1) / (ns.Num(UIParent:GetEffectiveScale()) or 1)
	return x * s, y * s
end

-- A drag ended (or the scale changed): store the centre, snapped to the screen edges, and re-anchor.
function M:DropHolder()
	local x, y = holderCenter()
	if not x then return end
	local W, H = screenSize()
	local w, h = self:ScreenSize()
	x, y = M.SnapCenter(x, y, w, h, W, H, mdb().snapEdges ~= false and 12 or 0, self:Insets())
	self:SetCenter(x, y)
	if drawer and drawer:IsShown() then M.AnchorDrawer() end
end

-- The minimap's size as a whole percentage (the edit-mode control shows it).
function M:SizePercent() return math.floor(M.ClampScale(mdb().scale) * 100 + 0.5) end

-- The size changed from the settings, or a piece was switched on: stay on screen and clear of the bars (the pieces
-- on the edge too), as after a mouse-wheel step. Returns true when the minimap has to move for it.
function M:KeepClear()
	local db = mdb()
	if not holder or self.stepAside then return end
	local W, H = screenSize()
	local w, h = self:ScreenSize()
	local cx, cy = self:Center()
	local x, y = M.SnapCenter(cx, cy, w, h, W, H, 0, self:Insets())
	if math.abs(x - cx) < 0.5 and math.abs(y - cy) < 0.5 then return false end -- it is clear already
	db.point = { math.floor(x + 0.5), math.floor(y + 0.5) }
	return true
end

-- Scale by mouse wheel steps (5% each), kept centred.
function M:Nudge(delta)
	if InCombatLockdown() then self:SayCombat() return end
	local db = mdb()
	local x, y = holderCenter()
	db.scale = M.ClampScale(math.floor((M.ClampScale(db.scale) + (delta > 0 and 0.05 or -0.05)) * 100 + 0.5) / 100)
	if x then
		-- a bigger map stays on screen and clear of the bars
		local W, H = screenSize()
		local w, h = self:ScreenSize()
		x, y = M.SnapCenter(x, y, w, h, W, H, 0, self:Insets())
		db.point = { math.floor(x + 0.5), math.floor(y + 0.5) }
	end
	self:ApplyFrame()
	if ns.Unlock then ns.Unlock:SyncMovers() end
	if ns.Options then ns.Options:Refresh() end
end

-- Dragging the minimap (the mover over the map, or the edit-mode control in its middle).
function M:StartDrag()
	if not holder or not self.unlocked then return end
	if InCombatLockdown() then self:SayCombat() return end
	GameTooltip:Hide()
	self.dragging = true
	holder:StartMoving()
end

function M:StopDrag()
	if not self.dragging then return end
	self.dragging = false
	holder:StopMovingOrSizing()
	self:DropHolder()
	if ns.Unlock then ns.Unlock:SyncMovers() end
end

-- The edge the pieces stick to, as dots: small ones along it, a larger one at each snap point (the corners of a
-- square map largest: they pull from furthest away). Drawn in the minimap's own units, so it follows its size.
local function drawGuide()
	local g = overlay.guide
	local T = ns.Theme
	local half, square = M:Half(), mdb().shape == "square"
	local n = 0
	local function dot(x, y, size, alpha)
		n = n + 1
		local t = g.dots[n]
		if not t then
			t = g:CreateTexture(nil, "OVERLAY")
			t:SetTexture(U.WHITE)
			g.dots[n] = t
		end
		t:ClearAllPoints()
		t:SetSize(size, size)
		t:SetPoint("CENTER", g, "CENTER", x, y)
		t:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], alpha)
		t:Show()
	end
	if square then
		local steps = math.max(4, math.floor(half * 2 / 9 + 0.5))
		for k = 0, steps - 1 do
			local p = -half + 2 * half * k / steps
			dot(p, half, 2, 0.75); dot(half, -p, 2, 0.75); dot(-p, -half, 2, 0.75); dot(-half, p, 2, 0.75)
		end
		for a = 0, 315, 45 do
			local x, y = M.PiecePoint(a, 0, "square", half)
			dot(x, y, a % 90 == 45 and 7 or 5, 1)
		end
	else
		for a = 0, 355, 5 do
			local x, y = M.PiecePoint(a, 0, "round", half)
			if a % 45 == 0 then dot(x, y, 5, 1) else dot(x, y, 2, 0.75) end
		end
	end
	for i = n + 1, #g.dots do g.dots[i]:Hide() end
	g.shape, g.half = square and "square" or "round", half
	if overlay.mask then overlay.mask:SetTexture(square and M.MASKS.square or M.MASKS.round) end
end

local function makeOverlay()
	if overlay then return end
	local T = ns.Theme
	overlay = CreateFrame("Button", ns.PREFIX .. "MinimapMover", holder)
	overlay:SetAllPoints(Minimap)
	overlay:SetFrameStrata("HIGH")
	overlay:EnableMouse(true)
	overlay:EnableMouseWheel(true)
	overlay:RegisterForDrag("LeftButton")
	-- a light tint in the map's own shape
	local fill = overlay:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(); fill:SetTexture(U.WHITE); fill:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.14)
	if overlay.CreateMaskTexture and fill.AddMaskTexture then
		overlay.mask = overlay:CreateMaskTexture()
		overlay.mask:SetAllPoints(fill)
		fill:AddMaskTexture(overlay.mask)
	end
	overlay.fill = fill
	local guide = CreateFrame("Frame", nil, overlay)
	guide:SetSize(1, 1)
	guide:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
	guide.dots = {}
	overlay.guide = guide
	overlay:SetScript("OnDragStart", function() M:StartDrag() end)
	overlay:SetScript("OnDragStop", function() M:StopDrag() end)
	overlay:SetScript("OnMouseWheel", function(_, delta) M:Nudge(delta) end)
	overlay:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Minimap", 1, 1, 1)
		GameTooltip:AddLine("Drag to move it. Mouse wheel: size. The dots are the edge its pieces stick to.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
	overlay:Hide()
	M.overlay = overlay
end

-- Show the mover while unlocked (called from ApplyFrame too: a new size, shape or border redraws the guide).
function M:ApplyUnlock()
	if not self.unlocked or not holder then
		if overlay then overlay:Hide() end
		return
	end
	makeOverlay()
	drawGuide()
	overlay:Show()
end

-- on: true to unlock. quiet: no chat line. Returns whether it is now as asked. Edit mode (Unlock.lua) calls this;
-- the minimap is not unlocked on its own any more.
function M:SetUnlocked(on, quiet)
	on = on and true or false
	if on then
		if not self.running then if not quiet then ns:Print("the clean minimap is off; switch it on first.") end return false end
		if self.stepAside then if not quiet then ns:Print(self.stepAside .. " manages the minimap, so move it there.") end return false end
		if InCombatLockdown() then if not quiet then self:SayCombat() end return false end
		if not holder then self:ApplyFrame() end
	end
	if not on then self:StopDrag() end
	self.unlocked = on
	self:ApplyUnlock()
	if ns.Options then ns.Options:Refresh() end
	return true
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

-- A button can be collected cleanly when it is not protected and has an icon of its own to show.
local function hasIcon(b)
	if b.icon and b.icon.GetObjectType then return true end -- LibDBIcon and most others
	if not b.GetRegions then return false end
	for _, r in ipairs({ b:GetRegions() }) do
		if r and r.GetObjectType and r:GetObjectType() == "Texture" then
			local tex = r.GetTexture and r:GetTexture()
			if tex ~= nil and not ns.IsSecret(tex) then return true end
		end
	end
	local nt = b.GetNormalTexture and b:GetNormalTexture()
	return nt ~= nil
end
M.HasIcon = hasIcon

local CELL, PAD, TOP = 34, 8, 4

-- Buttons being dragged right now (by their own addon): never re-anchored or collected mid-drag.
local dragging = setmetatable({}, { __mode = "k" })
local function isDragging(b)
	if dragging[b] then return true end
	if b.IsDragging then
		local ok, d = pcall(b.IsDragging, b)
		if ok and d == true then return true end
	end
	return false
end
M.IsDragging = isDragging

local function relayoutDrawer()
	if not drawer then return end
	local cols = math.max(1, math.min(12, tonumber(mdb().drawerCols) or 6))
	local n = 0
	local level = (ns.Num(drawer:GetFrameLevel()) or 1) + 5
	placing = true
	for _, b in ipairs(heldList) do
		local info = held[b]
		if info and not info.hiddenByOwner and b:GetParent() == drawer then
			local col, row = n % cols, math.floor(n / cols)
			if not isDragging(b) then pcall(function()
				b:ClearAllPoints()
				b:SetPoint("CENTER", drawer, "TOPLEFT", PAD + col * CELL + CELL / 2, -PAD - TOP - row * CELL - CELL / 2)
				b:SetFrameStrata(drawer:GetFrameStrata())
				b:SetFrameLevel(level)
				b:SetAlpha(1)
			end) end -- a button being dragged keeps its cell but is not moved
			n = n + 1
		end
	end
	placing = false
	local rows = math.max(1, math.ceil(n / cols))
	drawer:SetSize(PAD * 2 + math.max(1, math.min(n, cols)) * CELL + (n == 0 and 60 or 0), PAD * 2 + TOP + rows * CELL)
	drawer.empty:SetShown(n == 0)
	if drawerToggle then
		drawerToggle.count = n
		drawerToggle:SetShown(mdb().buttons == "drawer" and n > 0)
		if n == 0 then drawer:Hide() end
	end
end
M.RelayoutDrawer = relayoutDrawer

-- Where the drawer opens: beside the drawer button, on the side of the minimap the button sits on, growing along the
-- minimap (up from a bottom corner, down from a top corner). Flips sideways when there is no room. Pure maths.
-- corner: the button's corner of the minimap; tx: the button's centre x on screen; dw: the drawer's width; W: screen.
function M.DrawerAnchor(corner, tx, dw, W)
	local top = corner == "TOPLEFT" or corner == "TOPRIGHT"
	local left = corner == "TOPLEFT" or corner == "BOTTOMLEFT"
	if left and tx - dw - 12 < 0 then left = false elseif not left and tx + dw + 12 > W then left = true end
	local v = top and "TOP" or "BOTTOM"
	if left then return v .. "RIGHT", v .. "LEFT", -6 end
	return v .. "LEFT", v .. "RIGHT", 6
end

local function anchorDrawer()
	local c = mdb().drawerCorner
	if c ~= "TOPLEFT" and c ~= "TOPRIGHT" and c ~= "BOTTOMRIGHT" then c = "BOTTOMLEFT" end
	local inset = { TOPLEFT = { 3, -3 }, TOPRIGHT = { -3, -3 }, BOTTOMLEFT = { 3, 3 }, BOTTOMRIGHT = { -3, 3 } }
	drawerToggle:ClearAllPoints()
	drawerToggle:SetPoint(c, Minimap, c, inset[c][1], inset[c][2])
	local tx = ns.Num((drawerToggle:GetCenter()))
	local s = (ns.Num(drawerToggle:GetEffectiveScale()) or 1) / (ns.Num(UIParent:GetEffectiveScale()) or 1)
	local W = screenSize()
	local point, rel, dx = M.DrawerAnchor(c, (tx or 0) * s, ns.Num(drawer:GetWidth()) or 100, W)
	drawer:ClearAllPoints()
	drawer:SetPoint(point, drawerToggle, rel, dx, 0)
	M.drawerPoint = point
end
M.AnchorDrawer = function() if drawer then anchorDrawer() end end

local function makeDrawer()
	if drawer then return end
	local T = ns.Theme
	drawerToggle = CreateFrame("Button", ns.PREFIX .. "MinimapDrawerButton", Minimap)
	drawerToggle:SetSize(20, 20)
	drawerToggle:SetFrameLevel((ns.Num(Minimap:GetFrameLevel()) or 1) + 10)
	drawerToggle:RegisterForClicks("LeftButtonUp")
	-- our style: a dark slate tile, thin border, a 2x2 grid of light squares; the accent colour on hover and while open
	U.Solid(drawerToggle, "BACKGROUND", T.bg[1], T.bg[2], T.bg[3], 0.92):SetAllPoints()
	drawerToggle.border = U.Border(drawerToggle, 1, T.border[1], T.border[2], T.border[3], 1)
	drawerToggle.squares = {}
	for i = 0, 3 do
		local sq = drawerToggle:CreateTexture(nil, "ARTWORK")
		sq:SetTexture(U.WHITE)
		sq:SetSize(5, 5)
		sq:SetPoint("TOPLEFT", 4 + (i % 2) * 7, -4 - math.floor(i / 2) * 7)
		drawerToggle.squares[#drawerToggle.squares + 1] = sq
	end
	function drawerToggle:Paint()
		local on = self.hover or (drawer and drawer:IsShown())
		local c = on and T.accent or T.text
		for _, sq in ipairs(self.squares) do sq:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.75) end
		if on then self.border:SetColor(T.accent[1], T.accent[2], T.accent[3], 1) else self.border:SetColor(T.border[1], T.border[2], T.border[3], 1) end
	end
	drawerToggle:SetScript("OnEnter", function(self)
		self.hover = true; self:Paint()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Addon buttons", 1, 1, 1)
		GameTooltip:AddLine((self.count or 0) .. " minimap buttons. Click to show or hide them.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	drawerToggle:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); GameTooltip:Hide() end)
	drawerToggle:SetScript("OnClick", function(self)
		GameTooltip:Hide()
		if drawer:IsShown() then drawer:Hide() else relayoutDrawer(); anchorDrawer(); drawer:Show() end
		self:Paint()
	end)

	drawer = CreateFrame("Frame", ns.PREFIX .. "MinimapDrawer", UIParent)
	drawer.eluiTheme = T
	drawer:SetFrameStrata("HIGH")
	drawer:SetClampedToScreen(true)
	drawer:EnableMouse(true)
	drawer:Hide()
	U.Solid(drawer, "BACKGROUND", T.bg[1], T.bg[2], T.bg[3], 0.96):SetAllPoints()
	local top = U.Solid(drawer, "ARTWORK", T.accent[1], T.accent[2], T.accent[3], 1)
	top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
	U.Border(drawer, 1, T.border[1], T.border[2], T.border[3], 1)
	drawer.empty = drawer:CreateFontString(nil, "OVERLAY")
	U.SetFont(drawer.empty, 10)
	drawer.empty:SetPoint("CENTER")
	drawer.empty:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
	drawer.empty:SetText("none")
	drawer:SetScript("OnShow", function() if drawerToggle then drawerToggle:Paint() end end)
	drawer:SetScript("OnHide", function() if drawerToggle then drawerToggle:Paint() end end)
	-- Escape closes it through its own key handler (never UISpecialFrames)
	ns.UI.CloseOnEscape(drawer)
	drawerToggle:Paint()
	M.drawer, M.drawerToggle = drawer, drawerToggle
end

local function libIcon() return LibStub and LibStub("LibDBIcon-1.0", true) end

-- Take one addon button into the drawer (or out of sight). Everything about it that we change is remembered and
-- given back on release. The button keeps its own textures, scripts, tooltip and click.
M.skipped = {} -- [button name] = why it was left where it was
local function skip(b, why)
	local n = b.GetName and b:GetName()
	if n then M.skipped[n] = why end
end

local function hold(b)
	if held[b] or not b then return end
	if isDragging(b) then return end -- its addon is moving it: try again on the next scan
	if b.IsProtected and b:IsProtected() then skip(b, "protected") return end
	if not hasIcon(b) then skip(b, "no icon of its own") return end -- nothing to show: leave it where it is
	local info = {
		parent = b:GetParent(), points = savePoints(b),
		strata = b.GetFrameStrata and b:GetFrameStrata(), level = ns.Num(b.GetFrameLevel and b:GetFrameLevel()),
		fixedStrata = b.HasFixedFrameStrata and b:HasFixedFrameStrata(), fixedLevel = b.HasFixedFrameLevel and b:HasFixedFrameLevel(),
		alpha = ns.Num(b:GetAlpha()) or 1, fade = b.showOnMouseover,
		drag = b.GetScript and b:GetScript("OnDragStart") ~= nil,
	}
	local ok = pcall(function()
		-- LibDBIcon fades buttons out away from the minimap (showOnMouseover): in the drawer they stay visible
		if b.showOnMouseover then
			b.showOnMouseover = false
			if b.fadeOut then b.fadeOut:Stop() end
		end
		-- dragging it around the minimap would fight the drawer
		if b.RegisterForDrag then b:RegisterForDrag() end
		-- LibDBIcon pins strata and level; the drawer needs them above itself
		if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
		if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
		b:SetParent(mdb().buttons == "hide" and hider or drawer)
		b:SetAlpha(1)
	end)
	if not ok then
		skip(b, "refused to move")
		-- could not be collected cleanly: put back what was changed and leave it
		pcall(function()
			b:SetParent(info.parent)
			b:ClearAllPoints()
			for _, p in ipairs(info.points) do b:SetPoint(unpack(p)) end
			b.showOnMouseover = info.fade
			if info.drag and b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
		end)
		return
	end
	held[b] = info
	heldList[#heldList + 1] = b
	if not hooked[b] then
		hooked[b] = true
		hooksecurefunc(b, "SetPoint", function(o)
			if placing or not held[o] or isDragging(o) then return end
			ns.Soon(relayoutDrawer)
		end)
		-- its own addon drags it (EverlookPets' button around the minimap): hands off until it is dropped
		if b.HookScript and b.GetScript then
			pcall(b.HookScript, b, "OnDragStart", function(o) dragging[o] = true end)
			pcall(b.HookScript, b, "OnDragStop", function(o) dragging[o] = nil; if held[o] then ns.Soon(relayoutDrawer) end end)
		end
		-- LibDBIcon's fade timer and its minimap hooks set alpha; in the drawer it stays visible
		hooksecurefunc(b, "SetAlpha", function(o, a)
			if placing or not held[o] or o:GetParent() ~= drawer then return end
			if ns.Num(a) and a < 1 then placing = true; o:SetAlpha(1); placing = false end
		end)
		b:HookScript("OnShow", function(o) if held[o] then held[o].hiddenByOwner = nil; ns.Soon(relayoutDrawer) end end)
		b:HookScript("OnHide", function(o)
			if held[o] and o:GetParent() == drawer and drawer:IsShown() then held[o].hiddenByOwner = true; ns.Soon(relayoutDrawer) end
		end)
	end
	-- a LibDBIcon button its owner hid stays out of the grid
	if (type(b.db) == "table" and b.db.hide) or not b:IsShown() then info.hiddenByOwner = true end
end
M.Hold = hold

function M:CollectButtons()
	if self.buttonRival or mdb().buttons == "leave" then return end
	makeDrawer()
	local icon = libIcon()
	if icon and icon.GetButtonList then
		for _, name in ipairs(icon:GetButtonList()) do
			local b = icon:GetMinimapButton(name)
			if b and not mdb().ignore[b:GetName() or ""] then hold(b) end
		end
		if not self.iconCallback and icon.RegisterCallback then
			self.iconCallback = true
			icon.RegisterCallback(M, "LibDBIcon_IconCreated", function(_, b)
				ns.AfterCombat("minimap-buttons", function() if M.running and mdb().buttons ~= "leave" then hold(b); relayoutDrawer() end end)
			end)
		end
	end
	for _, parent in ipairs({ Minimap, MinimapBackdrop or false, MinimapCluster or false }) do
		if type(parent) == "table" and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if child ~= drawerToggle and M.IsAddonButton(child) then hold(child) end
			end
		end
	end
	relayoutDrawer()
	anchorDrawer()
end

-- Give the buttons back (mode changed to "leave", or a button put on the ignore list).
function M:ReleaseButtons(only)
	placing = true
	for i = #heldList, 1, -1 do
		local b = heldList[i]
		local name = b.GetName and b:GetName()
		if not only or only == name then
			local info = held[b]
			held[b] = nil
			table.remove(heldList, i)
			pcall(function()
				b:SetParent(info.parent)
				if info.strata then b:SetFrameStrata(info.strata) end
				if info.level then b:SetFrameLevel(info.level) end
				if info.fixedStrata and b.SetFixedFrameStrata then b:SetFixedFrameStrata(true) end
				if info.fixedLevel and b.SetFixedFrameLevel then b:SetFixedFrameLevel(true) end
				b:ClearAllPoints()
				for _, p in ipairs(info.points) do b:SetPoint(unpack(p)) end
				if info.drag and b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
				b.showOnMouseover = info.fade
				b:SetAlpha(info.alpha or 1)
			end)
		end
	end
	placing = false
	relayoutDrawer()
end

function M:Held() return heldList end

------------------------------------------------------------------------
-- Our own zone line over (or under) the minimap: the subzone you stand in, the zone, or both, coloured like the
-- game's zone text (sanctuary, friendly, hostile, contested).
------------------------------------------------------------------------
local zoneLabel
local zoneEvents = { name = ns.NAME .. " minimap zone" }
local PVP_COLORS = {
	sanctuary = { 0.41, 0.8, 0.94 }, friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 }, arena = { 1, 0.1, 0.1 },
	contested = { 1, 0.7, 0 }, combat = { 1, 0.1, 0.1 },
}

-- The text for a mode from the zone and subzone names (plain strings or nil). Pure.
function M.ZoneLabelText(mode, zone, sub)
	zone = (zone and zone ~= "") and zone or nil
	sub = (sub and sub ~= "") and sub or nil
	if mode == "zone" then return zone or sub or "" end
	if mode == "both" then
		if zone and sub and sub ~= zone then return zone .. ": " .. sub end
		return zone or sub or ""
	end
	return sub or zone or "" -- subzone, else the zone (open country has no subzone)
end

function M:UpdateZoneLabel()
	if not zoneLabel or not zoneLabel:IsShown() then return end
	local mode = mdb().zoneLabel
	local zone, sub = ns.Str(GetZoneText and GetZoneText()), ns.Str(GetSubZoneText and GetSubZoneText())
	zoneLabel:SetText(M.ZoneLabelText(mode, zone, sub))
	local pvp = ns.Str(GetZonePVPInfo and (GetZonePVPInfo()))
	local c = pvp and PVP_COLORS[pvp] or { 1, 0.82, 0 }
	zoneLabel:SetTextColor(c[1], c[2], c[3])
end

function M:ApplyZoneLabel()
	local db = mdb()
	local on = db.zoneLabel and db.zoneLabel ~= "off" and holder and not self.stepAside and self.running
	if not on then
		if zoneLabel then zoneLabel:Hide() end
		ns.OffAll(zoneEvents)
		return
	end
	if not zoneLabel then
		zoneLabel = holder:CreateFontString(ns.PREFIX .. "MinimapZoneLabel", "OVERLAY")
		U.SetFont(zoneLabel, 12, "OUTLINE")
		zoneLabel:SetJustifyH("CENTER")
		zoneLabel:SetWordWrap(false)
		M.zoneLabel = zoneLabel
	end
	zoneLabel:ClearAllPoints()
	zoneLabel:SetWidth((ns.Num(Minimap:GetWidth()) or 140) + 40)
	if db.zoneLabelPos == "bottom" then
		zoneLabel:SetPoint("TOP", Minimap, "BOTTOM", 0, -5)
	else
		zoneLabel:SetPoint("BOTTOM", Minimap, "TOP", 0, 5)
	end
	zoneLabel:Show()
	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, zoneEvents, function() M:UpdateZoneLabel() end)
	end
	self:UpdateZoneLabel()
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function M:ApplyAll()
	-- the minimap frame and the addon buttons wait for combat to end; the settings page says so meanwhile (a piece
	-- switched on or off does not come through here: it changes at once, see the piece settings)
	M.frameWaiting = InCombatLockdown() and true or nil
	ns.AfterCombat("minimap-all", function()
		local waited = M.frameWaiting
		M.frameWaiting = nil
		if not M.running then return end
		M:ApplyFrame()
		M:ApplyElements()
		M:CollectButtons()
		if waited and ns.Options then ns.Options:Refresh() end
	end)
end

-- Another addon manages the minimap or its buttons: said once ever per addon; after that the minimap page and
-- /ebar status say it.
function M:TellRivals()
	if M.stepAside and ns.TellOnce("stepAside:" .. M.stepAside) then
		ns:Print(M.stepAside .. " is managing the minimap, so " .. ns.NAME .. " leaves the minimap frame alone. "
			.. "To use " .. ns.NAME .. "'s clean minimap instead, disable " .. M.stepAside .. " (Esc > AddOns) and /reload. "
			.. "This is said once; " .. ns.SLASH .. " status shows it again.")
	end
	if M.buttonRival and ns.TellOnce("buttons:" .. M.buttonRival) then
		ns:Print(M.buttonRival .. " already collects minimap buttons, so " .. ns.NAME .. " leaves them to it.")
	end
end

function M:Enable()
	if not Minimap then return end
	local function start()
		M:DetectRivals()
		M:TellRivals()
		M:ApplyAll()
		-- other addons' coordinate features: say once which setting turns them off
		C_Timer.After(5, function() if M.running then M:TellForeignCoords() end end)
	end
	mdb().drawerPos = nil -- the drawer is no longer dragged anywhere: it opens beside its button
	if IsLoggedIn and IsLoggedIn() then start() else ns.On("PLAYER_LOGIN", self, start) end
	-- a new resolution or UI scale: keep the minimap on screen (the saved centre is clamped when applied)
	for _, e in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
		ns.On(e, self, function() ns.AfterCombat("minimap-frame", function() if M.running then M:ApplyFrame() end end) end)
	end
	-- combat starts: drop what is being dragged where it is and lock
	ns.On("PLAYER_REGEN_DISABLED", self, function()
		if M.unlocked then
			M:SetUnlocked(false, true)
			ns.SayLockedForCombat()
		end
	end)
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
	self:SetUnlocked(false, true)
	if ns.Unlock and ns.Unlock.active then ns.Unlock:PlacePanel(); ns.Unlock:SyncMovers() end
	self:ApplyZoneLabel()
	for obj in pairs(taken) do restore(obj) end
	self:ReleaseButtons()
	if drawerToggle then drawerToggle:Hide() end
	if drawer then drawer:Hide() end
	-- no chat line: the minimap page says it ("Off. Turning it off fully gives the minimap back after /reload.")
end

-- The settings that move or reshape the minimap changed.
function M:Redraw()
	if not self.running then return end
	self:ApplyAll()
end
