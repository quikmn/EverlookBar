-- Everlook Bar: calendar. The date (or today's next event, or the time and date), a marker for pending invites,
-- and the next days' events in the tooltip. Built on the game's own calendar (C_Calendar); read only, except when you
-- answer an invite from the right-click menu.
--
-- Cost: the calendar is asked for its data once, 10 s after login and never in combat; after that it pushes updates
-- (CALENDAR_UPDATE_EVENT_LIST, CALENDAR_UPDATE_PENDING_INVITES) and the event list is rebuilt only then, or when the
-- day changes. The tooltip reads the cached list.
local _, ns = ...

local M = ns:NewModule({
	id = "calendar", title = "Calendar", ldbName = ns.PREFIX .. "_Calendar",
	desc = "Date, today's next event and pending invites; the coming week in the tooltip. Left-click opens the calendar.",
	defaults = { style = "full", days = 7, filter = "all", lockouts = false, h24 = true },
	place = { group = "right", order = 8 },
})

local obj
local events = {}       -- cached, sorted: { title, kind, y, m, d, dayOffset, hour, minute, off, day, index, invite, signup, until }
local pending = 0
local requestedAt = -1000
local loaded = false
local builtFor = -1     -- day key the list was built for
local lastText

local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local KIND_COLOR = { holiday = "|cff68ccef", guild = "|cff62cf88", player = "|cffffffff", lockout = "|cff8d94a3" }

------------------------------------------------------------------------
-- Dates (pure; tested)
------------------------------------------------------------------------
local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
function M.DaysIn(y, m) if m == 2 and leap(y) then return 29 end return DAYS[m] end

-- y, m, d plus n days (n >= 0).
function M.AddDays(y, m, d, n)
	d = d + n
	while d > M.DaysIn(y, m) do
		d = d - M.DaysIn(y, m)
		m = m + 1
		if m > 12 then m, y = 1, y + 1 end
	end
	return y, m, d
end

function M.Available()
	return C_Calendar ~= nil and C_Calendar.GetNumDayEvents ~= nil and C_Calendar.GetDayEvent ~= nil
		and C_DateAndTime ~= nil and C_DateAndTime.GetCurrentCalendarTime ~= nil
end

local function today()
	local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
	if not ok or type(t) ~= "table" or ns.IsSecret(t) then return nil end
	local y, m, d = ns.Num(t.year), ns.Num(t.month), ns.Num(t.monthDay)
	if not (y and m and d) then return nil end
	return { y = y, m = m, d = d, wd = ns.Num(t.weekday) or 1, hour = ns.Num(t.hour) or 0, minute = ns.Num(t.minute) or 0 }
end

local function kindOf(calendarType)
	if calendarType == "HOLIDAY" or calendarType == "SYSTEM" then return "holiday" end
	if calendarType == "GUILD_EVENT" or calendarType == "GUILD_ANNOUNCEMENT" then return "guild" end
	if calendarType == "RAID_LOCKOUT" or calendarType == "RAID_RESET" then return "lockout" end
	return "player"
end

local INVITED = Enum and Enum.CalendarStatus and Enum.CalendarStatus.Invited or 0
local NOT_SIGNED = Enum and Enum.CalendarStatus and Enum.CalendarStatus.NotSignedup or 7
local SIGNUP_TYPE = Enum and Enum.CalendarInviteType and Enum.CalendarInviteType.Signup or 1

------------------------------------------------------------------------
-- Reading the calendar
------------------------------------------------------------------------
function M:Build()
	local now = today()
	if not now then return end
	builtFor = now.y * 10000 + now.m * 100 + now.d
	for i = #events, 1, -1 do events[i] = nil end
	local okInfo, info = pcall(C_Calendar.GetMonthInfo, 0)
	if not okInfo or type(info) ~= "table" or ns.IsSecret(info) then return end
	local baseY, baseM = ns.Num(info.year), ns.Num(info.month)
	if not (baseY and baseM) then return end
	local base = baseY * 12 + baseM
	local mdb = ns:ModuleDB("calendar")
	local seenHoliday = {}
	for dayOffset = 0, math.max(0, math.min(31, tonumber(mdb.days) or 7)) do
		local y, m, d = M.AddDays(now.y, now.m, now.d, dayOffset)
		local off = y * 12 + m - base
		local okN, n = pcall(C_Calendar.GetNumDayEvents, off, d)
		n = okN and ns.Num(n) or 0
		for i = 1, n do
			local ok, ev = pcall(C_Calendar.GetDayEvent, off, d, i)
			if ok and type(ev) == "table" and not ns.IsSecret(ev) and not ns.IsSecret(ev.title) then
				local title = ns.Str(ev.title) or "?"
				local kind = kindOf(ns.Str(ev.calendarType))
				local st = type(ev.startTime) == "table" and not ns.IsSecret(ev.startTime) and ev.startTime or {}
				local et = type(ev.endTime) == "table" and not ns.IsSecret(ev.endTime) and ev.endTime or {}
				local keep = kind ~= "lockout" or mdb.lockouts
				if kind == "holiday" then
					-- a multi-day holiday shows once, on the first day in range, with its end date
					if seenHoliday[title] then keep = false end
					seenHoliday[title] = true
				end
				if keep then
					local status = ns.Num(ev.inviteStatus)
					local inviteType = ns.Num(ev.inviteType)
					events[#events + 1] = {
						title = title, kind = kind, y = y, m = m, d = d, dayOffset = dayOffset,
						hour = ns.Num(st.hour) or 0, minute = ns.Num(st.minute) or 0,
						allDay = kind == "holiday",
						untilM = ns.Num(et.month), untilD = ns.Num(et.monthDay),
						off = off, day = d, index = i,
						invite = kind ~= "holiday" and kind ~= "lockout" and status == INVITED,
						signup = kind ~= "holiday" and inviteType == SIGNUP_TYPE and status == NOT_SIGNED,
					}
				end
			end
		end
	end
	table.sort(events, function(a, b)
		if a.dayOffset ~= b.dayOffset then return a.dayOffset < b.dayOffset end
		if a.allDay ~= b.allDay then return a.allDay end
		if a.hour ~= b.hour then return a.hour < b.hour end
		if a.minute ~= b.minute then return a.minute < b.minute end
		return a.title < b.title
	end)
	local okP, p = pcall(C_Calendar.GetNumPendingInvites)
	pending = okP and ns.Num(p) or 0
	loaded = true
	M.dirty = true
end
M.events = events

-- Ask the server for calendar data (lazily; never in combat; at most every 5 minutes unless forced).
function M:Request(force)
	if not C_Calendar.OpenCalendar then return end
	if not force and GetTime() - requestedAt < 300 then return end
	ns.AfterCombat("calendar-open", function()
		requestedAt = GetTime()
		C_Calendar.OpenCalendar()
	end)
end

local function fmtTime(h, m)
	return ns.modules.clock and ns.modules.clock.Format(h, m, ns:ModuleDB("calendar").h24) or string.format("%02d:%02d", h, m)
end

local function shorten(s, n)
	if #s <= n then return s end
	return s:sub(1, n - 1) .. "."
end

local FULLDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local lastMinute = -1
function M:Render()
	-- nothing on screen changes within a minute unless the list was rebuilt: skip without making garbage
	local minute = math.floor(time() / 60)
	if minute == lastMinute and not M.dirty then return end
	lastMinute, M.dirty = minute, false
	local now = today()
	if not now then obj.text = ""; return end
	local key = now.y * 10000 + now.m * 100 + now.d
	if key ~= builtFor and loaded then self:Build() end
	local mdb = ns:ModuleDB("calendar")
	local date = (WEEKDAYS[now.wd] or "") .. " " .. now.d
	local text
	if mdb.style == "next" then
		for _, e in ipairs(events) do
			if e.dayOffset == 0 and not e.allDay and e.kind ~= "lockout"
				and (e.hour > now.hour or (e.hour == now.hour and e.minute >= now.minute)) then
				text = shorten(e.title, 18) .. " " .. fmtTime(e.hour, e.minute)
				break
			end
		end
		text = text or date
	elseif mdb.style == "clock" then
		local realm = ns.modules.clock and ns:ModuleDB("clock") and ns:ModuleDB("clock").realm
		local h, m = now.hour, now.minute
		if not realm then h, m = ns.LocalClock() end
		text = fmtTime(h, m) .. "  " .. date
	elseif mdb.style == "full" then
		-- "23:59, Wednesday, 26-nov-2026"
		local realm = ns.modules.clock and ns:ModuleDB("clock") and ns:ModuleDB("clock").realm
		local h, m = now.hour, now.minute
		if not realm then h, m = ns.LocalClock() end
		text = string.format("%02d:%02d, %s, %02d-%s-%d", h, m, FULLDAYS[now.wd] or "", now.d, (MONTHS[now.m] or ""):lower(), now.y)
	else
		text = date
	end
	if pending > 0 then text = text .. " |cffffc74a[" .. pending .. "]|r" end
	if text ~= lastText then
		lastText = text
		obj.text = text
	end
end

------------------------------------------------------------------------
-- Opening the calendar, answering invites
------------------------------------------------------------------------
function ns.OpenCalendar()
	local loadedFn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local loadFn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if loadedFn and not loadedFn("Blizzard_Calendar") then
		if InCombatLockdown() then ns:Print("the calendar opens after combat.") return false end
		if loadFn then pcall(loadFn, "Blizzard_Calendar") end
	end
	local toggle = _G.Calendar_Toggle or _G.ToggleCalendar
	if toggle then
		local ok = pcall(toggle)
		return ok
	end
	return false
end

-- Show one event in Blizzard's calendar.
local function openEvent(e)
	ns.OpenCalendar()
	if C_Calendar.OpenEvent then pcall(C_Calendar.OpenEvent, e.off, e.day, e.index) end
end

-- answer: "accept" | "tentative" | "decline" | "signup"
function M:Respond(e, answer)
	if InCombatLockdown() then ns:Print("answer invites after combat.") return false end
	local C = C_Calendar
	local fn = (answer == "accept" and C.ContextMenuInviteAvailable) or (answer == "tentative" and C.ContextMenuInviteTentative)
		or (answer == "decline" and C.ContextMenuInviteDecline) or (answer == "signup" and C.ContextMenuEventSignUp)
	if not (fn and C.ContextMenuSelectEvent) then openEvent(e) return false end
	local ok = pcall(function()
		C.ContextMenuSelectEvent(e.off, e.day, e.index)
		fn()
	end)
	if not ok then
		ns:Print("could not answer from the bar; opening the calendar instead.")
		openEvent(e)
		return false
	end
	local word = { accept = "Accepted", tentative = "Tentative", decline = "Declined", signup = "Signed up" }
	ns:Print(word[answer] .. ": " .. e.title)
	return true
end

local FILTERS = { { "all", "Everything" }, { "invites", "Invites only" }, { "holidays", "Holidays only" }, { "guild", "Guild events only" } }

local function passes(e, filter)
	if filter == "invites" then return e.invite or e.signup end
	if filter == "holidays" then return e.kind == "holiday" end
	if filter == "guild" then return e.kind == "guild" end
	return true
end

function M:Menu(button)
	local mdb = ns:ModuleDB("calendar")
	local items = { { title = true, text = "Show in the tooltip" } }
	for _, f in ipairs(FILTERS) do
		items[#items + 1] = { value = "filter:" .. f[1], text = (mdb.filter == f[1] and "|cffffc74a" or "") .. f[2] .. (mdb.filter == f[1] and "|r" or "") }
	end
	local answers = {}
	for i, e in ipairs(events) do
		if e.invite or e.signup then
			items[#items + 1] = { title = true, text = shorten(e.title, 26) .. " (" .. MONTHS[e.m] .. " " .. e.d .. ")" }
			if e.signup then
				items[#items + 1] = { value = "respond:" .. i .. ":signup", text = "   Sign up" }
			else
				items[#items + 1] = { value = "respond:" .. i .. ":accept", text = "   Accept" }
				items[#items + 1] = { value = "respond:" .. i .. ":tentative", text = "   Tentative" }
				items[#items + 1] = { value = "respond:" .. i .. ":decline", text = "   Decline" }
			end
			answers[#answers + 1] = e
		end
	end
	items[#items + 1] = { value = "open", text = "Open calendar" }
	ns.UI.OpenPopup(button, items, nil, function(v)
		if v == "open" then ns.OpenCalendar() return end
		local f = v:match("^filter:(%a+)$")
		if f then mdb.filter = f return end
		local i, a = v:match("^respond:(%d+):(%a+)$")
		local e = i and events[tonumber(i)]
		if e then M:Respond(e, a) end
	end, { atCursor = true, width = 220 })
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function dayLabel(e)
	if e.dayOffset == 0 then return "Today" end
	if e.dayOffset == 1 then return "Tomorrow" end
	return MONTHS[e.m] .. " " .. e.d
end

function M.Tooltip(tip)
	local now = today()
	M:Request(false)
	ns.TipHeader(tip, "Calendar")
	if now then tip:AddLine((WEEKDAYS[now.wd] or "") .. " " .. now.d .. " " .. (MONTHS[now.m] or "") .. " " .. now.y, 1, 1, 1) end
	if not loaded then
		ns.TipHint(tip, "Reading the calendar... (it loads a few seconds after login, never in combat)")
		return
	end
	local mdb = ns:ModuleDB("calendar")
	local any = false
	-- pending invites first
	if pending > 0 then
		tip:AddLine(" ")
		tip:AddLine("Invites waiting for an answer: " .. pending, 1, 0.78, 0.29)
		for _, e in ipairs(events) do
			if e.invite or e.signup then
				tip:AddDoubleLine("  " .. e.title, dayLabel(e) .. " " .. fmtTime(e.hour, e.minute), 1, 1, 1, 0.9, 0.9, 0.9)
			end
		end
		ns.TipHint(tip, "Right-click to answer.")
	end
	local lastDay = -1
	for _, e in ipairs(events) do
		if passes(e, mdb.filter) and not ((e.invite or e.signup) and pending > 0) then
			if e.dayOffset ~= lastDay then
				lastDay = e.dayOffset
				tip:AddLine(" ")
				tip:AddLine(dayLabel(e), 1, 0.82, 0.29)
			end
			local left
			if e.allDay then
				left = (e.untilM and e.untilD and ("until " .. MONTHS[e.untilM] .. " " .. e.untilD)) or "all day"
			else
				left = fmtTime(e.hour, e.minute)
			end
			tip:AddDoubleLine((KIND_COLOR[e.kind] or "") .. e.title .. "|r", left, 1, 1, 1, 0.8, 0.8, 0.8)
			any = true
		end
	end
	if not any and pending == 0 then
		tip:AddLine(" ")
		ns.TipHint(tip, "Nothing in the next " .. (tonumber(mdb.days) or 7) .. " days" .. (mdb.filter ~= "all" and " (filtered)" or "") .. ".")
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "Left-click: open the calendar. Right-click: filter, answer invites.")
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Calendar", text = "", icon = "Interface\\Icons\\INV_Misc_Note_02",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function(button, mouse)
			if mouse == "RightButton" then M:Menu(button) else ns.OpenCalendar() end
		end,
	})
	local function rebuild() M:Build(); M:Render() end
	for _, e in ipairs({ "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_PENDING_INVITES", "CALENDAR_NEW_EVENT",
		"CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_INVITE_LIST" }) do
		ns.On(e, self, rebuild)
	end
	ns.On("PLAYER_ENTERING_WORLD", self, function()
		C_Timer.After(10, function() if M.running then M:Request(false) end end)
	end)
	-- the date and "next event" move on with the clock: once a minute is plenty, every second with the clock style
	self.task = self.task or ns.Every(self, 1, function() M:Render() end)
	self.task:SetInterval((ns:ModuleDB("calendar").style == "clock" or ns:ModuleDB("calendar").style == "full") and 1 or 30)
	self.task:SetActive(true)
	lastText = nil
	M.dirty = true
	self:Render()
end

function M:Redraw()
	if not self.running then return end
	self.task:SetInterval((ns:ModuleDB("calendar").style == "clock" or ns:ModuleDB("calendar").style == "full") and 1 or 30)
	if loaded then self:Build() end
	lastText = nil
	M.dirty = true
	self:Render()
end

function M:Disable() if self.task then self.task:SetActive(false) end end
