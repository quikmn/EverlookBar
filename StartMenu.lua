-- EverlookDB Bar: the Start menu. Every window you can open in one list: the EverlookDB addons (their windows, pages
-- and main views), the game's panels, your professions and every addon launcher (LibDataBroker). A search box at the
-- top (type to filter, Enter opens the first), pinned favourites and the ones used lately.
-- The game's panels open through the game's own buttons: a row that opens one gets the bar's secure click
-- (SecureClick.lua) while the mouse is on it. Enter on such a row (a key press can't click securely) arms Enter
-- once more for that row: the second Enter opens it. In combat they open with their own keys; the menu closes when
-- combat starts.
local _, ns = ...
local UI, U = ns.UI, ns.Util
local S = ns.SecureClick
local rgba = U.rgba

local SM = { rows = {}, tiles = {}, heads = {} }
ns.StartMenu = SM

local W, H = 460, 560
local ROW_H, TILE_W, TILE_H = 26, 82, 66
local MAX_RECENT, MAX_RESULTS = 6, 40

local function db() return ns.db.taskbar end
local function theme() return ns.TaskTheme or UI.Theme end

------------------------------------------------------------------------
-- What the menu lists
------------------------------------------------------------------------
-- The game's own button for a panel, as a secure click (the first of `names` the game has).
local function clickAny(names)
	return function()
		for _, n in ipairs(names) do
			local b = S.Button(n)
			if b then return { type = "click", clickbutton = b } end
		end
	end
end
local function call(name, ...)
	local fn = _G[name]
	if type(fn) == "function" then return fn(...) end
end
local function loadUI(addon)
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then pcall(load, addon) end
end

-- id, title, icon, keywords; secure: the game's button (opens and closes it securely); fallback: a plain way out of
-- combat, used only when the game has no such button. run: entries that need no secure click at all.
SM.GAME = {
	{ id = "game:character", title = CHARACTER_BUTTON or "Character", icon = "user", secure = clickAny({ "CharacterMicroButton" }),
		keywords = { "gear", "equipment", "stats", "paper", "doll", "character" } },
	{ id = "game:reputation", title = REPUTATION or "Reputation", icon = "flag", keywords = { "factions", "standing" },
		secure = function() if S.Button("CharacterMicroButton") then return S.CharacterPanelOn(REPUTATION or "Reputation")() end end },
	{ id = "game:spellbook", title = "Spellbook", icon = "book", keywords = { "spells", "abilities" },
		secure = clickAny({ "SpellbookMicroButton", "PlayerSpellsMicroButton" }) },
	{ id = "game:talents", title = TALENTS or "Talents", icon = "sparkle", keywords = { "talent", "specialization", "spec" },
		secure = clickAny({ "TalentMicroButton", "PlayerSpellsMicroButton" }) },
	{ id = "game:professions", title = "Professions", icon = "hammer", keywords = { "trade", "skills", "crafting" },
		secure = clickAny({ "ProfessionMicroButton" }) },
	{ id = "game:quests", title = "Quest log", icon = "scroll", keywords = { "quests", "log" },
		secure = clickAny({ "QuestLogMicroButton" }), fallback = function() call("ToggleQuestLog") end },
	{ id = "game:map", title = WORLD_MAP or "World map", icon = "map", keywords = { "map", "world", "zone" },
		secure = clickAny({ "WorldMapMicroButton" }), fallback = function() call("ToggleWorldMap") end },
	{ id = "game:friends", title = FRIENDS or "Friends", icon = "chat", keywords = { "social", "who", "ignore" },
		secure = clickAny({ "SocialsMicroButton", "FriendsMicroButton", "QuickJoinToastButton" }),
		fallback = function() call("ToggleFriendsFrame") end },
	{ id = "game:guild", title = GUILD or "Guild", icon = "shield", keywords = { "communities", "roster" },
		secure = clickAny({ "GuildMicroButton" }), fallback = function() call("ToggleGuildFrame") end },
	{ id = "game:bags", title = "Bags", icon = "bag", keywords = { "inventory", "backpack", "items" },
		secure = clickAny({ "MainMenuBarBackpackButton" }),
		fallback = function() if ToggleAllBags then ToggleAllBags() else call("ToggleBackpack") end end },
	{ id = "game:achievements", title = ACHIEVEMENTS or "Achievements", icon = "star", secure = clickAny({ "AchievementMicroButton" }) },
	{ id = "game:collections", title = COLLECTIONS or "Collections", icon = "paw", keywords = { "mounts", "pets", "toys" },
		secure = clickAny({ "CollectionsMicroButton" }) },
	{ id = "game:groupfinder", title = "Group finder", icon = "user", keywords = { "dungeon", "lfg", "lfd", "raid" },
		secure = clickAny({ "LFDMicroButton", "GroupFinderMicroButton", "LFGMicroButton" }) },
	{ id = "game:journal", title = "Adventure guide", icon = "book", keywords = { "dungeon", "journal", "encounter" },
		secure = clickAny({ "EJMicroButton" }) },
	{ id = "game:calendar", title = "Calendar", icon = "clock", keywords = { "events", "date" },
		secure = clickAny({ "GameTimeFrame" }), fallback = function() if ns.OpenCalendar then ns.OpenCalendar() end end },
	{ id = "game:macros", title = MACROS or "Macros", icon = "keyboard", keywords = { "macro" },
		run = function()
			loadUI("Blizzard_MacroUI")
			if ShowMacroFrame then ShowMacroFrame() elseif MacroFrame then MacroFrame:Show() end
		end },
	{ id = "game:keybindings", title = KEY_BINDINGS or "Key bindings", icon = "keyboard", keywords = { "keys", "binds", "hotkeys" },
		run = function()
			if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
				Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
			else
				loadUI("Blizzard_BindingUI")
				if KeyBindingFrame then KeyBindingFrame:Show() end
			end
		end },
	{ id = "game:settings", title = SETTINGS or "Settings", icon = "gear", keywords = { "options", "interface", "video", "sound" },
		run = function()
			if SettingsPanel and SettingsPanel.Open then SettingsPanel:Open()
			elseif Settings and Settings.OpenToCategory then Settings.OpenToCategory() end
		end },
	{ id = "game:menu", title = MAINMENU_BUTTON or "Game menu", icon = "list", keywords = { "logout", "exit", "escape" },
		secure = clickAny({ "MainMenuMicroButton" }) },
}

-- More views of EverlookDB addons, by addon folder: { command, title, icon } run as "/x command".
SM.EXTRAS = {
	EverlookDBCrafting = { { "recipes", "Recipe browser", "book" }, { "list", "Crafting list", "list" },
		{ "plan", "Skill-up planner", "hammer" }, { "favor", "Merchant's Favor", "bag" }, { "guide", "Profession guide", "scroll" } },
	EverlookPets = { { "beasts", "Bestiary", "paw" }, { "recent", "Pet messages", "clock" } },
	EverlookDBAuctions = { { "loot", "Loot log", "bag" }, { "forsale", "Up for sale", "coins" }, { "income", "Income", "coins" },
		{ "bought", "Purchases", "coins" } },
}
-- EverlookDB addons whose copy of the window library is older (no app list): opened with their slash command.
SM.KNOWN = {
	{ "EverlookDBAuctions", "EverlookDB Auctions", "EVERLOOKAUCTIONS" }, { "EverlookDBCrafting", "EverlookDB Crafting", "EVERLOOKCRAFT" },
	{ "EverlookPets", "EverlookDB Pets", "EVERLOOKPETS" }, { "EverlookDBMail", "EverlookDB Mail", "EVERLOOKMAIL" },
	{ "MouseoverMacros", "EverlookDB Macros", "MOUSEOVERMACROS" }, { "PlayerNotes", "Player Notes", "PLAYERNOTES" },
	{ "Lattice", "Lattice", "LATTICE" }, { "EverlookDBChat", "EverlookDB Chat", "EDBCHAT" },
	{ "EverlookDB", "EverlookDB Collector", "EVERLOOKDB" }, { "EverlookDBQuests", "EverlookDB Quests", "EVERLOOKDBQUESTS" },
	{ "DisenchantValue", "DisenchantValue", "DISENCHANTVALUE" }, { "CraftColors", "CraftColors", "CRAFTCOLORS" },
	{ "Whack", "Whack", "WHACK" }, { "AuraCode", "AuraCode", "AURACODE" },
}

local function addonIcon(addon)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return addon and get and get(addon, "IconTexture") or nil
end
local function loaded(addon)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return f and f(addon) and true or false
end

-- Every entry, freshly read (addons, launchers and professions come and go).
function SM:Entries()
	local list, byId = {}, {}
	local function add(e)
		if byId[e.id] then return end
		if e.secure and not e.run then
			local attrs = e.secure()
			if not attrs and not e.fallback then return end -- the game has no way for it here
		end
		byId[e.id] = e
		list[#list + 1] = e
	end
	-- EverlookDB: every app, its pages (found by the search), and its other views
	local names = {}
	for _, app in ipairs(UI.apps or {}) do
		local name = app.name
		if name and not names[name:lower()] then
			names[name:lower()] = true
			local addon = app.spec and app.spec.addon
			if addon then names[addon:lower()] = true end
			add({ id = "app:" .. name, title = name, sub = "EverlookDB", group = "everlook", icon = (app.spec and app.spec.icon) or addonIcon(addon) or "puzzle",
				keywords = { addon, app.slash, app.spec and app.spec.tagline }, run = function() app:Open() end })
			for _, x in ipairs(addon and SM.EXTRAS[addon] or {}) do
				add({ id = "cmd:" .. name .. ":" .. x[1], title = x[2], sub = name, group = "everlook", icon = x[3], indent = true,
					keywords = { name, x[1] }, run = function() app:HandleSlash(x[1]) end })
			end
			if #(app.order or {}) > 1 then
				for _, sid in ipairs(app.order) do
					local s = app.sections[sid]
					if s and s.title then
						add({ id = "page:" .. name .. ":" .. sid, title = s.title, sub = name, group = "everlook", hidden = true,
							icon = s.icon or UI.PageIcon(s.title), keywords = { name, s.desc }, run = function() app:Open(sid) end })
					end
				end
			end
		end
	end
	for _, k in ipairs(SM.KNOWN) do
		local addon, title, slash = k[1], k[2], k[3]
		if loaded(addon) and not names[addon:lower()] and not names[title:lower()] and type(SlashCmdList[slash]) == "function" then
			names[title:lower()] = true
			add({ id = "app:" .. title, title = title, sub = "EverlookDB", group = "everlook", icon = addonIcon(addon) or "puzzle",
				run = function() SlashCmdList[slash]("") end })
		end
	end
	-- the game's panels
	for _, g in ipairs(SM.GAME) do
		add({ id = g.id, title = g.title, sub = "Game", group = "game", icon = g.icon, keywords = g.keywords,
			secure = g.secure, fallback = g.fallback, run = g.run })
	end
	-- professions (the bar's Professions plugin knows them)
	local P = ns.modules and ns.modules.professions
	if P and P.Read then
		local ok, rows = pcall(P.Read)
		if ok and type(rows) == "table" then
			for _, r in ipairs(rows) do
				if r.window then
					add({ id = "prof:" .. tostring(r.id), title = r.name, sub = "Profession", group = "profession", icon = r.icon or "hammer",
						keywords = { "profession" }, run = function() P.Open(r) end })
				end
			end
		end
	end
	-- addon launchers (LibDataBroker): every one with a click, but not an EverlookDB addon listed above
	if ns.Host then
		local launchers = {}
		for key, rec in pairs(ns.Host.plugins) do
			local obj = rec.obj
			if not rec.module and ns.Host:Kind(rec) == "launcher" and type(obj.OnClick) == "function" then
				local title = ns.Str(obj.label) or key
				if not names[title:lower()] and not names[key:lower()] then launchers[#launchers + 1] = { key, title, rec } end
			end
		end
		table.sort(launchers, function(a, b) return a[2]:lower() < b[2]:lower() end)
		for _, l in ipairs(launchers) do
			local rec = l[3]
			local icon = rec.obj.icon
			add({ id = "ldb:" .. l[1], title = l[2], sub = "Addon", group = "launcher",
				icon = (type(icon) == "string" or type(icon) == "number") and not ns.IsSecret(icon) and icon or "puzzle",
				run = function(owner) ns.SafeCall(rec, rec.obj.OnClick, owner, "LeftButton") end })
		end
	end
	self.byId = byId
	return list, byId
end

-- Search: every word typed must match the title, the group or a keyword (EverlookUI's matcher).
function SM:Find(list, query)
	local entries = {}
	for _, e in ipairs(list) do
		local kw = {}
		for _, k in ipairs(e.keywords or {}) do if type(k) == "string" then kw[#kw + 1] = k end end
		local se = UI.Search.Entry({ label = e.title, keywords = kw, section = e.sub })
		se.e = e
		entries[#entries + 1] = se
	end
	local out = {}
	for _, m in ipairs(UI.Search.Match(entries, query)) do
		local e = (m.entry or m[1]).e
		out[#out + 1] = e
		if #out >= MAX_RESULTS then break end
	end
	return out
end

------------------------------------------------------------------------
-- Opening an entry
------------------------------------------------------------------------
function SM:Remember(e)
	local r = db().recent
	for i = #r, 1, -1 do if r[i] == e.id then table.remove(r, i) end end
	table.insert(r, 1, e.id)
	while #r > MAX_RECENT do table.remove(r) end
end

function SM:IsPinned(id)
	for _, p in ipairs(db().pinned) do if p == id then return true end end
	return false
end
function SM:SetPinned(id, on)
	local p = db().pinned
	for i = #p, 1, -1 do if p[i] == id then table.remove(p, i) end end
	if on then p[#p + 1] = id end
	if self:IsShown() then self:Fill() end
end

-- After a secure click (or a plain run): remember it and close the menu.
function SM:Ran(e)
	self:Remember(e)
	self:Hide()
end

-- A click that is not the secure one, or Enter. A game panel that needs the game's button and has none to click
-- here opens with its key instead (in combat), or arms Enter for a second press.
function SM:Run(e, owner, fromKey)
	if not e then return false end
	if e.run then
		ns.SafeCall(SM, e.run, owner)
		self:Ran(e)
		return true
	end
	local attrs = e.secure and e.secure()
	if attrs then
		if InCombatLockdown() then
			if UIErrorsFrame then UIErrorsFrame:AddMessage(ns.NAME .. ": in combat, open " .. e.title .. " with its key.", 1, 0.3, 0.3) end
			return false
		end
		if fromKey then return self:ArmEnter(e, attrs) end
		return false -- the mouse click without a cover (it was being laid): nothing from addon code
	end
	if e.fallback then
		if InCombatLockdown() then
			if UIErrorsFrame then UIErrorsFrame:AddMessage(ns.NAME .. ": this opens after combat (or use its key).", 1, 0.3, 0.3) end
			return false
		end
		ns.SafeCall(SM, e.fallback)
		self:Ran(e)
		return true
	end
	return false
end

-- Enter on a game panel: the next Enter clicks the game's button (a key binding to a secure button, only while the
-- menu is open and out of combat).
function SM:ArmEnter(e, attrs)
	local f = self.frame
	local btn = self.enterButton
	if not btn then
		-- on UIParent, not in the menu: a secure child would make the menu itself protected in combat
		btn = CreateFrame("Button", ns.PREFIX .. "StartEnter", UIParent, "SecureActionButtonTemplate")
		btn:SetSize(1, 1)
		btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		btn:SetAlpha(0)
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:SetScript("PostClick", function(b) if b.entry then SM:Ran(b.entry) end end)
		self.enterButton = btn
	end
	btn.entry = e
	btn:SetAttribute("type", attrs.type)
	btn:SetAttribute("clickbutton", attrs.clickbutton)
	btn:SetAttribute("macrotext", attrs.macrotext)
	btn:Show()
	self.box:ClearFocus()
	if SetOverrideBindingClick then
		SetOverrideBindingClick(f, true, "ENTER", btn:GetName(), "LeftButton")
		SetOverrideBindingClick(f, true, "NUMPADENTER", btn:GetName(), "LeftButton")
	end
	self.armed = e
	self.hint:SetText("Press Enter again to open " .. e.title)
	return true
end

function SM:Disarm()
	if self.armed and not InCombatLockdown() then
		if ClearOverrideBindings then ClearOverrideBindings(self.frame) end
		if self.enterButton then self.enterButton:Hide() end
	end
	self.armed = nil
	if self.hint then self.hint:SetText("") end
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
local function heading(parent, T)
	local fs = UI.Text(parent, T.fontSmall, T.gold)
	fs:SetJustifyH("LEFT")
	return fs
end

-- A row or tile that may carry a secure click for a game panel (SecureClick lays it while the mouse is on it).
local function secureOf(b)
	return function()
		local e = b.entry
		if e and e.secure and not e.run then return e.secure() end
	end
end

local function entryEnter(b)
	b.hl:Show()
	local e = b.entry
	if e and e.secure and not e.run and S:Owner() ~= b then S:Cover(b) end
	SM:Select(b.index)
end
local function entryLeave(b)
	if SM.sel ~= b.index or not b.isRow then b.hl:Hide() end
end
local function entryClick(b, mouse)
	local e = b.entry
	if not e then return end
	if mouse == "RightButton" then
		local pinned = SM:IsPinned(e.id)
		UI.OpenPopup(b, { { title = true, text = e.title }, { value = "pin", text = pinned and "Unpin from Start" or "Pin to Start" } }, nil,
			function() SM:SetPinned(e.id, not pinned) end, { atCursor = true, width = 180 })
		return
	end
	SM:Run(e, b)
end

local function setup(b, T)
	b.eluiTheme = T
	b:RegisterForClicks("AnyUp")
	b.hl = U.Round(b, 4, "BACKGROUND")
	b.hl:SetAllPoints(b)
	b.hl:SetVertexColor(rgba(T.surfaceHi))
	b.hl:Hide()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.rec = { name = "Start menu", obj = { ebarSecure = secureOf(b) } }
	b.ebarAfterSecure = function(self)
		local e = self.entry
		S:Uncover(self)
		if e then SM:Ran(e) end
	end
	b:SetScript("OnEnter", entryEnter)
	b:SetScript("OnLeave", entryLeave)
	b:SetScript("OnClick", entryClick)
end

local function setIcon(tex, icon, T)
	if UI.SetIcon(tex, icon) then
		if UI.IsIconName(icon) then tex:SetVertexColor(rgba(T.accent)) else tex:SetVertexColor(1, 1, 1) end
	end
end

function SM:Row(i)
	local b = self.rows[i]
	if b then return b end
	local T = theme()
	b = CreateFrame("Button", ns.PREFIX .. "StartRow" .. i, self.list.child)
	setup(b, T)
	b.isRow = true
	b:SetHeight(ROW_H)
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 8, 0)
	b.text = UI.Text(b, T.font, T.text)
	b.text:SetWordWrap(false)
	b.text:SetJustifyH("LEFT")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetPoint("RIGHT", -110, 0)
	b.sub = UI.Text(b, T.fontSmall, T.muted)
	b.sub:SetJustifyH("RIGHT")
	b.sub:SetWordWrap(false)
	b.sub:SetPoint("RIGHT", -10, 0)
	b.sub:SetWidth(100)
	self.rows[i] = b
	return b
end

function SM:Tile(i)
	local b = self.tiles[i]
	if b then return b end
	local T = theme()
	b = CreateFrame("Button", ns.PREFIX .. "StartTile" .. i, self.list.child)
	setup(b, T)
	b:SetSize(TILE_W, TILE_H)
	b.icon:SetSize(24, 24)
	b.icon:SetPoint("TOP", 0, -10)
	b.text = UI.Text(b, T.fontSmall + 1, T.text)
	b.text:SetJustifyH("CENTER")
	b.text:SetPoint("TOPLEFT", 4, -40)
	b.text:SetPoint("TOPRIGHT", -4, -40)
	b.text:SetHeight(22)
	self.tiles[i] = b
	return b
end

function SM:Head(i)
	local h = self.heads[i]
	if h then return h end
	h = heading(self.list.child, theme())
	self.heads[i] = h
	return h
end

function SM:Build()
	if self.frame then return self.frame end
	local T = theme()
	local f = CreateFrame("Frame", ns.PREFIX .. "StartMenu", UIParent)
	self.frame = f
	f.eluiTheme = T
	f:SetSize(W, H)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		db().menuPos = { math.floor((ns.Num(self:GetLeft()) or 0) + 0.5), math.floor((ns.Num(self:GetBottom()) or 0) + 0.5) }
	end)
	f:Hide()
	UI.WindowChrome(f, T)
	UI.RegisterWindow(f, { noTaskbar = true })

	local box = UI.EditBox(f, W - 40, 28)
	box:SetPoint("TOP", 0, -16)
	self.box = box
	local ph = UI.Text(box, T.font, T.muted)
	ph:SetPoint("LEFT", 10, 0)
	ph:SetText("Type to search")
	box.placeholder = ph
	box:SetScript("OnTextChanged", function(self)
		ph:SetShown(self:GetText() == "")
		SM:Disarm()
		SM:Fill()
	end)
	box:SetScript("OnEnterPressed", function() SM:Run(SM.results and SM.results[SM.sel or 1], nil, true) end)
	box:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else SM:Hide() end
	end)
	box:SetScript("OnArrowPressed", function(_, key)
		if key == "DOWN" then SM:Select((SM.sel or 0) + 1) elseif key == "UP" then SM:Select((SM.sel or 2) - 1) end
	end)
	if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end

	local list = UI.ScrollPage(f)
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", 12, -56)
	list:SetPoint("BOTTOMRIGHT", -12 - 18, 52)
	list.child:SetWidth(W - 24 - 18)
	self.list = list
	-- the list scrolled under the mouse: a secure click laid on a row would stay where that row was
	list:HookScript("OnVerticalScroll", function() SM:UncoverAll() end)

	local line = U.Solid(f, "ARTWORK", rgba(T.divider))
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 1, 46)
	line:SetPoint("BOTTOMRIGHT", -1, 46)
	local tile = UI.Button(f, "Tile all", function() if ns.Taskbar then ns.Taskbar:TileAll() end SM:Hide() end, 96)
	tile:SetPoint("BOTTOMLEFT", 14, 12)
	local minall = UI.Button(f, "Minimize all", function() ns.WM:MinimizeAll() SM:Hide() end, 110)
	minall:SetPoint("LEFT", tile, "RIGHT", 8, 0)
	local settings = UI.Button(f, "Settings", function() SM:Hide() ns.Options:Open("taskbar") end, 96)
	settings:SetPoint("BOTTOMRIGHT", -14, 12)
	self.tileButton, self.minButton = tile, minall
	self.hint = UI.Text(f, T.fontSmall, T.accent)
	self.hint:SetPoint("BOTTOM", line, "TOP", 0, 4)

	f:SetScript("OnShow", function()
		ns.On("GLOBAL_MOUSE_DOWN", SM, function() SM:OutsideClick() end)
		if ns.Taskbar then ns.Taskbar:Refresh() end
	end)
	f:SetScript("OnHide", function()
		ns.Off("GLOBAL_MOUSE_DOWN", SM)
		SM:Disarm()
		SM:UncoverAll()
		SM.cache = nil
		box:ClearFocus()
		if ns.Taskbar then ns.Taskbar:Refresh() end
	end)
	UI.CloseOnEscape(f)
	return f
end

-- Next to the Start button (on the screen side of the taskbar), or where the player dragged it.
function SM:Anchor()
	local f = self.frame
	f:ClearAllPoints()
	local p = db().menuPos
	local st = ns.Taskbar and ns.Taskbar.start
	if type(p) == "table" and p[1] then
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
	elseif st and st:IsVisible() then
		local e = ns.Taskbar.edge or "bottom"
		if e == "top" then f:SetPoint("TOPLEFT", st, "BOTTOMLEFT", 0, -4)
		elseif e == "left" then f:SetPoint("TOPLEFT", st, "TOPRIGHT", 4, 0)
		elseif e == "right" then f:SetPoint("TOPRIGHT", st, "TOPLEFT", -4, 0)
		else f:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, 4) end
	else
		f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
	end
end

function SM:UncoverAll()
	for _, b in ipairs(self.rows) do S:Uncover(b) end
	for _, b in ipairs(self.tiles) do S:Uncover(b) end
end

function SM:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function SM:Hide() if self.frame then self.frame:Hide() end end
function SM:Show(query)
	self:Build()
	self:Anchor()
	self.frame:Show()
	self.frame:Raise()
	self.cache = nil
	self.box:SetText(query or "")
	self:Fill()
	self.box:SetFocus()
end
function SM:Toggle() if self:IsShown() then self:Hide() else self:Show() end end

function SM:OutsideClick()
	if not self:IsShown() or UI.IsPopupShown() then return end
	if self.frame:IsMouseOver() then return end
	local st = ns.Taskbar and ns.Taskbar.start
	if st and st:IsVisible() and st:IsMouseOver() then return end -- the Start button's own click toggles it
	if S:Frame() and S:Frame():IsShown() and S:Frame():IsMouseOver() then return end
	self:Hide()
end

-- The keyboard's pick among the rows (Up and Down; Enter opens it).
function SM:Select(i)
	local n = self.results and #self.results or 0
	if n == 0 then self.sel = nil return end
	i = math.max(1, math.min(n, i or 1))
	self.sel = i
	for _, b in ipairs(self.rows) do
		if b:IsShown() and b.isRow then b.hl:SetShown(b.index == i or b:IsMouseOver()) end
	end
end

-- Lay the list out: pinned tiles, recent and everything (no search), or the results.
function SM:Fill()
	if not self.frame then return end
	local T = theme()
	if not self.cache then self.cache = { self:Entries() } end
	local list, byId = self.cache[1], self.cache[2]
	self:UncoverAll()
	local q = U.Trim(self.box:GetText() or "")
	local child = self.list.child
	local width = child:GetWidth() or (W - 42)
	local y, nRows, nTiles, nHeads = 0, 0, 0, 0
	local results = {}
	local function head(text)
		nHeads = nHeads + 1
		local h = self:Head(nHeads)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y - 6)
		h:SetText(text:upper())
		h:Show()
		y = y + 24
	end
	local function row(e, indent)
		nRows = nRows + 1
		local b = self:Row(nRows)
		results[#results + 1] = e
		b.entry, b.index = e, #results
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", child, "TOPLEFT", indent and 18 or 0, -y)
		b:SetWidth(width - (indent and 18 or 0))
		setIcon(b.icon, e.icon, T)
		b.text:SetText(e.title)
		b.sub:SetText(e.sub or "")
		b:Show()
		y = y + ROW_H
	end
	if q ~= "" then
		local found = self:Find(list, q)
		head("Results")
		for _, e in ipairs(found) do row(e) end
		if #found == 0 then
			nHeads = nHeads + 1
			local h = self:Head(nHeads)
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y - 4)
			h:SetText("Nothing found for \"" .. U.Escape(q) .. "\"")
			h:Show()
			y = y + 24
		end
	else
		local pinned = {}
		for _, id in ipairs(db().pinned) do if byId[id] then pinned[#pinned + 1] = byId[id] end end
		if #pinned > 0 then
			head("Pinned")
			local cols = math.max(1, math.floor((width + 4) / (TILE_W + 4)))
			for i, e in ipairs(pinned) do
				nTiles = nTiles + 1
				local b = self:Tile(nTiles)
				b.entry, b.index = e, nil
				local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", child, "TOPLEFT", c * (TILE_W + 4), -y - r * (TILE_H + 4))
				setIcon(b.icon, e.icon, T)
				b.text:SetText(e.title)
				b:Show()
			end
			y = y + math.ceil(#pinned / cols) * (TILE_H + 4) + 4
		end
		local recent = {}
		for _, id in ipairs(db().recent) do if byId[id] then recent[#recent + 1] = byId[id] end end
		if #recent > 0 then
			head("Recent")
			for _, e in ipairs(recent) do row(e) end
		end
		local groups = { { "everlook", "EverlookDB" }, { "game", "Game" }, { "profession", "Professions" }, { "launcher", "Addons" } }
		for _, g in ipairs(groups) do
			local any = false
			for _, e in ipairs(list) do
				if e.group == g[1] and not e.hidden then
					if not any then head(g[2]); any = true end
					row(e, e.indent)
				end
			end
		end
	end
	for i = nRows + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].entry = nil end
	for i = nTiles + 1, #self.tiles do self.tiles[i]:Hide(); self.tiles[i].entry = nil end
	for i = nHeads + 1, #self.heads do self.heads[i]:Hide() end
	child:SetHeight(math.max(1, y + 6))
	if self.list.UpdateBar then self.list.UpdateBar() end
	self.results = results
	self:Select(1)
	local tileable = ns.WM and ns.WM.running
	self.tileButton:SetUsable(tileable and true or false)
	self.minButton:SetUsable(tileable and true or false)
end
