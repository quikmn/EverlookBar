-- EverlookDB Bar: the taskbar's window manager. It finds the windows that are open, remembers the ones minimized
-- from the taskbar, and snaps, maximizes and tiles the ones it may move.
--
-- Three kinds of windows:
--   ours      every EverlookDB window (EverlookUI lists them in UI.windows): minimize, restore, snap, tile, close and
--             drag-to-edge snapping, all of it;
--   blizzard  the game's panels (by name, and everything in UIPanelWindows): listed, raised, and opened and closed
--             only through the game's own buttons (a secure click, SecureClick.lua), so nothing of the game's runs
--             tainted. They are never moved: the game's panel layout (and addons that move panels) own their place;
--   other     other addons' windows (shown, named, movable, with a close button or a title): minimize, restore, snap
--             and tile, never while they are protected in combat.
-- Anything the game protects is never touched in combat: such actions wait (Tiling.NewQueue) and run when it ends.
-- Nothing here closes a window by itself; a window is hidden only when the player picks Minimize or Close.
local _, ns = ...
local UI = ns.UI
local Tiling = ns.Tiling

local WM = { recs = {}, byFrame = {}, running = false }
ns.WM = WM
local queue = Tiling.NewQueue()
WM.queue = queue

------------------------------------------------------------------------
-- The game's windows we know by name: a title, a line icon and the buttons that open and close them securely.
------------------------------------------------------------------------
local function G(title, icon, toggle) return { title = title, icon = icon, toggle = toggle } end
WM.BLIZZARD = {
	CharacterFrame = G(CHARACTER_BUTTON or "Character", "user", { "CharacterMicroButton" }),
	SpellBookFrame = G("Spellbook", "book", { "SpellbookMicroButton" }),
	PlayerSpellsFrame = G("Spellbook and talents", "book", { "PlayerSpellsMicroButton", "SpellbookMicroButton" }),
	PlayerTalentFrame = G("Talents", "sparkle", { "TalentMicroButton" }),
	ClassTalentFrame = G("Talents", "sparkle", { "TalentMicroButton" }),
	TalentFrame = G("Talents", "sparkle", { "TalentMicroButton" }),
	ProfessionsFrame = G("Professions", "hammer", { "ProfessionMicroButton" }),
	ProfessionsBookFrame = G("Professions", "hammer", { "ProfessionMicroButton" }),
	TradeSkillFrame = G("Profession", "hammer"),
	CraftFrame = G("Profession", "hammer"),
	QuestLogFrame = G("Quest log", "scroll", { "QuestLogMicroButton" }),
	WorldMapFrame = G("Map", "map", { "WorldMapMicroButton" }),
	FriendsFrame = G("Friends", "chat", { "SocialsMicroButton", "FriendsMicroButton", "QuickJoinToastButton" }),
	GuildFrame = G("Guild", "shield", { "GuildMicroButton" }),
	CommunitiesFrame = G("Guild and communities", "shield", { "GuildMicroButton" }),
	ContainerFrameCombinedBags = G("Bags", "bag", { "MainMenuBarBackpackButton" }),
	ContainerFrame1 = G("Backpack", "bag", { "MainMenuBarBackpackButton" }),
	MacroFrame = G("Macros", "keyboard"),
	KeyBindingFrame = G("Key bindings", "keyboard"),
	SettingsPanel = G("Settings", "gear"),
	AchievementFrame = G("Achievements", "star", { "AchievementMicroButton" }),
	CollectionsJournal = G("Collections", "paw", { "CollectionsMicroButton" }),
	PVEFrame = G("Group finder", "user", { "LFDMicroButton", "GroupFinderMicroButton", "LFGMicroButton" }),
	EncounterJournal = G("Adventure guide", "book", { "EJMicroButton" }),
	CalendarFrame = G("Calendar", "clock", { "GameTimeFrame" }),
	MerchantFrame = G("Merchant", "coins"),
	MailFrame = G("Mail", "note"),
	BankFrame = G("Bank", "bag"),
	AuctionHouseFrame = G("Auction house", "coins"),
	AuctionFrame = G("Auction house", "coins"),
	GossipFrame = G("Gossip", "chat"),
	QuestFrame = G("Quest", "scroll"),
	TaxiFrame = G("Flight map", "map"),
	ClassTrainerFrame = G("Trainer", "book"),
	AddonList = G("AddOns", "puzzle"),
}
-- Never listed: the game menu (Escape), full-screen and HUD frames.
WM.NEVER = { GameMenuFrame = true, UIParent = true, WorldFrame = true, StaticPopup1 = true, StaticPopup2 = true,
	StaticPopup3 = true, ItemRefTooltip = true, ChatConfigFrame = true, ColorPickerFrame = true, CinematicFrame = true,
	MovieFrame = true, LootFrame = true, GroupLootFrame1 = true, MinimapCluster = true, PlayerFrame = true,
	TargetFrame = true, FocusFrame = true, BuffFrame = true, ObjectiveTrackerFrame = true, QuestWatchFrame = true }
