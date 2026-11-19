-- Everlook Bar: professions. Your skill in each profession ("Mining 187  Herb 150  Cook 225"), each one its own click
-- target: click one to open its window. Primary professions, Cooking, First Aid, Fishing and (if you like) Riding.
-- Skills come from the game's skill list (C_SkillInfo); windows open through C_TradeSkillUI.OpenTradeSkill, which is
-- not protected (Blizzard's own alerts call it). Gathering skills, Fishing and Riding have no window.
-- Event driven, coalesced: no ticker.
local _, ns = ...
local U = ns.Util
local UI = ns.UI

local M = ns:NewModule({
	id = "professions", title = "Professions", ldbName = ns.PREFIX .. "_Professions",
	desc = "Your profession skills (Mining 187, Cook 225); click one to open its window, right-click for all of them.",
	defaults = { primary = true, cooking = false, firstAid = false, fishing = false, riding = false, showMax = false,
		names = "short", icons = true, markCap = true, capColor = { 1.00, 0.55, 0.25, 1 } },
	place = { group = "left", order = 2 },
})

-- Known skill lines by ID (the same in every language). kind: which setting shows it; window: it has a recipe window.
local I = "Interface\\Icons\\"
local KNOWN = {
	[171] = { short = "Alch", icon = I .. "Trade_Alchemy", window = true },
	[164] = { short = "BS", icon = I .. "Trade_BlackSmithing", window = true },
	[333] = { short = "Ench", icon = I .. "Trade_Engraving", window = true },
	[202] = { short = "Eng", icon = I .. "Trade_Engineering", window = true },
	[182] = { short = "Herb", icon = I .. "Trade_Herbalism", window = false },
	[165] = { short = "LW", icon = I .. "Trade_LeatherWorking", window = true },
	[186] = { short = "Mining", icon = I .. "Trade_Mining", window = true }, -- smelting
	[393] = { short = "Skin", icon = I .. "INV_Misc_Pelt_Wolf_01", window = false },
	[197] = { short = "Tailor", icon = I .. "Trade_Tailoring", window = true },
	[755] = { short = "JC", icon = I .. "INV_Misc_Gem_01", window = true },
	[773] = { short = "Insc", icon = I .. "INV_Inscription_Tradeskill01", window = true },
	[185] = { short = "Cook", icon = I .. "INV_Misc_Food_15", window = true, kind = "cooking", sort = 2 },
	[129] = { short = "Aid", icon = I .. "Spell_Holy_SealOfSacrifice", window = true, kind = "firstAid", sort = 3 },
	[356] = { short = "Fish", icon = I .. "Trade_Fishing", window = false, kind = "fishing", sort = 4 },
	[762] = { short = "Ride", icon = I .. "Spell_Nature_Swiftness", window = false, kind = "riding", sort = 5 },
}
M.KNOWN = KNOWN
local CAT_PROFESSION = 11 -- SkillLineCategory "Professions" (primary); other profession-like lines are known by ID
local ICON, ICON_GAP, PIECE_GAP = 14, 3, 10

local obj
local rows = {}   -- every profession the player has (reused tables), sorted
local shown = {}  -- the ones on the bar
local seen = {}
M.rows, M.shown = rows, shown
M.widgetW = 0

local function sortRows(a, b)
	if a.sort ~= b.sort then return a.sort < b.sort end
	return a.name < b.name
end

-- One skill line into row n (when it is a profession). Returns the new count.
local function add(n, d)
	local id = ns.Num(d.skillID)
	if not id or seen[id] then return n end
	local k = KNOWN[id]
	if not k and ns.Num(d.skillLineCategoryID) ~= CAT_PROFESSION then return n end
	local rank, max = ns.Num(d.rank), ns.Num(d.maxRank)
	if not rank then return n end
	local name = ns.Str(d.name) or (k and k.short) or "?"
	seen[id] = true
	n = n + 1
	local r = rows[n] or {}
	rows[n] = r
	r.id, r.name, r.rank, r.max, r.mod = id, name, rank, max or 0, ns.Num(d.modifier) or 0
	r.short = k and k.short or name:sub(1, 4)
	r.icon = k and k.icon or (I .. "INV_Misc_QuestionMark")
	r.window = (not k) or k.window
	r.kind = k and k.kind or "primary"
	r.sort = k and k.sort or 1
	return n
end

-- Read the skill list. Professions under a collapsed header are looked up by ID instead.
function M.Read()
	local S = C_SkillInfo
	wipe(seen)
	local n, collapsed = 0, false
	local total = ns.Num(S.GetNumSkillLines()) or 0
	for i = 1, total do
		local d = S.GetSkillLineInfo(i)
		if type(d) == "table" and not ns.IsSecret(d) then
			if d.isHeader then
				if d.isCollapsed then collapsed = true end
			else
				n = add(n, d)
			end
		end
	end
	if collapsed and S.GetSkillLineInfoByID then
		for id in pairs(KNOWN) do
			if not seen[id] then
				local d = S.GetSkillLineInfoByID(id)
				if type(d) == "table" and not ns.IsSecret(d) and (ns.Num(d.rank) or 0) > 0 then n = add(n, d) end
			end
		end
	end
	for i = n + 1, #rows do rows[i] = nil end
	-- WoW Forever lists some professions twice: the known skill line and a second line with another ID and the same
	-- name (both with the same skill). Keep one per name, the known one (it has the icon and the window).
	local known = {}
	for _, r in ipairs(rows) do if KNOWN[r.id] then known[r.name:lower()] = true end end
	for i = #rows, 1, -1 do
		local r = rows[i]
		if not KNOWN[r.id] and known[r.name:lower()] then table.remove(rows, i) end
	end
	table.sort(rows, sortRows)
	return rows
end

function M.AtCap(r) return r.max > 0 and r.rank >= r.max end

-- Is this row on the bar with these settings?
function M.Shows(r, db)
	if r.kind == "primary" then return db.primary ~= false end
	return db[r.kind] and true or false
end

local function hex(c)
	c = type(c) == "table" and c or { 1, 0.55, 0.25 }
	local function b(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
	return string.format("|cff%02x%02x%02x", b(c[1]), b(c[2]), b(c[3]))
end

-- The number, coloured when at the cap.
function M.Number(r, db)
	local s = db.showMax and (r.rank .. "/" .. r.max) or tostring(r.rank)
	if db.markCap and M.AtCap(r) then s = hex(db.capColor) .. s .. "|r" end
	return s
end

-- One profession's piece of text on the bar: "Mining 187", "Herbalism 150/150" or just "187" next to its icon.
function M.PieceText(r, db)
	local label
	if db.names == "full" then label = r.name
	elseif db.names ~= "none" or not db.icons then label = r.short end
	local num = M.Number(r, db)
	return label and (label .. " " .. num) or num
end

-- The whole line as plain text (the tooltip of an empty bar, and tests).
function M.Text(db)
	local t = {}
	for _, r in ipairs(shown) do t[#t + 1] = M.PieceText(r, db) end
	return table.concat(t, "  ")
end

function M.Row(id)
	for _, r in ipairs(rows) do if r.id == id then return r end end
end

function M.FirstWithWindow()
	for _, r in ipairs(shown) do if r.window then return r end end
	for _, r in ipairs(rows) do if r.window then return r end end
end

------------------------------------------------------------------------
-- Opening a profession
------------------------------------------------------------------------
-- Opens (or closes, when it is the one already open) the profession's window. Returns true when the game opened it.
function M.Open(r)
	if not r or not r.window then return false end
	local T = C_TradeSkillUI
	if not (T and T.OpenTradeSkill) then return false end
	local pf = ProfessionsFrame or TradeSkillFrame
	if pf and pf.IsShown and pf:IsShown() and T.GetBaseProfessionInfo and T.CloseTradeSkill then
		local info = T.GetBaseProfessionInfo()
		if type(info) == "table" and ns.Num(info.professionID) == r.id then
			T.CloseTradeSkill()
			return true
		end
	end
	local opened = T.OpenTradeSkill(r.id)
	if not opened then ns:Print("the game did not open " .. U.Escape(r.name) .. " from here.") end
	return opened and true or false
end

-- The list of every profession at the cursor: pick one to open it.
function M.Menu(owner)
	local items = { { title = true, text = "Professions" } }
	for _, r in ipairs(rows) do
		local t = r.name .. "  " .. r.rank .. "/" .. r.max
		if r.window then
			items[#items + 1] = { value = r.id, text = t, icon = r.icon }
		else
			items[#items + 1] = { title = true, text = t .. " (no window)", icon = r.icon }
		end
	end
	items[#items + 1] = { value = "settings", text = "Settings..." }
	M.menuItems = items
	UI.OpenPopup(owner, items, nil, M.MenuPick, { atCursor = true, width = 240 })
end

function M.MenuPick(v)
	if v == "settings" then
		if ns.Options then ns.Options:Open("modules") end
		return
	end
	M.Open(M.Row(v))
end

-- Left-click a profession: open (or close) its window. Right-click, or a profession with no window, or the button
-- around the pieces: every profession in a list (the bar shows only your two main ones); pick one to open it.
function M.Click(frame, mouse, id)
	if mouse ~= "RightButton" and id then
		local r = M.Row(id)
		if r and r.window then M.Open(r) return end
	end
	M.Menu(frame)
end

------------------------------------------------------------------------
-- The pieces: one small button per profession inside the plugin's button (through the public widget API), so each
-- profession is its own click target. Hover and unlock-mode drags are handed to the plugin's button.
------------------------------------------------------------------------
local pieces = {}
M.pieces = pieces

local function button(p) return p:GetParent():GetParent() end
local function pieceEnter(p)
	M.hover = p.id
	local b = button(p)
	local fn = b and b:GetScript("OnEnter")
	if fn then fn(b) end
end
local function pieceLeave(p)
	M.hover = nil
	local b = button(p)
	local fn = b and b:GetScript("OnLeave")
	if fn then fn(b) end
end
local function pieceClick(p, mouse)
	if ns.Unlock and ns.Unlock.active then return end
	local b = button(p)
	if b and b.shownTip == GameTooltip then GameTooltip:Hide(); b.shownTip = nil end
	ns.SafeCall(M, M.Click, p, mouse, p.id)
end
local function pieceDrag(p)
	local b = button(p)
	local fn = b and b:GetScript("OnDragStart")
	if fn then fn(b) end
end
local function pieceDrop(p)
	local b = button(p)
	local fn = b and b:GetScript("OnDragStop")
	if fn then fn(b) end
end

local function makePiece(f, i)
	local p = CreateFrame("Button", nil, f)
	p:RegisterForClicks("AnyUp")
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnEnter", pieceEnter)
	p:SetScript("OnLeave", pieceLeave)
	p:SetScript("OnClick", pieceClick)
	p:SetScript("OnDragStart", pieceDrag)
	p:SetScript("OnDragStop", pieceDrop)
	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetSize(ICON, ICON)
	p.icon:SetPoint("LEFT", p, "LEFT", 0, 0)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.text = p:CreateFontString(nil, "OVERLAY")
	U.SetFont(p.text, 12, "")
	p.text:SetWordWrap(false)
	p.text:SetJustifyH("LEFT")
	p.text:SetTextColor(0.92, 0.93, 0.95, 1)
	pieces[i] = p
	return p
end

-- Lay the pieces out and return their total width (the widget's width). Runs when the button redraws.
function M.Layout(f)
	if not f then return 0 end
	local db = ns:ModuleDB("professions")
	local b = f:GetParent()
	local font, size, flags
	if b and b.text and b.text.GetFont then font, size, flags = b.text:GetFont() end
	local h = b and ns.Num(b:GetHeight()) or 0
	if h < 10 then h = 20 end
	local x = 0
	for i, r in ipairs(shown) do
		local p = pieces[i] or makePiece(f, i)
		p.id = r.id
		if font and (p.font ~= font or p.size ~= size or p.flags ~= flags) then
			p.text:SetFont(font, size, flags)
			p.font, p.size, p.flags, p.lastText = font, size, flags, nil
		end
		local tx = 0
		if db.icons then
			if p.lastIcon ~= r.icon then p.icon:SetTexture(r.icon); p.lastIcon = r.icon end
			p.icon:Show()
			tx = ICON + ICON_GAP
		else
			p.icon:Hide()
		end
		local text = M.PieceText(r, db)
		if p.lastText ~= text then
			p.text:SetText(text)
			p.lastText = text
			local w = p.text.GetUnboundedStringWidth and p.text:GetUnboundedStringWidth() or p.text:GetStringWidth()
			p.textW = math.ceil(ns.Num(w) or 0)
		end
		if p.lastTx ~= tx then
			p.text:ClearAllPoints()
			p.text:SetPoint("LEFT", p, "LEFT", tx, 0)
			p.lastTx = tx
		end
		local w = tx + (p.textW or 0)
		p:ClearAllPoints()
		p:SetPoint("LEFT", f, "LEFT", x, 0)
		p:SetSize(w, h)
		p:Show()
		x = x + w + PIECE_GAP
	end
	for i = #shown + 1, #pieces do pieces[i]:Hide(); pieces[i].id = nil end
	M.widgetW = #shown > 0 and (x - PIECE_GAP) or 0
	return M.widgetW
end

local widget = {
	width = function() return M.Layout(M.frame) end,
	create = function(f) M.frame = f end,
}

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
function M:Update()
	M.Read()
	local db = ns:ModuleDB("professions")
	local n = 0
	for _, r in ipairs(rows) do
		if M.Shows(r, db) then n = n + 1; shown[n] = r end
	end
	for i = n + 1, #shown do shown[i] = nil end
	M.line = M.Text(db) -- what the bar shows, as text
	-- the pieces draw it on the bar; the text is only for an empty bar
	obj.text = n == 0 and (#rows == 0 and "No professions" or "Professions") or ""
	ns.API.Refresh(self.ldbName)
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Professions")
	if #rows == 0 then
		ns.TipHint(tip, "You have no professions yet.")
		return
	end
	local db = ns:ModuleDB("professions")
	local anyCap = false
	for _, r in ipairs(rows) do
		local right = r.rank .. "/" .. r.max
		if r.mod > 0 then right = right .. " (+" .. r.mod .. ")" end
		local cap = M.AtCap(r)
		if cap then
			anyCap = true
			right = right .. "  at cap"
		end
		local rr, rg, rb = 1, 1, 1
		if cap and db.markCap then
			local c = type(db.capColor) == "table" and db.capColor or { 1, 0.55, 0.25 }
			rr, rg, rb = c[1] or 1, c[2] or 1, c[3] or 1
		end
		local left = r.name
		if not r.window then left = left .. " |cff8d94a3(no window)|r" end
		tip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, rr, rg, rb)
	end
	if anyCap then
		tip:AddLine(" ")
		ns.TipHint(tip, "At cap: a trainer teaches the next rank, if there is one.")
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "Click a profession: open it. Right-click: every profession.")
end

function M:Available()
	return C_SkillInfo ~= nil and C_SkillInfo.GetNumSkillLines ~= nil and C_SkillInfo.GetSkillLineInfo ~= nil
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Professions", text = "",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function(frame, mouse) M.Click(frame, mouse, nil) end,
	})
	ns.API.RegisterWidget(self.ldbName, widget)
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "TRADE_SKILL_LIST_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Disable() end
