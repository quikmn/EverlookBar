-- EverlookDB Bar: minimap tracking. What the minimap tracks (Mailbox, Find Herbs...) on the bar; a click opens a menu
-- of every tracking type the game offers this character, grouped like the game's own tracking button (find and track
-- spells, townsfolk, the rest), each with a check box. It does what the minimap's tracking button does, so the button
-- can be hidden (Clean minimap) without losing the way to change tracking.
--
-- API: C_Minimap.GetNumTrackingTypes / GetTrackingInfo / SetTracking / ClearAllTracking (WoW Forever has these), or the
-- older globals GetNumTrackingTypes / GetTrackingInfo / SetTracking. Only the type the player clicked is ever set; a
-- spell type (Find Herbs) casts that spell through the game's own SetTracking, nothing else. In combat the menu is
-- read-only ("after combat"): nothing is set and nothing waits. Event driven: no ticker (one only while the menu is open,
-- to fold it away when the mouse has left it).
local _, ns = ...
local U = ns.Util
local UI = ns.UI

local M = ns:NewModule({
	id = "tracking", title = "Tracking", ldbName = ns.PREFIX .. "_Tracking",
	desc = "What the minimap tracks (Mailbox, Find Herbs...); click to change it, like the minimap's tracking button.",
	keywords = { "tracking", "track", "minimap", "mailbox", "trainer", "herbs", "minerals", "treasure", "beasts",
		"humanoids", "find", "flight master", "innkeeper", "banker", "auctioneer", "repair", "stable" },
	defaults = { show = "all" }, -- all | first | icon
	place = { group = "right", order = 4.5 },
})

local NONE_ICON = "Interface\\Minimap\\Tracking\\None"
local HUNTER_TRACKING, TOWNSFOLK = 1, 2 -- subType values in the game's own tracking menu
M.MAX_IN_TEXT = 2                       -- "Mailbox, Herbs +2"

-- The game's groups, in the order the menu shows them.
M.GROUPS = {
	{ key = "spell", title = "Find and track" },
	{ key = "town", title = "Townsfolk" },
	{ key = "other", title = "Other" },
}

local obj
local list = {}   -- every tracking type the game offers (reused tables), in the game's order
local active = {} -- the active ones, in menu order
M.list, M.active = list, active

------------------------------------------------------------------------
-- The client's API
------------------------------------------------------------------------
-- Which tracking API this client has: "C_Minimap", "global" or nil.
function M.Api()
	local C = C_Minimap
	if C and C.GetNumTrackingTypes and C.GetTrackingInfo and C.SetTracking then return "C_Minimap" end
	if GetNumTrackingTypes and GetTrackingInfo and SetTracking then return "global" end
	return nil
end

local function bool(v)
	if v == nil or ns.IsSecret(v) then return nil end
	return v and true or false
end

local function icon(v)
	if v == nil or ns.IsSecret(v) then return nil end
	if type(v) == "number" or (type(v) == "string" and v ~= "") then return v end
end

-- One tracking type: name, texture, active, kind ("spell", "npc", "other"), subType, spellID. nil when unreadable.
function M.Info(i)
	local api = M.Api()
	if api == "C_Minimap" then
		local ok, d = pcall(C_Minimap.GetTrackingInfo, i)
		if not ok or type(d) ~= "table" or ns.IsSecret(d) then return nil end
		return ns.Str(d.name), icon(d.texture), bool(d.active), ns.Str(d.type), ns.Num(d.subType), ns.Num(d.spellID)
	elseif api == "global" then
		local ok, name, tex, on, kind, sub, spellID = pcall(GetTrackingInfo, i)
		if not ok then return nil end
		return ns.Str(name), icon(tex), bool(on), ns.Str(kind), ns.Num(sub), ns.Num(spellID)
	end
end

function M.Count()
	local api = M.Api()
	local f = api == "C_Minimap" and C_Minimap.GetNumTrackingTypes or (api == "global" and GetNumTrackingTypes)
	if not f then return 0 end
	local ok, n = pcall(f)
	return ok and ns.Num(n) or 0
end

-- The game's way to untrack everything, or nil when this client has none.
function M.ClearFunc()
	if C_Minimap and C_Minimap.ClearAllTracking then return C_Minimap.ClearAllTracking end
	if ClearAllTracking then return ClearAllTracking end
end

function M.Group(kind, subType)
	if kind == "spell" or subType == HUNTER_TRACKING then return "spell" end
	if subType == TOWNSFOLK or kind == "npc" then return "town" end
	return "other"
end

