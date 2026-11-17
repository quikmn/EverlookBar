-- Everlook Bar: XP mini bar. A thin bar of fixed width: current XP, rested XP as an overlay, the percentage as text.
-- Hidden at max level (or with XP gain switched off). Event driven: no ticker.
local _, ns = ...
local U = ns.Util

local M = ns:NewModule({
	id = "xp", title = "XP bar", ldbName = ns.PREFIX .. "_XP",
	desc = "A thin experience bar with rested XP and the percentage. Hidden at max level.",
	defaults = { width = 160, decimals = 1, showText = true, textInBar = true },
	place = { group = "center", order = 1 },
})

local obj
M.pctText = ""
local state = { cur = 0, max = 1, rested = 0, level = 1, valid = false }
M.state = state

local function atMax()
	local level = ns.Num(UnitLevel("player"))
	local maxLevel = GetMaxPlayerLevel and ns.Num(GetMaxPlayerLevel())
	if IsXPUserDisabled and IsXPUserDisabled() then return true end
	return level and maxLevel and level >= maxLevel or false
end

function M:Read()
	local cur, max = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player"))
	local rested = ns.Num(GetXPExhaustion and GetXPExhaustion()) or 0
	state.level = ns.Num(UnitLevel("player")) or state.level
	if not cur or not max or max <= 0 then
		state.valid = false
		return
	end
	state.cur, state.max, state.rested, state.valid = cur, max, rested, true
end

function M:Update()
	self:Read()
	local hide = atMax()
	ns.API.SetHidden(self.ldbName, hide)
	local mdb = ns:ModuleDB("xp")
	if not state.valid then
		obj.text = ""
		return
	end
	local pct = state.cur / state.max * 100
	if mdb.showText then
		local d = tonumber(mdb.decimals) or 1
		M.pctText = string.format("%." .. d .. "f%%", pct)
	else
		M.pctText = ""
	end
	-- the percentage sits centred on the bar itself (default) or as text beside it
	obj.text = mdb.textInBar and "" or M.pctText
	-- the widget reads `state`; a changed percentage (text) redraws it, and so does rested XP
	ns.API.Refresh(self.ldbName)
end

local function tooltip(tip)
	ns.TipHeader(tip, "Experience")
	if not state.valid then
		ns.TipHint(tip, "No XP information right now.")
		return
	end
	local pct = state.cur / state.max * 100
	tip:AddDoubleLine("Level " .. state.level, string.format("%s / %s  (%.1f%%)", ns.Thousands(state.cur), ns.Thousands(state.max), pct), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddDoubleLine("To level", ns.Thousands(state.max - state.cur), 0.9, 0.9, 0.9, 1, 1, 1)
	if state.rested > 0 then
		tip:AddDoubleLine("Rested", string.format("%s  (%.1f%% of a level)", ns.Thousands(state.rested), state.rested / state.max * 100), 0.9, 0.9, 0.9, 0.4, 0.6, 1)
	else
		tip:AddDoubleLine("Rested", "none", 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
	end
end

-- The bar itself, through the public widget API (the same path third parties use).
local widget = {
	width = function() return tonumber(ns:ModuleDB("xp").width) or 160 end,
	create = function(f)
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints()
		f.bg:SetTexture(U.WHITE)
		f.bg:SetVertexColor(1, 1, 1, 0.08)
		f.rested = f:CreateTexture(nil, "BORDER")
		f.rested:SetTexture(U.WHITE)
		f.rested:SetVertexColor(0.30, 0.50, 1.00, 0.45)
		f.rested:SetPoint("TOPLEFT")
		f.rested:SetPoint("BOTTOMLEFT")
		f.fill = f:CreateTexture(nil, "ARTWORK")
		f.fill:SetTexture(U.WHITE)
		f.fill:SetVertexColor(0.62, 0.36, 0.95, 0.95)
		f.fill:SetPoint("TOPLEFT")
		f.fill:SetPoint("BOTTOMLEFT")
		f.label = f:CreateFontString(nil, "OVERLAY")
		U.SetFont(f.label, 11, "OUTLINE")
		f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
		f.label:SetTextColor(1, 1, 1, 1)
	end,
	update = function(f)
		local w = tonumber(ns:ModuleDB("xp").width) or 160
		local label = ns:ModuleDB("xp").textInBar and M.pctText or ""
		if f.label and f.label:GetText() ~= label then f.label:SetText(label) end
		if not state.valid then
			f.fill:Hide(); f.rested:Hide()
			return
		end
		local frac = math.max(0, math.min(1, state.cur / state.max))
		local rfrac = math.max(0, math.min(1, (state.cur + state.rested) / state.max))
		f.fill:SetWidth(math.max(0.01, w * frac)); f.fill:SetShown(frac > 0)
		f.rested:SetWidth(math.max(0.01, w * rfrac)); f.rested:SetShown(rfrac > frac)
	end,
}

function M:Enable()
	obj = ns.Plugin(self, { type = "data source", label = "XP", text = "", OnTooltipShow = function(tip) M.Tooltip(tip) end })
	ns.API.RegisterWidget(self.ldbName, widget)
	local function update() M:Update() end
	for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
		"ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
		ns.On(e, self, update)
	end
	self:Update()
end
function M.Tooltip(tip) tooltip(tip) end

function M:Disable() end
