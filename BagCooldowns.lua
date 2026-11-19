-- WoW Forever's client reports the global cooldown as a cooldown for every item in your bags, so after each spell every
-- bag slot spins for about 1.5 seconds (Bagnon, Blizzard's bags, any bag addon that asks the game). This clears an
-- item cooldown that is only the global cooldown; real item cooldowns (potions, Hearthstone, trinkets) still show.
-- A post-hook on CooldownFrame_Set: nothing is replaced, so nothing secure is tainted.
local _, ns = ...

local GCD_SPELL = 61304   -- the game's "Global Cooldown" spell: its cooldown is the GCD itself

local function gcdOf()
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, cd = pcall(C_Spell.GetSpellCooldown, GCD_SPELL)
		if ok and type(cd) == "table" then return cd.startTime, cd.duration end
	end
	if GetSpellCooldown then
		local ok, s, d = pcall(GetSpellCooldown, GCD_SPELL)
		if ok then return s, d end
	end
end

-- A bag slot's button: Blizzard's (GetBagID) or a bag addon's (Bagnon: GetBag; most others keep a bag id field)
local function isBagSlot(button)
	return type(button) == "table" and (button.GetBagID ~= nil or button.GetBag ~= nil or button.bagID ~= nil or button.bag ~= nil)
end

local function onSet(cd, start, duration)
	if not (ns.db and ns.db.hideBagGCD ~= false) then return end
	if type(start) ~= "number" or type(duration) ~= "number" or duration <= 0 or duration > 1.6 then return end
	local button = cd and cd.GetParent and cd:GetParent()
	if not isBagSlot(button) then return end
	-- only when it matches the running global cooldown (a real 1-second item cooldown would not)
	local gs, gd = gcdOf()
	if gs and gd and gd > 0 and math.abs(gs - start) > 0.05 then return end
	cd:Clear()
	if cd.Hide then cd:Hide() end
	-- bag addons dim an item while its cooldown runs: undo that too
	if SetItemButtonTextureVertexColor then pcall(SetItemButtonTextureVertexColor, button, 1, 1, 1) end
end

if type(CooldownFrame_Set) == "function" then hooksecurefunc("CooldownFrame_Set", onSet) end
