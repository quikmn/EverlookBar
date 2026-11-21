-- EverlookDB Bar: clock. Off by default. Local or realm time; the text changes once a minute.
local _, ns = ...

local M = ns:NewModule({
	id = "clock", title = "Clock", ldbName = ns.PREFIX .. "_Clock", default = false,
	desc = "The time, local or realm. Off by default.",
	defaults = { realm = false, h24 = true },
	place = { group = "right", order = 9 },
})

local obj
local lastKey = -1

-- hour, minute now (realm time from the server, or this computer's).
function M.Now(realm)
	if realm and GetGameTime then
		local h, m = GetGameTime()
		return ns.Num(h) or 0, ns.Num(m) or 0
	end
	local h, m = ns.LocalClock()
	return h, m
end

function M.Format(h, m, h24)
	if h24 then return string.format("%02d:%02d", h, m) end
	local suffix = h >= 12 and " PM" or " AM"
	local hh = h % 12
	if hh == 0 then hh = 12 end
	return string.format("%d:%02d%s", hh, m, suffix)
end

function M:Tick()
	local mdb = ns:ModuleDB("clock")
	local h, m = M.Now(mdb.realm)
	local key = h * 60 + m + (mdb.h24 and 0 or 10000) + (mdb.realm and 20000 or 0)
	if key == lastKey then return end
	lastKey = key
	obj.text = M.Format(h, m, mdb.h24)
end

function M.Tooltip(tip)
	local mdb = ns:ModuleDB("clock")
	ns.TipHeader(tip, "Time")
	local lh, lm = M.Now(false)
	local rh, rm = M.Now(true)
	tip:AddDoubleLine("Local", M.Format(lh, lm, mdb.h24), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddDoubleLine("Realm", M.Format(rh, rm, mdb.h24), 0.9, 0.9, 0.9, 1, 1, 1)
	tip:AddLine(" ")
	ns.TipHint(tip, "Click: open the calendar.")
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Clock", text = "", icon = "Interface\\Icons\\INV_Misc_PocketWatch_02",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		ebarSecure = ns.SecureClick.ClickOf("GameTimeFrame"), -- the game's own calendar button (secure)
		ebarOpened = function() return ns.CalendarShown and ns.CalendarShown() or false end,
		OnClick = ns.SecureClick.Fallback(function(_, mouse)
			if mouse == "LeftButton" and ns.OpenCalendar then ns.OpenCalendar() end
		end),
	})
	lastKey = -1
	self.task = self.task or ns.Every(self, 1, function() M:Tick() end)
	self.task:SetActive(true)
	self:Tick()
end

function M:Redraw() lastKey = -1; if self.running then self:Tick() end end
function M:Disable() if self.task then self.task:SetActive(false) end end
