-- Everlook Bar: durability. The lowest equipped item in percent; every slot in the tooltip. Event driven.
local _, ns = ...

local M = ns:NewModule({
	id = "durability", title = "Durability", ldbName = ns.PREFIX .. "_Durability",
	desc = "Your most worn item in percent; every slot in the tooltip.",
	defaults = {},
	place = { group = "right", order = 3 },
})

local obj
-- slot id, global name of the slot label
local SLOTS = {
	{ 1, "HEADSLOT", "Head" }, { 3, "SHOULDERSLOT", "Shoulders" }, { 5, "CHESTSLOT", "Chest" },
	{ 6, "WAISTSLOT", "Waist" }, { 7, "LEGSSLOT", "Legs" }, { 8, "FEETSLOT", "Feet" }, { 9, "WRISTSLOT", "Wrists" },
	{ 10, "HANDSSLOT", "Hands" }, { 15, "BACKSLOT", "Back" }, { 16, "MAINHANDSLOT", "Main hand" },
	{ 17, "SECONDARYHANDSLOT", "Off hand" }, { 18, "RANGEDSLOT", "Ranged" },
}
local rows = {} -- reused: [i] = { name, pct } for slots with durability
M.rows = rows

local function pctColor(p)
	if p >= 60 then return "|cff62cf88" end
	if p >= 25 then return "|cffffd25a" end
	return "|cffef5d5d"
end

function M:Update()
	local lowest
	local n = 0
	for _, s in ipairs(SLOTS) do
		local cur, max = GetInventoryItemDurability(s[1])
		cur, max = ns.Num(cur), ns.Num(max)
		if cur and max and max > 0 then
			n = n + 1
			local r = rows[n] or {}
			rows[n] = r
			r.name, r.pct = ns.Str(_G[s[2]]) or s[3], cur / max * 100
			if not lowest or r.pct < lowest then lowest = r.pct end
		end
	end
	for i = n + 1, #rows do rows[i] = nil end
	if not lowest then
		obj.text = "-"
	else
		local p = math.floor(lowest + 0.5)
		obj.text = pctColor(p) .. p .. "%|r"
	end
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Durability")
	if #rows == 0 then ns.TipHint(tip, "Nothing equipped that can wear out.") return end
	for _, r in ipairs(rows) do
		local p = math.floor(r.pct + 0.5)
		tip:AddDoubleLine(r.name, pctColor(p) .. p .. "%|r", 0.9, 0.9, 0.9, 1, 1, 1)
	end
end

function M:Enable()
	if not GetInventoryItemDurability then return end
	obj = ns.Plugin(self, {
		type = "data source", label = "Durability", text = "", icon = "Interface\\Icons\\Trade_BlackSmithing",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		-- the character panel opens through the game's own micro button (secure; SecureClick.lua)
		ebarSecure = ns.SecureClick.ClickOf("CharacterMicroButton"),
		OnClick = ns.SecureClick.Fallback(function(_, mouse)
			if mouse == "LeftButton" and ToggleCharacter then ToggleCharacter("PaperDollFrame") end
		end),
	})
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Available() return GetInventoryItemDurability ~= nil end
function M:Disable() end