-- "Find Herbs" -> "Herbs", "Track Beasts" -> "Beasts", "Mailbox" stays.
function M.Short(name)
	name = tostring(name or "")
	local s = name:gsub("^Find ", ""):gsub("^Track ", ""):gsub("^Sense ", "")
	return s ~= "" and s or name
end

------------------------------------------------------------------------
-- The model
------------------------------------------------------------------------
local GROUP_ORDER = {}
for i, g in ipairs(M.GROUPS) do GROUP_ORDER[g.key] = i end

function M.Read()
	local n = 0
	for i = 1, M.Count() do
		local name, tex, on, kind, sub, spellID = M.Info(i)
		if name and name ~= "" then
			n = n + 1
			local r = list[n] or {}
			list[n] = r
			r.index, r.name, r.icon, r.active = i, name, tex or NONE_ICON, on and true or false
			r.kind, r.subType, r.spellID = kind or "other", sub, spellID
			r.group = M.Group(kind, sub)
			r.short = M.Short(name)
		end
	end
	for i = n + 1, #list do list[i] = nil end
	local a = 0
	for _, g in ipairs(M.GROUPS) do
		for _, r in ipairs(list) do
			if r.group == g.key and r.active then a = a + 1; active[a] = r end
		end
	end
	for i = a + 1, #active do active[i] = nil end
	return list
end