-- Name parts of HUD frames (unit frames, action bars, alerts...): never another addon's window.
local HUD_WORDS = { "Bar", "Unit", "Nameplate", "NamePlate", "Raid", "Party", "Compact", "Chat", "Minimap", "Buff",
	"Aura", "Cast", "Tooltip", "Action", "Micro", "Objective", "Tracker", "Alert", "Toast", "Talking", "Boss", "Arena",
	"Totem", "Status", "Vehicle", "Cooldown", "Mover", "Anchor", "Drag", "Nudge", "Grid", "Popup", "Dropdown", "DropDown" }

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local WINDOW_STRATA = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }

local function db() return ns.db and ns.db.taskbar end
local function num(v) return ns.Num(v) end
local function screen()
	return num(UIParent:GetWidth()) or 1920, num(UIParent:GetHeight()) or 1080
end
local function forbidden(f) return f.IsForbidden and f:IsForbidden() end
local function nameOf(f)
	local ok, n = pcall(f.GetName, f)
	return ok and ns.Str(n) or nil
end
local function isFontString(x)
	return type(x) == "table" and type(x.GetText) == "function" and type(x.GetObjectType) == "function"
		and x:GetObjectType() == "FontString"
end
local function textOf(x)
	if not isFontString(x) then return nil end
	local t = ns.Str(x:GetText())
	if t and t ~= "" then return t end
end

-- The work area: the screen minus the bars docked to its edges.
function WM:WorkArea()
	local W, H = screen()
	return Tiling.WorkArea(ns.db and ns.db.bars or {}, W, H)
end
function WM:Gap() return db() and tonumber(db().gap) or 4 end

------------------------------------------------------------------------
-- Which kind a frame is, and whether it is a window to list
------------------------------------------------------------------------
function WM:KindOf(f)
	if UI.windows and UI.windows[f] then return "ours" end
	local n = nameOf(f)
	if n and (WM.BLIZZARD[n] or (type(UIPanelWindows) == "table" and UIPanelWindows[n])) then return "blizzard" end
	return "other"
end

local function closeButtonOf(f, n)
	for _, k in ipairs({ "CloseButton", "closeButton", "close", "Close" }) do
		local c = rawget(f, k)
		if type(c) == "table" and c.Click then return c end
	end
	if n then
		local c = _G[n .. "CloseButton"] or _G[n .. "Close"]
		if type(c) == "table" and c.Click then return c end
	end
end

local function titleTextOf(f, n)
	local t = textOf(rawget(f, "TitleText")) or textOf(rawget(f, "title")) or textOf(rawget(f, "titleText"))
		or textOf(rawget(f, "Title"))
	if t then return t end
	local tc = rawget(f, "TitleContainer")
	if type(tc) == "table" then t = textOf(rawget(tc, "TitleText")) if t then return t end end
	if n then return textOf(_G[n .. "TitleText"]) or textOf(_G[n .. "Title"]) end
end
WM.TitleTextOf = titleTextOf

local function bigEnough(f, minW, minH)
	local w, h = num(f:GetWidth()), num(f:GetHeight())
	if not w or not h then return false end
	local k = (num(f:GetEffectiveScale()) or 1) / (num(UIParent:GetEffectiveScale()) or 1)
	w, h = w * k, h * k
	local W, H = screen()
	return w >= minW and h >= minH and w <= W * 1.01 and h <= H * 1.01
