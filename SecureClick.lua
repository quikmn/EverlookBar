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
-- to UIParent, never to the plugin's button), so the bar's buttons stay free to move and resize in combat. When
-- combat starts every such plugin on screen gets a cover, so its click works all fight wherever the mouse comes from;
-- out of combat the covers follow their buttons when a bar is laid out again.
local _, ns = ...
local S = {}
ns.SecureClick = S

local pool = {}      -- the secure cover buttons, reused (one per plugin at most)
local coverOf = {}   -- [plugin button] = its cover while it has one
local owner          -- the plugin button covered for the mouse right now

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
				UIErrorsFrame:AddMessage(ns.NAME .. ": this opens after combat (or use its key).", 1, 0.3, 0.3)
			end
			return
		end
		return fn(...)
	end
end

local function hideTip(b)
	if b and b.shownTip == GameTooltip then GameTooltip:Hide(); b.shownTip = nil end
end

local function covers(b)
	local rec = b and b.rec
	return rec and rec.obj and type(rec.obj.ebarSecure) == "function"
end

-- A free cover (or a new one). Each runs its plugin's scripts for everything but the secure left click.
local function make()
	for _, c in ipairs(pool) do if not c.owner then return c end end
	local n = #pool + 1
	local c = CreateFrame("Button", ns.PREFIX .. "SecureClick" .. (n > 1 and n or ""), UIParent, "SecureActionButtonTemplate")
	pool[n] = c
	c:RegisterForClicks("AnyUp")
	c:Hide()
	c:SetScript("OnEnter", function(self)
		local b = self.owner
		local fn = b and b:GetScript("OnEnter")
		if fn then fn(b) end
	end)
	c:SetScript("OnLeave", function(self)
		local b = self.owner
		local fn = b and b:GetScript("OnLeave")
		if fn then fn(b) end
		if b then S:Uncover(b) end
	end)
	-- A plugin may say whether its panel is open (ebarOpened). Then the state before the click is noted, and if the
	-- game's button changed nothing (a client whose micro button doesn't open it), the plugin's own click runs.
	c:SetScript("PreClick", function(self)
		local b = self.owner
		local obj = b and b.rec and b.rec.obj
		self.before = nil
		if obj and type(obj.ebarOpened) == "function" then
			local ok, open = pcall(obj.ebarOpened)
			if ok then self.before = open and true or false end
		end
	end)
	-- Runs after the secure click. The left button was handled securely; the others go to the plugin.
	c:SetScript("PostClick", function(self, mouse)
		local b = self.owner
		if not b then return end
		hideTip(b)
		if mouse == "LeftButton" and self:GetAttribute("type1") then
			local obj = b.rec and b.rec.obj
			local was = self.before
			if was ~= nil and obj and type(obj.ebarOpened) == "function" then
				C_Timer.After(0.15, function()
					local ok, open = pcall(obj.ebarOpened)
					if ok and (open and true or false) == was and not InCombatLockdown() then
						local fn = b:GetScript("OnClick")
						if fn then fn(b, "LeftButton") end
					end
				end)
			end
			-- the panel changed: what the next click does may change too (open on a tab, or close it)
			C_Timer.After(0.2, function()
				if coverOf[b] == self and not InCombatLockdown() then S:Place(b, self) end
			end)
			return
		end
		local fn = b:GetScript("OnClick")
		if fn then fn(b, mouse) end
	end)
	return c
end

-- Point cover c at plugin button b: its secure click and the button's rectangle, in UIParent's coordinates (never
-- anchored to the button, so the bar's buttons stay free to move and resize in combat). Out of combat only.
function S:Place(b, c)
	if InCombatLockdown() then return false end
	local rec = b and b.rec
	local fn = rec and rec.obj and rec.obj.ebarSecure
	if type(fn) ~= "function" then return false end
	local ok, attrs = ns.SafeCall(rec, fn)
	if not ok or type(attrs) ~= "table" then return false end
	local l, bt, w, h = ns.Num(b:GetLeft()), ns.Num(b:GetBottom()), ns.Num(b:GetWidth()), ns.Num(b:GetHeight())
	if not (l and bt and w and h) or w <= 0 or h <= 0 then return false end
	c:SetAttribute("type1", attrs.type)
	c:SetAttribute("clickbutton1", attrs.clickbutton)
	c:SetAttribute("macrotext1", attrs.macrotext)
	local bs, us = ns.Num(b:GetEffectiveScale()) or 1, ns.Num(UIParent:GetEffectiveScale()) or 1
	local k = bs / us
	c:ClearAllPoints()
	c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bt * k)
	c:SetSize(w * k, h * k)
	c:SetFrameStrata(b:GetFrameStrata() or "MEDIUM")
	c:SetFrameLevel((ns.Num(b:GetFrameLevel()) or 1) + 10)
	return true
end

-- Lay a cover over plugin button b, if its plugin has a secure left click. Out of combat only.
-- forCombat: laid when combat starts (not for the mouse), so it works all fight long.
function S:Cover(b, forCombat)
	if InCombatLockdown() then return false end
	if not forCombat and ns.Unlock and ns.Unlock.active then return false end
	if not covers(b) then return false end
	local c = coverOf[b] or make()
	if not self:Place(b, c) then
		if coverOf[b] == c then self:Uncover(b) end
		return false
	end
	c.owner, coverOf[b] = b, c
	if not forCombat then owner = b end
	c:Show()
	return true
end

-- Take the cover away from b (default: the one under the mouse). In combat it stays and keeps working; it goes when
-- combat ends, unless the mouse is on it then.
function S:Uncover(b)
	b = b or owner
	local c = b and coverOf[b]
	if not c then if b == owner then owner = nil end return end
	if InCombatLockdown() then
		ns.AfterCombat("secureclick", function() S:UncoverIdle() end)
		return
	end
	c:Hide()
	c:ClearAllPoints()
	c.owner, coverOf[b] = nil, nil
	if owner == b then owner = nil end
end

-- After combat: drop every cover the mouse is not on.
function S:UncoverIdle()
	for b, c in pairs(coverOf) do
		if not (c:IsShown() and c:IsMouseOver()) then S:Uncover(b) end
	end
end

-- The bar was laid out again: covers follow their buttons (out of combat), and go when a button went.
function S:Sync()
	if InCombatLockdown() then return end
	for b, c in pairs(coverOf) do
		if not (b:IsVisible() and covers(b) and self:Place(b, c)) then self:Uncover(b) end
	end
end

-- Combat starts (the last moment protected frames can be changed): cover every secure plugin on screen, so its
-- left click works in combat too, wherever the mouse came from. Combat ends: covers the mouse is not on go away, and
-- a plugin under the mouse gets its cover (it was entered during combat, when none could be laid).
ns.On("PLAYER_REGEN_DISABLED", S, function()
	if not ns.Host then return end
	for _, rec in pairs(ns.Host.plugins) do
		local b = rec.button
		if b and b:IsVisible() and covers(b) and not coverOf[b] then S:Cover(b, true) end
	end
end)
ns.On("PLAYER_REGEN_ENABLED", S, function()
	S:UncoverIdle()
	if not ns.Host then return end
	for _, rec in pairs(ns.Host.plugins) do
		local b = rec.button
		if b and b:IsVisible() and covers(b) and b:IsMouseOver() then S:Cover(b) end
	end
end)

function S:Owner() return owner end
function S:Frame() return (owner and coverOf[owner]) or pool[1] end
function S:Covers() return coverOf end -- tests