-- The menu's rows: { title = true, text } for a group heading, { index, name, text, icon, checked, disabled } for a
-- tracking type, { note = true, text } for the combat line. combat: the menu is read-only.
function M.MenuModel(combat)
	local rows = {}
	for _, g in ipairs(M.GROUPS) do
		local any = false
		for _, r in ipairs(list) do
			if r.group == g.key then
				if not any then rows[#rows + 1] = { title = true, text = g.title }; any = true end
				rows[#rows + 1] = { index = r.index, name = r.name, text = r.name, icon = r.icon, checked = r.active,
					spell = r.group == "spell", disabled = combat and true or false }
			end
		end
	end
	if #rows == 0 then
		rows[1] = { note = true, text = M.Api() and "Nothing to track yet." or "This client has no tracking API." }
	elseif combat then
		rows[#rows + 1] = { note = true, text = "In combat: change tracking after combat." }
	end
	return rows
end

-- Turn tracking type `index` on or off (the opposite of now). `name` guards against a list that changed since the
-- menu was drawn. Returns true, or false and why ("combat", "changed", "api").
function M.Toggle(index, name)
	if InCombatLockdown() then return false, "combat" end
	local api = M.Api()
	if not api then return false, "api" end
	local cur, _, on = M.Info(index)
	if not cur or (name and cur ~= name) then M:Update() return false, "changed" end
	local f = api == "C_Minimap" and C_Minimap.SetTracking or SetTracking
	f(index, not on)
	M:Update()
	return true
end

-- Untrack everything, when the game allows it. Returns true, or false and why.
function M.CanClear() return M.ClearFunc() ~= nil and #active > 0 end
function M.ClearAll()
	if InCombatLockdown() then return false, "combat" end
	local f = M.ClearFunc()
	if not f then return false, "api" end
	f()
	M:Update()
	return true
end

-- What the bar shows. mode: all | first | icon.
function M.Text(mode)
	if mode == "icon" then return "" end
	if #active == 0 then return "|cff8d94a3Not tracking|r" end
	local shown = mode == "first" and 1 or M.MAX_IN_TEXT
	local t = {}
	for i = 1, math.min(shown, #active) do t[i] = active[i].short end
	local s = table.concat(t, ", ")
	if #active > shown then s = s .. " |cff8d94a3+" .. (#active - shown) .. "|r" end
	return s
end

function M.Icon()
	return active[1] and active[1].icon or NONE_ICON
end

------------------------------------------------------------------------
-- The menu: our own small frame (the shared dropdown closes on every click and has no check boxes). It stays open
-- while you tick types, folds away once the mouse has been off it and the plugin for a moment, on Escape, or on a
-- second click on the plugin. It never closes another window.
------------------------------------------------------------------------
local ROW, PAD, MIN_W = 22, 4, 210
local menu, hideTask
local away = 0

local function T() return ns.Theme end

local function rowEnter(b)
	if b.item and b.item.index and not b.item.disabled then b.hl:Show() end
	if b.item and b.item.spell and b.item.disabled then
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:AddLine(b.item.name, 1, 1, 1)
		GameTooltip:AddLine("A tracking spell: pick it after combat.", 0.55, 0.58, 0.64, true)
		GameTooltip:Show()
		b.tip = true
	end
end
local function rowLeave(b)
	b.hl:Hide()
	if b.tip then GameTooltip:Hide(); b.tip = nil end
end
local function rowClick(b)
	local item = b.item
	if not item or not item.index or item.disabled then return end
	local ok, why = M.Toggle(item.index, item.name)
	if not ok and why == "combat" then ns:Print("tracking can be changed after combat.") end
	M.DrawMenu()
end

local function makeRow(i)
	local t = T()
	local b = CreateFrame("Button", nil, menu)
	b:SetHeight(ROW)
	b:RegisterForClicks("LeftButtonUp")
	b.hl = U.Round(b, 4, "BACKGROUND", 1)
	b.hl:SetAllPoints(b)
	b.hl:SetVertexColor(U.rgba(t.surfaceHi))
	b.hl:Hide()
	-- check box: a rounded square, filled with the accent and a check when on
	b.box = CreateFrame("Frame", nil, b)
	b.box:SetSize(14, 14)
	b.box:SetPoint("LEFT", 8, 0)
	b.boxFill, b.boxEdge = U.RoundBox(b.box, 3, t.surface, t.border, "ARTWORK")
	b.check = b.box:CreateTexture(nil, "OVERLAY")
	b.check:SetSize(10, 10)
	b.check:SetPoint("CENTER")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 30, 0)
	b.text = UI.Text(b, t.font, t.text)
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", rowEnter)
	b:SetScript("OnLeave", rowLeave)
	b:SetScript("OnClick", rowClick)
	menu.rows[i] = b
	return b
end

local function makeMenu()
	local t = T()
	menu = CreateFrame("Frame", ns.PREFIX .. "TrackingMenu", UIParent)
	menu.eluiTheme = t
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	menu.bg, menu.edge = U.RoundBox(menu, 6, t.bg, t.border)
	local line = U.Solid(menu, "ARTWORK", U.rgba(t.accent))
	line:SetHeight(2)
	line:SetPoint("TOPLEFT", 6, -1)
	line:SetPoint("TOPRIGHT", -6, -1)
	menu.head = UI.Text(menu, t.fontTitle, t.gold)
	menu.head:SetPoint("TOPLEFT", 12, -10)
	menu.head:SetText("Minimap tracking")
	menu.rows = {}
	menu:SetScript("OnShow", function() away = 0; if hideTask then hideTask:SetActive(true) end end)
	menu:SetScript("OnHide", function() if hideTask then hideTask:SetActive(false) end end)
	UI.CloseOnEscape(menu)
	hideTask = ns.Every(M, 0.25, function()
		if not menu:IsShown() then hideTask:SetActive(false) return end
		local over = menu:IsMouseOver() or (menu.owner and menu.owner.IsMouseOver and menu.owner:IsMouseOver())
		away = over and 0 or (away + 0.25)
		if away >= 1.5 then menu:Hide() end
	end, false)
	M.menu = menu
end

-- Draw the menu from the model (again after every change).
function M.DrawMenu()
	if not menu or not menu:IsShown() then return end
	local t = T()
	M.Read()
	local items = M.MenuModel(InCombatLockdown())
	M.menuItems = items
	local y = -32
	local width = MIN_W
	for i, item in ipairs(items) do
		local b = menu.rows[i] or makeRow(i)
		b.item = item
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y)
		b:SetPoint("RIGHT", menu, "RIGHT", -PAD, 0)
		b.text:ClearAllPoints()
		if item.title or item.note then
			b.box:Hide(); b.icon:Hide()
			b.text:SetPoint("LEFT", 8, item.title and -2 or 0)
			b.text:SetPoint("RIGHT", -8, 0)
			U.SetFont(b.text, item.title and t.fontSmall or t.font)
			b.text:SetTextColor(U.rgba(item.note and t.gold or t.muted))
			b.text:SetText(item.title and item.text:upper() or item.text)
			b:SetAlpha(1)
			b:EnableMouse(false)
		else
			b.box:Show()
			b.boxFill:SetVertexColor(U.rgba(item.checked and t.accentFill or t.surface))
			b.boxEdge:SetVertexColor(U.rgba(item.checked and t.accent or t.border))
			if item.checked and UI.SetIcon(b.check, "check") then b.check:SetVertexColor(U.rgba(t.onAccent)) else b.check:Hide() end
			UI.SetIcon(b.icon, item.icon)
			b.text:SetPoint("LEFT", 52, 0)
			b.text:SetPoint("RIGHT", -8, 0)
			U.SetFont(b.text, t.font)
			b.text:SetTextColor(U.rgba(t.text))
			b.text:SetText(item.text)
			b:SetAlpha(item.disabled and 0.5 or 1)
			b:EnableMouse(true)
		end
		local w = ns.Num(b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()) or 0
		local need = (item.title or item.note) and (w + 16 + 2 * PAD) or (w + 60 + 2 * PAD)
		if need > width then width = need end
		b:Show()
		y = y - ROW
	end
	for i = #items + 1, #menu.rows do menu.rows[i]:Hide(); menu.rows[i].item = nil end
	menu:SetSize(math.ceil(width), -y + PAD + 2)
end

local function anchorMenu(owner)
	menu:ClearAllPoints()
	if not owner then
		local x, yy = GetCursorPosition()
		local s = UIParent:GetEffectiveScale()
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, yy / s)
		return
	end
	local _, cy = owner:GetCenter()
	local h = ns.Num(UIParent:GetHeight()) or 768
	if (ns.Num(cy) or h) > h / 2 then
		menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	else
		menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	end
