-- Everlook Bar: bags. Free/total slots in your normal bags; profession bags (herb, enchanting, soul, quiver...)
-- counted apart in the tooltip. Bag events are bursty, so updates are coalesced to one per frame.
local _, ns = ...

local M = ns:NewModule({
	id = "bags", title = "Bags", ldbName = ns.PREFIX .. "_Bags",
	desc = "Free and total bag slots; profession bags listed apart.",
	defaults = { style = "free/total" },
	place = { group = "right", order = 2 },
})

local obj
local special = {} -- reused rows: { name, free, total }
local free, total = 0, 0

local function bagCount()
	return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 -- the reagent bag (bag 5) too
end

function M:Update()
	free, total = 0, 0
	local n = 0
	local C = C_Container
	for bag = 0, bagCount() do
		local slots = ns.Num(C.GetContainerNumSlots(bag)) or 0
		if slots > 0 then
			local f, family = C.GetContainerNumFreeSlots(bag)
			f, family = ns.Num(f) or 0, ns.Num(family) or 0
			if family == 0 then
				free, total = free + f, total + slots
			else
				n = n + 1
				local r = special[n] or {}
				special[n] = r
				r.name = ns.Str(C.GetBagName and C.GetBagName(bag)) or "Profession bag"
				r.free, r.total = f, slots
			end
		end
	end
	for i = n + 1, #special do special[i] = nil end
	local style = ns:ModuleDB("bags").style
	local col = free == 0 and "|cffef5d5d" or (free <= 4 and "|cffffd25a" or "")
	local close = col ~= "" and "|r" or ""
	if style == "free" then
		obj.text = col .. free .. close
	elseif style == "used/total" then
		obj.text = col .. (total - free) .. close .. "/" .. total
	else
		obj.text = col .. free .. close .. "/" .. total
	end
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Bags")
	tip:AddDoubleLine("Free", free .. " of " .. total, 0.9, 0.9, 0.9, 1, 1, 1)
	if #special > 0 then
		tip:AddLine(" ")
		tip:AddLine("Profession bags (not counted above)", 0.7, 0.7, 0.7)
		for _, r in ipairs(special) do
			tip:AddDoubleLine(r.name, r.free .. " of " .. r.total .. " free", 0.9, 0.9, 0.9, 1, 1, 1)
		end
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "Click: open your bags.")
end

function M:Available() return C_Container ~= nil and C_Container.GetContainerNumSlots ~= nil end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Bags", text = "", icon = "Interface\\Icons\\INV_Misc_Bag_08",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		-- the bags open through the game's own backpack button (secure; SecureClick.lua): bag frames opened from addon
		-- code are tainted, and an item clicked in them in combat can then be blocked
		ebarSecure = ns.SecureClick.ClickOf("MainMenuBarBackpackButton"),
		OnClick = ns.SecureClick.Fallback(function(_, mouse)
			if mouse ~= "LeftButton" then return end
			if ToggleAllBags then ToggleAllBags() elseif ToggleBackpack then ToggleBackpack() end
		end),
	})
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "BAG_SLOT_FLAGS_UPDATED" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Disable() end
