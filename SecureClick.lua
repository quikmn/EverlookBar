-- Everlook Bar: opening Blizzard panels without taint.
--
-- Why: a panel opened from addon code runs its OnShow "tainted". The character panel's OnShow calls
-- ShowStatusBarText on the player frame's health and mana bars, which writes their lockShow field. Written under
-- taint, that field taints every later read: hovering the player frame then fails with "attempt to compare a secret
-- number value (execution tainted by 'EverlookBar')" in TextStatusBar.lua (the saved error shows lockShow=1 and a
-- stack that starts in the bar's own OnEnter, with no Everlook Bar code in it).
--
-- How: a built-in plugin that opens a Blizzard panel gives its data object an `ebarSecure` function. When the mouse
-- enters its button (out of combat), one secure action button is laid over it: its left click "clicks" the game's own
-- micro button (or runs a /click macro), so the panel opens from secure code, exactly as if the micro button had been
-- clicked. Other mouse buttons go on to the plugin's normal OnClick. The cover sits at absolute coordinates (anchored
-- to UIParent, never to the plugin's button), so the bar's buttons stay free to move and resize in combat.
local _, ns = ...
local S = {}
ns.SecureClick = S

local cover   -- the secure button
local owner   -- the plugin button it covers

-- A micro button (or any frame) by global name, if the game has it.
function S.Button(name)
	local b = _G[name]
	if type(b) == "table" and b.Click then return b end
end

-- The character panel's tab whose text is `label` (Reputation sits on tab 2 on retail-style clients, tab 3 on
-- classic ones), as "CharacterFrameTabN".
function S.CharacterTab(label)
	if not label then return end
	for i = 1, 8 do
		local tab = _G["CharacterFrameTab" .. i]
		if not tab then break end
		local t = tab.GetText and tab:GetText()
		if t == nil and tab.Text and tab.Text.GetText then t = tab.Text:GetText() end
		if ns.Str(t) == label then return "CharacterFrameTab" .. i, tab end
	end
end

-- What a left click does on these plugins. Each returns attributes ({ type = "click", clickbutton = frame } or
-- { type = "macro", macrotext = "..." }) or nil when the client has no secure way (the plugin's own OnClick runs).
function S.ClickOf(name)
	return function()
		local b = S.Button(name)
		if b then return { type = "click", clickbutton = b } end
	end
end

-- The character panel on one of its tabs (by the tab's text).
function S.CharacterPanelOn(label)
	return function()
		local micro = S.Button("CharacterMicroButton")
		if not micro then return end
		local tabName = S.CharacterTab(label)
		if not tabName then return { type = "click", clickbutton = micro } end
		local frame = CharacterFrame
		local open = frame and frame.IsShown and frame:IsShown()
		if open then
			local tab = _G[tabName]
			local id = tab and tab.GetID and tab:GetID()
			local sel = frame.selectedTab or (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(frame))
			if sel ~= nil and id ~= nil and sel == id then
				return { type = "macro", macrotext = "/click CharacterMicroButton" } -- open on that tab: close it
			end
			return { type = "macro", macrotext = "/click " .. tabName }
		end
		return { type = "macro", macrotext = "/click CharacterMicroButton\n/click " .. tabName }
	end
end

-- A plugin's click that has no secure way at the moment (no cover: the mouse came in during combat, or the client
-- lacks the micro button). Out of combat it runs fn; in combat it says so instead of tainting the panel.
function S.Fallback(fn)
	return function(...)
		if InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage(ns.NAME .. ": opens after combat (or move the mouse off and back on).", 1, 0.3, 0.3)
			end
			return
		end
		return fn(...)
	end
end

local function hideTip(b)
	if b and b.shownTip == GameTooltip then GameTooltip:Hide(); b.shownTip = nil end
end

local function make()
	if cover then return cover end
	cover = CreateFrame("Button", ns.PREFIX .. "SecureClick", UIParent, "SecureActionButtonTemplate")
	cover:RegisterForClicks("AnyUp")
	cover:Hide()
	cover:SetScript("OnEnter", function()
		local b = owner
		local fn = b and b:GetScript("OnEnter")
		if fn then fn(b) end
	end)
	cover:SetScript("OnLeave", function()
		local b = owner
		local fn = b and b:GetScript("OnLeave")
		if fn then fn(b) end
		S:Uncover()
	end)
	-- Runs after the secure click. The left button was handled securely; the others go to the plugin.
	cover:SetScript("PostClick", function(self, mouse)
		local b = owner
		if not b then return end
		hideTip(b)
		if mouse == "LeftButton" and self:GetAttribute("type1") then return end
		local fn = b:GetScript("OnClick")
		if fn then fn(b, mouse) end
	end)
	return cover
end

-- Lay the cover over plugin button b, if its plugin has a secure left click. Out of combat only.
function S:Cover(b)
	if InCombatLockdown() then return false end
	if ns.Unlock and ns.Unlock.active then return false end
	local rec = b and b.rec
	local fn = rec and rec.obj and rec.obj.ebarSecure
	if type(fn) ~= "function" then return false end
	local ok, attrs = ns.SafeCall(rec, fn)
	if not ok or type(attrs) ~= "table" then return false end
	local c = make()
	c:SetAttribute("type1", attrs.type)
	c:SetAttribute("clickbutton1", attrs.clickbutton)
	c:SetAttribute("macrotext1", attrs.macrotext)
	-- absolute place: same rectangle as the button, in UIParent's coordinates
	local l, bt, w, h = ns.Num(b:GetLeft()), ns.Num(b:GetBottom()), ns.Num(b:GetWidth()), ns.Num(b:GetHeight())
	if not (l and bt and w and h) then return false end
	local bs, us = ns.Num(b:GetEffectiveScale()) or 1, ns.Num(UIParent:GetEffectiveScale()) or 1
	local k = bs / us
	c:ClearAllPoints()
	c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bt * k)
	c:SetSize(w * k, h * k)
	c:SetFrameStrata(b:GetFrameStrata() or "MEDIUM")
	c:SetFrameLevel((ns.Num(b:GetFrameLevel()) or 1) + 10)
	owner = b
	c:Show()
	return true
end

-- Take the cover away (out of combat; in combat it stays and keeps working, and goes when combat ends).
function S:Uncover()
	if not cover or not cover:IsShown() then owner = nil return end
	if InCombatLockdown() then
		ns.AfterCombat("secureclick", function() S:Uncover() end)
		return
	end
	cover:Hide()
	cover:ClearAllPoints()
	owner = nil
end

function S:Owner() return owner end
function S:Frame() return cover end
