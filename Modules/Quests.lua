-- Everlook Bar: quest log. How full it is ("! 38/45"), yellow when only a few slots are left and red when full, so
-- you see before a quest giver says your log is full. The limit is the game's own (C_QuestLog), never a guess.
local _, ns = ...

local M = ns:NewModule({
	id = "quests", title = "Quest log", ldbName = ns.PREFIX .. "_Quests",
	desc = "Quests in your log out of how many you can have.",
	defaults = { style = "used/max", warn = 3 },
	place = { group = "right", order = 2.5 },
})

local obj
local count, max, watched = 0, 0, 0

-- the quests in the log (headers not counted) and how many the game lets you have
local function read()
	local Q = C_QuestLog
	local n
	if Q and Q.GetNumQuestLogEntries then
		n = select(2, Q.GetNumQuestLogEntries())
	elseif GetNumQuestLogEntries then
		n = select(2, GetNumQuestLogEntries())
	end
	local m = Q and ((Q.GetMaxNumQuestsCanAccept and Q.GetMaxNumQuestsCanAccept()) or (Q.GetMaxNumQuests and Q.GetMaxNumQuests()))
	m = ns.Num(m) or ns.Num(MAX_QUESTS) or 0
	local w = Q and Q.GetNumQuestWatches and Q.GetNumQuestWatches()
	return ns.Num(n) or 0, m, ns.Num(w) or 0
end

-- The text for count of max: "38/45", or "7 left" (the style setting); coloured as the log fills.
function M.Text(c, m, style, warn)
	if m <= 0 then return tostring(c) end
	local left = m - c
	local col = left <= 0 and "|cffef5d5d" or (left <= (warn or 3) and "|cffffd25a" or "")
	local close = col ~= "" and "|r" or ""
	if style == "left" then return col .. math.max(0, left) .. " left" .. close end
	return col .. c .. close .. "/" .. m
end

function M:Update()
	count, max, watched = read()
	local db = ns:ModuleDB("quests")
	obj.text = M.Text(count, max, db.style, db.warn)
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Quest log")
	if max > 0 then
		tip:AddDoubleLine("Quests", count .. " of " .. max, 0.9, 0.9, 0.9, 1, 1, 1)
		tip:AddDoubleLine("Room for", math.max(0, max - count) .. " more", 0.9, 0.9, 0.9, 1, 1, 1)
	else
		tip:AddDoubleLine("Quests", tostring(count), 0.9, 0.9, 0.9, 1, 1, 1)
	end
	if watched > 0 then tip:AddDoubleLine("Tracked", tostring(watched), 0.9, 0.9, 0.9, 1, 1, 1) end
	tip:AddLine(" ")
	ns.TipHint(tip, "Click: open your quest log.")
end

function M:Available()
	return (C_QuestLog ~= nil and C_QuestLog.GetNumQuestLogEntries ~= nil) or GetNumQuestLogEntries ~= nil
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Quests", text = "", icon = "Interface\\GossipFrame\\AvailableQuestIcon",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		ebarSecure = ns.SecureClick.ClickOf("QuestLogMicroButton"), -- secure when the game has the micro button
		OnClick = ns.SecureClick.Fallback(function(_, mouse)
			if mouse == "LeftButton" and ToggleQuestLog then ToggleQuestLog() end
		end),
	})
	local function update() ns.Soon(M.Update, M) end
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Disable() end
