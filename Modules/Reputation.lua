-- Everlook Bar: reputation bar. The XP bar's look for one faction, coloured by standing with the game's own colours
-- (FACTION_BAR_COLORS: red hostile, orange unfriendly, yellow neutral, green friendly and up). It follows the game's
-- watched faction (the default) or a faction picked in the settings or with a right-click on the bar. Never hidden:
-- at max level the XP bar steps aside and this one keeps its place next to it. Event driven: no ticker.
local _, ns = ...
local U = ns.Util
local UI = ns.UI

local WATCHED = "watched"
local WATCHED_TEXT = "Watched faction (the game's own)"

local M = ns:NewModule({
	id = "reputation", title = "Reputation bar", ldbName = ns.PREFIX .. "_Reputation",
	desc = "A thin bar for one faction, coloured by standing: the game's watched faction or one you pick.",
	defaults = { faction = WATCHED, width = 160, showName = true, showStanding = true, showValue = false,
		showPercent = false, textInBar = true },
	place = { group = "center", order = 2 },
})
M.WATCHED = WATCHED

local obj
M.label = ""
local state = { valid = false, name = "", reaction = 4, value = 0, max = 0, watched = true }
M.state = state

------------------------------------------------------------------------
-- Standings and colours
------------------------------------------------------------------------
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
-- Blizzard's classic faction colours, used only when FACTION_BAR_COLORS is missing.
local FALLBACK = {
	{ 0.80, 0.30, 0.22 }, { 0.80, 0.30, 0.22 }, { 0.75, 0.27, 0.00 }, { 0.90, 0.70, 0.00 },
	{ 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 },
}

local function clampReaction(r)
	r = ns.Num(r) or 4
	return math.max(1, math.min(8, math.floor(r)))
end

function M.StandingName(r)
	r = ns.Num(r)
	if not r or r < 1 or r > 8 then return "" end
	return ns.Str(_G["FACTION_STANDING_LABEL" .. r]) or STANDINGS[r]
end

-- The bar colour for a standing (1 Hated .. 8 Exalted): the game's own when it has them.
function M.Color(reaction)
	local r = clampReaction(reaction)
	local c = type(FACTION_BAR_COLORS) == "table" and FACTION_BAR_COLORS[r]
	if type(c) == "table" and not ns.IsSecret(c) then
		local cr, cg, cb = ns.Num(c.r), ns.Num(c.g), ns.Num(c.b)
		if cr and cg and cb then return cr, cg, cb end
	end
	local f = FALLBACK[r]
	return f[1], f[2], f[3]
end

------------------------------------------------------------------------
-- Reading a faction
------------------------------------------------------------------------
local function usable(d)
	if type(d) ~= "table" or ns.IsSecret(d) then return nil end
	local name = ns.Str(d.name)
	if not name or name == "" then return nil end
	return d
end

-- The faction to show: the one chosen in settings, else (or when that one is unknown) the game's watched faction.
-- Returns the data and whether it is the watched one.
function M.Data()
	local R = C_Reputation
	if not R then return nil, true end
	local want = ns:ModuleDB("reputation").faction
	if type(want) == "number" and R.GetFactionDataByID then
		local d = usable(R.GetFactionDataByID(want))
		if d then return d, false end
	end
	return usable(R.GetWatchedFactionData and R.GetWatchedFactionData()), true
end

-- Fill `out` from a FactionData: value and max within the current standing.
function M.Compute(d, out)
	out.valid = false
	out.name = d and ns.Str(d.name) or ""
	out.id = d and ns.Num(d.factionID)
	if not d then return out end
	local cur, lo, hi = ns.Num(d.currentStanding), ns.Num(d.currentReactionThreshold), ns.Num(d.nextReactionThreshold)
	local r = ns.Num(d.reaction)
	if not (cur and lo and hi and r) then return out end
	out.reaction = r
	out.value = math.max(0, cur - lo)
	out.max = math.max(0, hi - lo)
	out.valid = true
	return out
end

-- How full the bar is, 0..1. A standing with no room left (the top) is a full bar.
function M.Frac(s)
	if not s.valid then return 0 end
	if s.max <= 0 then return 1 end
	return math.max(0, math.min(1, s.value / s.max))
end

-- The fill's width in a bar `width` pixels wide (never 0: a texture of width 0 shows whole).
function M.FillWidth(s, width)
	return math.max(0.01, (tonumber(width) or 160) * M.Frac(s))
end

