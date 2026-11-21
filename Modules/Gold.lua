-- Everlook Bar: gold. Your money, and in the tooltip how much it changed this session. Nothing per hour.
local _, ns = ...

local M = ns:NewModule({
	id = "gold", title = "Gold", ldbName = ns.PREFIX .. "_Gold",
	desc = "Your money; the change this session in the tooltip.",
	defaults = { copper = false },
	place = { group = "right", order = 5 },
})

local obj
local start, money

local G, S, C = "|cffffd25ag|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

-- 123456 -> "12g 34s 56c" (copper optional; zeros left out).
function M.Format(copper, withCopper)
	copper = math.floor(math.abs(copper or 0))
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = ns.Thousands(g) .. G end
	if s > 0 or (g > 0 and not withCopper) then parts[#parts + 1] = s .. S end
	if withCopper or (g == 0 and s == 0) then parts[#parts + 1] = c .. C end
	return table.concat(parts, " ")
end

function M:Update()
	local m = ns.Num(GetMoney())
	if not m then return end
	money = m
	-- the session starts once the character is in the world: before that the game may still say 0 (and the whole
	-- purse would show as this session's gain)
	if not start and (not IsLoggedIn or IsLoggedIn()) then start = m end
	obj.text = M.Format(m, ns:ModuleDB("gold").copper)
end

function M.ResetSession() start, money = nil, nil end -- tests

function M.Tooltip(tip)
	ns.TipHeader(tip, "Gold")
	if not money then return end
	tip:AddDoubleLine("Now", M.Format(money, true), 0.9, 0.9, 0.9, 1, 1, 1)
	local diff = money - (start or money)
	local txt = diff == 0 and "no change" or ((diff > 0 and "|cff62cf88+" or "|cffef5d5d-") .. "|r" .. M.Format(diff, true))
	tip:AddDoubleLine("This session", txt, 0.9, 0.9, 0.9, 1, 1, 1)
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Gold", text = "", icon = "Interface\\Icons\\INV_Misc_Coin_01",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
	})
	ns.On("PLAYER_MONEY", self, function() M:Update() end)
	ns.On("PLAYER_ENTERING_WORLD", self, function() M:Update() end)
	self:Update()
end

function M:Disable() end
