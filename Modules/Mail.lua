-- Everlook Bar: mail. New mail yes or no; the senders the game reports (up to three) in the tooltip. Only your own
-- mailbox: the game has no API for anyone else's.
local _, ns = ...

local M = ns:NewModule({
	id = "mail", title = "Mail", ldbName = ns.PREFIX .. "_Mail",
	desc = "Shows when you have new mail, with the senders in the tooltip.",
	defaults = { hideWhenNone = false },
	place = { group = "right", order = 4 },
})

local obj
local hasMail = false

function M:Update()
	hasMail = HasNewMail and HasNewMail() and true or false
	local mdb = ns:ModuleDB("mail")
	if hasMail then
		obj.text = "|cff62cf88New mail|r"
		obj.icon = "Interface\\Icons\\INV_Letter_15"
	else
		obj.text = "|cff8d94a3No mail|r"
		obj.icon = "Interface\\Icons\\INV_Letter_02"
	end
	ns.API.SetHidden(self.ldbName, mdb.hideWhenNone and not hasMail)
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Mail")
	if not hasMail then ns.TipHint(tip, "No new mail.") return end
	local senders = { GetLatestThreeSenders and GetLatestThreeSenders() }
	local any = false
	for _, s in ipairs(senders) do
		s = ns.Str(s)
		if s and s ~= "" then tip:AddLine(s, 1, 1, 1); any = true end
	end
	if not any then ns.TipHint(tip, "New mail is waiting. The game does not say who sent it until you open a mailbox.") end
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Mail", text = "", icon = "Interface\\Icons\\INV_Letter_02",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
	})
	local function update() M:Update() end
	for _, e in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, update)
	end
	self:Update()
end

function M:Disable() end