-- The text: name, standing, value/max, percent, as the settings say.
function M.Text(s, db)
	if not s.valid then
		if s.name ~= "" then return s.name end
		return s.watched and "No faction watched" or "Pick a faction"
	end
	local t = {}
	if db.showStanding then t[#t + 1] = M.StandingName(s.reaction) end
	if db.showValue and s.max > 0 then t[#t + 1] = ns.Thousands(s.value) .. "/" .. ns.Thousands(s.max) end
	if db.showPercent then t[#t + 1] = math.floor(M.Frac(s) * 100) .. "%" end
	local rest = table.concat(t, " ")
	if db.showName then
		if rest ~= "" then return s.name .. ": " .. rest end
		return s.name
	end
	return rest
end

function M:Update()
	if #M.choices == 1 then M.Scan() end -- the faction list for "/ebar reputation.faction <name>", once
	local d, watched = M.Data()
	M.Compute(d, state)
	state.watched = watched
	local db = ns:ModuleDB("reputation")
	M.label = M.Text(state, db)
	obj.text = db.textInBar and "" or M.label
	ns.API.Refresh(self.ldbName)
end

------------------------------------------------------------------------
-- The faction list (settings choice and right-click menu)
------------------------------------------------------------------------
M.choices = { { value = WATCHED, text = WATCHED_TEXT } } -- the setting's choices for chat, refilled in place
M.groups = {}

local function byName(a, b) return a.text:lower() < b.text:lower() end

-- Every faction the player knows, with its header. Collapsed headers are opened for the read and closed again, so
-- the reputation panel looks as it did.
function M.Scan()
	local R = C_Reputation
	local list = {}
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return list end
	local opened = {}
	local header = "Other"
	local n = ns.Num(R.GetNumFactions()) or 0
	local i = 1
	while i <= n and i <= 500 do
		local d = R.GetFactionDataByIndex(i)
		if type(d) == "table" and not ns.IsSecret(d) then
			local name, id = ns.Str(d.name), ns.Num(d.factionID)
			if d.isHeader then
				if d.isCollapsed and R.ExpandFactionHeader then
					R.ExpandFactionHeader(i)
					opened[name or ("#" .. i)] = true
					n = ns.Num(R.GetNumFactions()) or n
				end
				if d.isHeaderWithRep and id and name then
					list[#list + 1] = { value = id, text = name, group = d.isChild and header or name }
				end
				if name then header = name end
			elseif id and name then
				list[#list + 1] = { value = id, text = name, group = header }
			end
		end
		i = i + 1
	end
	if next(opened) and R.CollapseFactionHeader then
		for j = ns.Num(R.GetNumFactions()) or 0, 1, -1 do -- from the bottom: earlier rows keep their index
			local d = R.GetFactionDataByIndex(j)
			if type(d) == "table" and not ns.IsSecret(d) and d.isHeader and opened[ns.Str(d.name) or ("#" .. j)] then
				R.CollapseFactionHeader(j)
			end
		end
	end
	-- the chat choices: watched first, then every faction alphabetically
	for k = #M.choices, 2, -1 do M.choices[k] = nil end
	local flat = {}
	for _, f in ipairs(list) do flat[#flat + 1] = f end
	table.sort(flat, byName)
	for _, f in ipairs(flat) do M.choices[#M.choices + 1] = { value = f.value, text = f.text } end
	return list, flat
end

-- The rows a list may have before it runs off the screen.
local function maxRows()
	local h = UIParent and ns.Num(UIParent:GetHeight()) or 768
	return math.max(10, math.floor(h / 22) - 2)
end

-- The list to pick from: grouped under headers (game order, factions A-Z) when it fits on screen, else A-Z without
-- headers, else one row per header that opens that header's factions.
function M.Items(rowsMax)
	rowsMax = rowsMax or maxRows()
	local list, flat = M.Scan()
	local groups, order = {}, {}
	for _, f in ipairs(list) do
		local g = groups[f.group]
		if not g then
			g = { name = f.group, items = {} }
			groups[f.group] = g
			order[#order + 1] = g
		end
		g.items[#g.items + 1] = { value = f.value, text = f.text }
	end
	wipe(M.groups)
	local grouped = { { value = WATCHED, text = WATCHED_TEXT } }
	for gi, g in ipairs(order) do
		table.sort(g.items, byName)
		M.groups[gi] = g
		grouped[#grouped + 1] = { title = true, text = g.name }
		for _, it in ipairs(g.items) do grouped[#grouped + 1] = it end
	end
	if #grouped <= rowsMax then return grouped end
	local plain = { { value = WATCHED, text = WATCHED_TEXT } }
	for _, f in ipairs(flat) do plain[#plain + 1] = { value = f.value, text = f.text } end
	if #plain <= rowsMax then return plain end
	local top = { { value = WATCHED, text = WATCHED_TEXT } }
	for gi, g in ipairs(order) do top[#top + 1] = { value = "group:" .. gi, text = g.name .. "  >" } end
	return top
end

-- What a choice is called (the settings dropdown shows it).
function M.ChoiceText(v)
	if v == WATCHED or v == nil then return WATCHED_TEXT end
	local R = C_Reputation
	local d = type(v) == "number" and R and R.GetFactionDataByID and usable(R.GetFactionDataByID(v))
	return d and ns.Str(d.name) or ("Faction " .. tostring(v))
end

-- Track `v` (WATCHED or a factionID). A header row ("group:N") opens that header's factions instead.
function M.Pick(v)
	local g = type(v) == "string" and tonumber(v:match("^group:(%d+)$"))
	if g then
		local grp = M.groups[g]
		if not grp then return end
		local items = { { title = true, text = grp.name } }
		for _, it in ipairs(grp.items) do items[#items + 1] = it end
		UI.OpenPopup(nil, items, ns:ModuleDB("reputation").faction, M.Pick, { atCursor = true, width = 260 })
		return
	end
	if v ~= WATCHED and type(v) ~= "number" then return end
	ns:ModuleDB("reputation").faction = v
	if M.running then M:Update() end
	if ns.app and ns.app:IsShown() and ns.Options then ns.Options:Refresh() end
end

function M.Menu(owner)
	UI.OpenPopup(owner, M.Items(), ns:ModuleDB("reputation").faction, M.Pick, { atCursor = true, width = 260 })
end

------------------------------------------------------------------------
-- Tooltip, clicks, the bar
------------------------------------------------------------------------
function M.Tooltip(tip)
	ns.TipHeader(tip, "Reputation")
	if not state.valid then
		ns.TipHint(tip, state.watched and "No faction is watched. Right-click to pick one, or tick \"Show as experience bar\" in the reputation panel."
			or "That faction is not known on this character.")
		tip:AddLine(" ")
		ns.TipHint(tip, "Click: open the reputation panel. Right-click: choose the faction.")
		return
	end
	local r, g, b = M.Color(state.reaction)
	tip:AddLine(state.name, 1, 1, 1)
	tip:AddDoubleLine("Standing", M.StandingName(state.reaction), 0.9, 0.9, 0.9, r, g, b)
	if state.max > 0 then
		tip:AddDoubleLine("Progress", string.format("%s / %s  (%d%%)", ns.Thousands(state.value), ns.Thousands(state.max),
			math.floor(M.Frac(state) * 100)), 0.9, 0.9, 0.9, 1, 1, 1)
		local nextName = M.StandingName(state.reaction + 1)
		if nextName ~= "" then
			tip:AddDoubleLine("To " .. nextName, ns.Thousands(state.max - state.value), 0.9, 0.9, 0.9, 1, 1, 1)
		end
	else
		tip:AddDoubleLine("Progress", "the highest standing", 0.9, 0.9, 0.9, 1, 1, 1)
	end
	tip:AddLine(" ")
	ns.TipHint(tip, state.watched and "Following the game's watched faction." or "Chosen in Everlook Bar.")
	ns.TipHint(tip, "Click: open the reputation panel. Right-click: choose the faction.")
end

function M.Click(frame, mouse)
	if mouse == "RightButton" then M.Menu(frame) return end
	if ToggleCharacter then ToggleCharacter("ReputationFrame") end
end

local function db() return ns:ModuleDB("reputation") end

local widget = {
	width = function() return tonumber(db().width) or 160 end,
	create = function(f)
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints()
		f.bg:SetTexture(U.WHITE)
		f.bg:SetVertexColor(1, 1, 1, 0.08)
		f.fill = f:CreateTexture(nil, "ARTWORK")
		f.fill:SetTexture(U.WHITE)
		f.fill:SetPoint("TOPLEFT")
		f.fill:SetPoint("BOTTOMLEFT")
		f.label = f:CreateFontString(nil, "OVERLAY")
		U.SetFont(f.label, 11, "OUTLINE")
		f.label:SetPoint("LEFT", f, "LEFT", 3, 0)
		f.label:SetPoint("RIGHT", f, "RIGHT", -3, 0)
		f.label:SetWordWrap(false)
		f.label:SetTextColor(1, 1, 1, 1)
	end,
	update = function(f)
		local w = tonumber(db().width) or 160
		local label = db().textInBar and M.label or ""
		if f.label and f.label:GetText() ~= label then f.label:SetText(label) end
		if not state.valid then f.fill:Hide() return end
		local r, g, b = M.Color(state.reaction)
		f.fill:SetVertexColor(r, g, b, 0.95)
		f.fill:SetWidth(M.FillWidth(state, w))
		f.fill:SetShown(M.Frac(state) > 0)
	end,
}

function M:Available()
	return C_Reputation ~= nil and (C_Reputation.GetWatchedFactionData ~= nil or C_Reputation.GetFactionDataByID ~= nil)
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Rep", text = "",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function(frame, mouse) M.Click(frame, mouse) end,
	})
	ns.API.RegisterWidget(self.ldbName, widget)
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "UPDATE_FACTION", "FACTION_STANDING_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Disable() end