end

-- A shown frame that belongs on the taskbar?
function WM:Eligible(f, kind)
	if type(f) ~= "table" or forbidden(f) or not f.IsShown then return false end
	local n = nameOf(f)
	if n and (WM.NEVER[n] or (db() and db().ignore[n])) then return false end
	if ns.StartMenu and f == ns.StartMenu.frame then return false end
	kind = kind or self:KindOf(f)
	if kind == "ours" then
		local info = UI.windows[f]
		if info.noTaskbar then return false end
		if f:GetParent() ~= UIParent then return false end
		if not (f.IsMovable and f:IsMovable()) then return false end
		return bigEnough(f, 160, 100)
	elseif kind == "blizzard" then
		if db() and db().blizzard == false then return false end
		if n and n:match("^ContainerFrame%d") and n ~= "ContainerFrame1" then return false end
		return bigEnough(f, 60, 60)
	end
	-- another addon's window: named, shown, takes the mouse, movable, not protected, a window's size and layer, and
	-- with a close button or a title
	if db() and db().others == false then return false end
	if not n or n:find("^" .. ns.PREFIX) then return false end
	for _, w in ipairs(HUD_WORDS) do if n:find(w, 1, true) then return false end end
	if f:GetParent() ~= UIParent then return false end
	if not (f.IsMouseEnabled and f:IsMouseEnabled()) then return false end
	if not (f.IsMovable and f:IsMovable()) then return false end
	if f.IsProtected and f:IsProtected() then return false end
	if not WINDOW_STRATA[f:GetFrameStrata() or ""] then return false end
	if not bigEnough(f, 220, 150) then return false end
	return closeButtonOf(f, n) ~= nil or titleTextOf(f, n) ~= nil
end

------------------------------------------------------------------------
-- Titles and icons
------------------------------------------------------------------------
local function prettyName(n)
	n = tostring(n or "Window"):gsub("Frame$", ""):gsub("Window$", ""):gsub("_", " ")
	n = n:gsub("(%l)(%u)", "%1 %2")
	return n ~= "" and n or "Window"
end

function WM:Title(rec)
	local f, n = rec.frame, nameOf(rec.frame)
	if rec.kind == "ours" then
		local info = UI.windows[f] or {}
		local t = info.title
		if type(t) == "function" then local ok, v = pcall(t, f); t = ok and v or nil end
		if type(t) == "string" and t ~= "" then return t end
		t = titleTextOf(f, n)
		if t then return t end
		if info.app and info.app.name then return info.app.name end
		return prettyName(n)
	elseif rec.kind == "blizzard" then
		local b = n and WM.BLIZZARD[n]
		-- a profession window says which profession it is; the others go by their usual names
		if b and b.icon ~= "hammer" then return b.title end
		return titleTextOf(f, n) or (b and b.title) or prettyName(n)
	end
	return titleTextOf(f, n) or prettyName(n)
end