end

function M.OpenMenu(owner)
	if not menu then makeMenu() end
	if menu:IsShown() and menu.owner == owner then menu:Hide() return end
	UI.ClosePopup()
	menu.owner = owner
	anchorMenu(owner)
	menu:Show()
	M.DrawMenu()
end

function M.CloseMenu() if menu then menu:Hide() end end

-- Right-click: untrack all (when the game allows it) and the settings.
function M.RightMenu(owner)
	M.CloseMenu()
	local items = { { title = true, text = "Tracking" } }
	if M.CanClear() then
		local combat = InCombatLockdown()
		items[#items + 1] = combat and { title = true, text = "Untrack all (after combat)" } or { value = "clear", text = "Untrack all" }
	end
	items[#items + 1] = { value = "settings", text = "Settings..." }
	M.rightItems = items
	UI.OpenPopup(owner, items, nil, M.RightPick, { atCursor = true, width = 200 })
end

function M.RightPick(v)
	if v == "clear" then
		local ok, why = M.ClearAll()
		if not ok and why == "combat" then ns:Print("tracking can be changed after combat.") end
	elseif v == "settings" and ns.Options then
		ns.Options:Open("modules")
	end
end

function M.Click(frame, mouse)
	if mouse == "RightButton" then M.RightMenu(frame) return end
	M.OpenMenu(frame)
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
function M:Update()
	M.Read()
	if not obj then return end
	local db = ns:ModuleDB("tracking")
	obj.text = M.Text(db.show)
	obj.icon = M.Icon()
	if menu and menu:IsShown() then M.DrawMenu() end
end
M.Redraw = M.Update

function M.Tooltip(tip)
	ns.TipHeader(tip, "Tracking")
	if #list == 0 then
		ns.TipHint(tip, M.Api() and "Nothing to track yet." or "This client has no tracking API.")
		return
	end
	if #active == 0 then
		ns.TipHint(tip, "Nothing tracked on the minimap.")
	else
		for _, r in ipairs(active) do
			tip:AddLine("|T" .. tostring(r.icon) .. ":14:14:0:0:64:64:5:59:5:59|t " .. U.Escape(r.name), 0.9, 0.9, 0.9)
		end
	end
	tip:AddLine(" ")
	if InCombatLockdown() then
		ns.TipHint(tip, "In combat: change tracking after combat.")
	else
		ns.TipHint(tip, M.CanClear() and "Click to change. Right-click: untrack all." or "Click to change.")
	end
end

-- Existing players (a layout from before this plugin) don't get it on a bar uninvited. Those who hide the minimap's
-- tracking button hear about it once in chat.
function M.TellExisting()
	if not ns.db or ns.db.placement[M.ldbName] then return end
	local mm = ns.modules.minimap
	if not (mm and mm.running and mm:Mode("tracking") ~= "show") then return end
	if not ns.TellOnce("trackingPlugin") then return end
	ns:Print("new: a Tracking plugin (Mailbox, Find Herbs...) does what the hidden minimap tracking button did. Put it on a bar: "
		.. ns.SLASH .. " place tracking 1 right")
end

function M:Available() return M.Api() ~= nil end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Tracking", text = "", icon = NONE_ICON,
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function(frame, mouse) M.Click(frame, mouse) end,
	})
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED",
		"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		ns.On(e, self, update)
	end
	if ns.db and ns.db.seenLayout and not M.toldChecked then
		M.toldChecked = true
		C_Timer.After(8, function() ns.SafeCall(M, M.TellExisting) end)
	end
	self:Update()
end

function M:Disable() M.CloseMenu() end