-- { icon = name-or-texture } or { tex = texture, coords = { l, r, t, b } } (copied from the window's own icon).
function WM:Icon(rec)
	local f = rec.frame
	if rec.kind == "ours" then
		local info = UI.windows[f] or {}
		if info.icon then return { icon = info.icon } end
		local app = info.app
		if app then
			local icon = app.spec and app.spec.icon
			if not icon and app.spec and app.spec.addon then
				local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
				icon = get and get(app.spec.addon, "IconTexture")
			end
			if icon then return { icon = icon } end
		end
		local t = rawget(f, "icon")
		if type(t) == "table" and t.GetObjectType and t:GetObjectType() == "Texture" and t.GetTexture then
			local tex = t:GetTexture()
			if tex then
				local l, tt, _, b, r = 0, 0, 0, 1, 1
				if t.GetTexCoord then
					local a1, a2, a3, a4, a5, a6, a7, a8 = t:GetTexCoord()
					if a8 then l, tt, r, b = a1, a2, a7, a8 elseif a4 then l, r, tt, b = a1, a2, a3, a4 end
				end
				return { tex = tex, coords = { l or 0, r or 1, tt or 0, b or 1 } }
			end
		end
		return { icon = "frames" }
	elseif rec.kind == "blizzard" then
		local b = WM.BLIZZARD[nameOf(f) or ""]
		return { icon = b and b.icon or "frames" }
	end
	return { icon = "frames" }
end

-- The game's button that opens and closes a Blizzard window (a micro button), if it has one.
function WM:Toggle(rec)
	if rec.kind ~= "blizzard" then return nil end
	local b = WM.BLIZZARD[nameOf(rec.frame) or ""]
	for _, name in ipairs(b and b.toggle or {}) do
		local btn = ns.SecureClick.Button(name)
		if btn then return btn end
	end
end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------
local hooked = setmetatable({}, { __mode = "k" })
local function dirty() if WM.running then ns.Soon(WM.Scan, WM) end end
WM.Dirty = dirty

-- Show/hide hooks (HookScript runs after the frame's own script and never changes how the game runs it), and for our
-- own windows the drag hooks for snapping to the screen's edges. Out of combat only.
function WM:Hook(f, kind)
	if hooked[f] or InCombatLockdown() or forbidden(f) then return end
	hooked[f] = true
	f:HookScript("OnShow", dirty)
	f:HookScript("OnHide", dirty)
	if kind == "ours" then
		f:HookScript("OnDragStart", function(self) WM:DragStart(self) end)
		f:HookScript("OnDragStop", function(self) WM:DragStop(self) end)
	end
end

function WM:Get(f) return self.byFrame[f] end

local function add(self, f, kind)
	local rec = { frame = f, kind = kind, key = nameOf(f) or tostring(f) }
	self.byFrame[f] = rec
	self.recs[#self.recs + 1] = rec
	return rec
end

local function remove(self, rec)
	self.byFrame[rec.frame] = nil
	for i, r in ipairs(self.recs) do if r == rec then table.remove(self.recs, i) break end end
	queue:Drop(rec.key .. ":vis"); queue:Drop(rec.key .. ":geo"); queue:Drop(rec.key .. ":raise")
end

local scanList, scanKinds, scanSeen = {}, {}, {}
-- (no closures or tables made per scan: it runs four times a second)
local function take(f, kind)
	if type(f) == "table" and type(f.IsShown) == "function" and not scanSeen[f] then
		scanSeen[f] = true
		scanList[#scanList + 1] = f
		scanKinds[f] = kind
	end
end
local function takeAll(f, ...)
	if f == nil then return end
	take(f, nil)
	return takeAll(...)
end

-- Every frame that could be a window: ours, the game's (by name and UIPanelWindows), and with `full` the children of
-- UIParent (other addons' windows).
function WM:Candidates(full)
	for i = #scanList, 1, -1 do scanList[i] = nil end
	wipe(scanKinds)
	wipe(scanSeen)
	for f in pairs(UI.windows or {}) do take(f, "ours") end
	for n in pairs(WM.BLIZZARD) do take(_G[n], nil) end
	if type(UIPanelWindows) == "table" then for n in pairs(UIPanelWindows) do take(_G[n], nil) end end
	for _, rec in ipairs(self.recs) do take(rec.frame, rec.kind) end
	if full and UIParent.GetChildren then takeAll(UIParent:GetChildren()) end
	return scanList
end

-- Look again at every window: new ones get a button, closed ones lose theirs (a minimized one keeps it). In combat
-- nothing is taken off (the buttons stay where they are, their secure clicks too); that waits for combat's end.
function WM:Scan(full)
	if not self.running then return end
	local combat = InCombatLockdown()
	local changed = false
	for _, f in ipairs(self:Candidates(full)) do
		local kind = scanKinds[f] or self:KindOf(f)
		if kind ~= "other" or self.byFrame[f] or full then
			local shown = f:IsShown() and f:IsVisible()
			local rec = self.byFrame[f]
			if shown then
				if not rec and self:Eligible(f, kind) then
					rec = add(self, f, kind)
					changed = true
				end
				if rec then
					if rec.minimized or rec.gone then changed = true end
					rec.minimized, rec.minimizing, rec.gone = false, nil, nil
					if kind ~= "other" then self:Hook(f, kind) end
				end
			elseif rec then
				if rec.minimizing then rec.minimized, rec.minimizing = true, nil; changed = true end
				if not rec.minimized and not rec.gone then
					if combat then rec.gone = true else remove(self, rec) end
					changed = true
				end
			elseif kind ~= "other" then
				self:Hook(f, kind) -- hidden now: hear when it opens
			end
		end
	end
	if not combat then
		for i = #self.recs, 1, -1 do
			local rec = self.recs[i]
			if rec.gone then remove(self, rec); changed = true end
		end
	end
	local active = self:Active()
	if active ~= self.lastActive then self.lastActive = active; changed = true end
	if changed and self.onChange then ns.SafeCall(ns.Taskbar, self.onChange) end
	return changed
end

-- The cheap look, four times a second: did a listed window open or close, or another come to the front?
function WM:Changed()
	for _, rec in ipairs(self.recs) do
		local shown = rec.frame:IsShown() and true or false
		if shown == (rec.minimized or rec.gone or false) then return true end
	end
	return self:Active() ~= self.lastActive
end

-- The window in front: the highest layer and level among the shown ones.
function WM:Active()
	local best, bestV
	for _, rec in ipairs(self.recs) do
		local f = rec.frame
		if not rec.minimized and not rec.gone and f:IsShown() then
			local v = (STRATA[f:GetFrameStrata() or ""] or 3) * 100000 + (num(f:GetFrameLevel()) or 0)
			if not bestV or v > bestV then best, bestV = rec, v end
		end
	end
	return best
end

------------------------------------------------------------------------
-- Running (only while the taskbar is on)
------------------------------------------------------------------------
local ticks = 0
function WM:Start()
	if self.running then return end
	self.running = true
	if not self.listening then
		self.listening = true
		UI.OnWindowRegistered(function() dirty() end)
	end
	self.task = self.task or ns.Every(self, 0.25, function()
		ticks = ticks + 1
		if ticks % 8 == 0 then WM:Scan(true) -- other addons' windows: every 2 seconds
		elseif WM:Changed() then WM:Scan(false) end
	end)
	self.task:SetActive(true)
	ns.On("ADDON_LOADED", self, dirty) -- the game's panels load later (Blizzard_* addons)
	ns.On("PLAYER_REGEN_ENABLED", self, function() WM:CombatEnded() end)
	self:Scan(true)
end

function WM:Stop()
	if not self.running then return end
	self:RestoreAll()
	self.running = false
	if self.task then self.task:SetActive(false) end
	ns.Off("ADDON_LOADED", self)
	ns.Off("PLAYER_REGEN_ENABLED", self)
	self:DragCancel()
	wipe(self.recs); wipe(self.byFrame)
end

------------------------------------------------------------------------
-- Actions. Anything protected in combat waits until combat ends (one entry per window and kind of action: the newest
-- wins), and the player hears so once per fight.
------------------------------------------------------------------------
local toldWait = false
local function blocked(rec)
	if not InCombatLockdown() then return false end
	local f = rec.frame
	return rec.kind == "blizzard" or (f.IsProtected and f:IsProtected()) and true or false
end

function WM:Do(rec, what, fn)
	if blocked(rec) then
		queue:Add(rec.key .. ":" .. what, function() if WM.byFrame[rec.frame] == rec then fn() end end)
		if not toldWait then
			toldWait = true
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage(ns.NAME .. ": that window changes when combat ends.", 1, 0.82, 0.3)
			end
		end
		return false
	end
	fn()
	return true
end

function WM:CombatEnded()
	toldWait = false
	queue:Run(function(fn) ns.SafeCall(WM, fn) end)
	self:Scan(true)
end

function WM:CanMinimize(rec)
	if rec.kind == "blizzard" then return false end -- only through its own button (the taskbar's secure click)
	return true
end
function WM:CanMove(rec)
	if rec.kind == "blizzard" then return false end
	local f = rec.frame
	return f.IsMovable and f:IsMovable() and true or false
end
WM.CanClose = WM.CanMinimize

function WM:Minimize(rec)
	if not rec or not self:CanMinimize(rec) or rec.minimized then return false end
	return self:Do(rec, "vis", function()
		local f = rec.frame
		if self.drag and self.drag.rec == rec then self:DragCancel() end
		rec.minimized = true
		f.eluiMinimizing = true
		f:Hide()
		f.eluiMinimizing = nil
		dirty()
	end)
end

function WM:Restore(rec)
	if not rec or rec.kind == "blizzard" then return false end
	return self:Do(rec, "vis", function()
		rec.minimized = false
		rec.frame:Show()
		if rec.frame.Raise then rec.frame:Raise() end
		dirty()
	end)
end

function WM:Raise(rec)
	if not rec then return false end
	return self:Do(rec, "raise", function()
		if rec.frame.Raise then rec.frame:Raise() end
		self.lastActive = nil
		dirty()
	end)
end

-- A taskbar button's click (not the secure one): restore a minimized window, minimize the one in front, raise another.
function WM:Activate(rec)
	if not rec then return false end
	if rec.minimized or rec.gone then return self:Restore(rec) end
	if self:Active() == rec and self:CanMinimize(rec) then return self:Minimize(rec) end
	return self:Raise(rec)
end

function WM:Close(rec)
	if not rec or not self:CanClose(rec) then return false end
	return self:Do(rec, "vis", function()
		rec.minimized = false
		rec.frame:Hide()
		dirty()
	end)
end

-- Where a window is: its anchors and size, to put back exactly.
function WM.Geometry(f)
	local g = { points = {}, w = num(f:GetWidth()), h = num(f:GetHeight()) }
	for i = 1, (num(f:GetNumPoints()) or 0) do g.points[i] = { f:GetPoint(i) } end
	return g
end

function WM.SetGeometry(f, g)
	if not g then return end
	if #g.points > 0 then
		f:ClearAllPoints()
		for _, p in ipairs(g.points) do f:SetPoint(p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0) end
	end
	if g.w and g.h and f.IsResizable and f:IsResizable() then f:SetSize(g.w, g.h) end
end

-- Put a window into `rect` (UIParent units), within its own size limits.
function WM:Place(rec, rect)
	local f = rec.frame
	local k = (num(UIParent:GetEffectiveScale()) or 1) / (num(f:GetEffectiveScale()) or 1)
	local resizable = f.IsResizable and f:IsResizable() and true or false
	local win = { w = (num(f:GetWidth()) or rect.w * k) / k, h = (num(f:GetHeight()) or rect.h * k) / k, resizable = resizable }
	if resizable and f.GetResizeBounds then
		local a, b, c, d = f:GetResizeBounds()
		win.minW, win.minH = num(a) and num(a) / k, num(b) and num(b) / k
		win.maxW, win.maxH = num(c) and num(c) / k, num(d) and num(d) / k
	end
	local W, H = screen()
	local r = Tiling.Fit(rect, win, W, H)
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r.x * k, r.y * k)
	if resizable then f:SetSize(r.w * k, r.h * k) end
	return r
end

-- Snap a window to a layout (Tiling.ZONES): its place before is kept for Restore size.
function WM:Snap(rec, zone)
	if not rec or not self:CanMove(rec) or not Tiling.ZONE[zone] then return false end
	return self:Do(rec, "geo", function()
		if rec.minimized then rec.minimized = false; rec.frame:Show() end
		if not rec.snap then rec.restore = WM.Geometry(rec.frame) end
		self:Place(rec, Tiling.SnapRect(zone, self:WorkArea(), self:Gap()))
		rec.snap = zone
		if rec.frame.Raise then rec.frame:Raise() end
		dirty()
	end)
end

function WM:Unsnap(rec)
	if not rec or not rec.snap then return false end
	return self:Do(rec, "geo", function()
		WM.SetGeometry(rec.frame, rec.restore)
		rec.snap, rec.restore = nil, nil
		dirty()
	end)
end

function WM:ToggleMaximize(rec)
	if rec and rec.snap == "max" then return self:Unsnap(rec) end
	return self:Snap(rec, "max")
end

-- The windows Tile all arranges: open (not minimized), movable, in taskbar order.
function WM:Tileable()
	local list = {}
	for _, rec in ipairs(self.recs) do
		if not rec.minimized and not rec.gone and rec.frame:IsShown() and self:CanMove(rec) then list[#list + 1] = rec end
	end
	return list
end

function WM:TileAll()
	local list = self:Tileable()
	local rects = Tiling.TileRects(#list, self:WorkArea(), self:Gap())
	for i, rec in ipairs(list) do
		self:Do(rec, "geo", function()
			if not rec.snap then rec.restore = WM.Geometry(rec.frame) end
			self:Place(rec, rects[i])
			rec.snap = "tile"
		end)
	end
	dirty()
	return #list
end

function WM:MinimizeAll()
	local n = 0
	for _, rec in ipairs(self.recs) do
		if not rec.minimized and self:CanMinimize(rec) and rec.frame:IsShown() then
			self:Minimize(rec); n = n + 1
		end
	end
	return n
end

function WM:RestoreAll()
	local n = 0
	for _, rec in ipairs(self.recs) do
		if rec.minimized and rec.kind ~= "blizzard" then self:Restore(rec); n = n + 1 end
	end
	return n
end

-- Stop listing a window (named ones, saved): "Don't list this window".
function WM:Ignore(rec)
	local n = nameOf(rec.frame)
	if not n or rec.kind == "ours" then return false end
	db().ignore[n] = true
	if rec.minimized then self:Restore(rec) end
	remove(self, rec)
	if self.onChange then ns.SafeCall(ns.Taskbar, self.onChange) end
	return true
end

------------------------------------------------------------------------
-- Drag to an edge: one of our windows dragged with the cursor at the screen's top edge maximizes, at the left or
-- right edge takes that half, in a corner a quarter. A faint preview shows where it goes. A snapped window that is
-- dragged gets its old size back.
------------------------------------------------------------------------
local preview
local function cursor()
	local x, y = GetCursorPosition()
	local s = num(UIParent:GetEffectiveScale()) or 1
	return (num(x) or 0) / s, (num(y) or 0) / s
end

local function makePreview()
	preview = CreateFrame("Frame", ns.PREFIX .. "SnapPreview", UIParent)
	preview:SetFrameStrata("HIGH")
	preview:EnableMouse(false)
	local T = ns.TaskTheme or UI.Theme
	local a = T.accent
	preview.fill = ns.Util.Solid(preview, "BACKGROUND", a[1], a[2], a[3], 0.12)
	preview.fill:SetAllPoints()
	preview.edge = ns.Util.Border(preview, 2, a[1], a[2], a[3], 0.55)
	preview:Hide()
	preview:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		if self.t < 0.05 then return end
		self.t = 0
		WM:DragTick()
	end)
end

function WM:DragStart(f)
	if not self.running or not (db() and db().snap) then return end
	local rec = self.byFrame[f]
	if not rec then return end
	self.drag = { rec = rec, from = rec.snap and rec.restore or WM.Geometry(f) }
	if rec.snap then
		-- off its snap: back to its own size, under the cursor
		local g = rec.restore
		if g and g.w and g.h and f.IsResizable and f:IsResizable() then f:SetSize(g.w, g.h) end
		rec.snap, rec.restore = nil, nil
	end
	if not preview then makePreview() end
	preview.zone = nil
	preview:SetAlpha(0)
	preview:Show()
end

function WM:DragTick()
	local d = self.drag
	if not d then preview:Hide() return end
	local W, H = screen()
	local cx, cy = cursor()
	local zone = Tiling.DragZone(cx, cy, W, H)
	if zone ~= preview.zone then
		preview.zone = zone
		if zone then
			local r = Tiling.SnapRect(zone, self:WorkArea(), self:Gap())
			preview:ClearAllPoints()
			preview:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r.x, r.y)
			preview:SetSize(r.w, r.h)
			preview:SetAlpha(1)
		else
			preview:SetAlpha(0)
		end
	end
end

function WM:DragStop(f)
	local d = self.drag
	if not d or d.rec.frame ~= f then return end
	self:DragTick()
	local zone = preview and preview.zone
	self:DragCancel()
	if zone then
		local rec = d.rec
		self:Place(rec, Tiling.SnapRect(zone, self:WorkArea(), self:Gap()))
		rec.snap, rec.restore = zone, d.from
		dirty()
	end
end

function WM:DragCancel()
	self.drag = nil
	if preview then preview.zone = nil; preview:Hide() end
end
function WM:Preview() return preview end -- tests
