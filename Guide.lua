-- Everlook Bar: "Build your own plugin" in the settings window (/ebar). Addons can't open a browser, so the button
-- shows the guide's address in a box to copy, and under it one line to paste into an AI assistant: the guide as a
-- single Markdown brief it can read and write a plugin from.
local _, ns = ...
local UI, U = ns.UI, ns.Util
local app = ns.app

local G = {}
ns.Guide = G
G.URL = "https://everlookdb.com/ebar/plugins"
G.BRIEF = "https://everlookdb.com/ebar/plugins.md"
G.AI_LINE = "Read " .. G.BRIEF .. " and help me build a plugin for Everlook Bar."

local win

-- A read-only box: clicking selects it all, typing can't change it.
local function copyBox(parent, text, y)
	local box = UI.EditBox(parent, 428, 24)
	box:SetPoint("TOP", 0, y)
	box:SetScript("OnTextChanged", function(self)
		if self:GetText() ~= text then self:SetText(text); self:HighlightText() end
	end)
	box:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function() win:Hide() end)
	box:SetText(text)
	return box
end

local function line(parent, text, y, color, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	U.SetFont(fs, size or 12)
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetPoint("TOPRIGHT", -16, y)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(unpack(color))
	fs:SetText(text)
	return fs
end

-- Our own frame, not a StaticPopup (touching Blizzard's popups taints them).
function G:Open()
	if not win then
		local T = ns.Theme
		win = CreateFrame("Frame", ns.PREFIX .. "GuideWindow", UIParent)
		win.eluiTheme = T
		win:SetSize(460, 214)
		win:SetPoint("TOP", 0, -160)
		win:SetFrameStrata("DIALOG")
		win:SetToplevel(true)
		win:SetClampedToScreen(true)
		win:EnableMouse(true)
		win:Hide()
		U.Solid(win, "BACKGROUND", unpack(T.bg)):SetAllPoints()
		U.Border(win, 1, unpack(T.border))
		line(win, "The guide (press Ctrl+C, then paste it in your browser):", -16, T.text)
		win.guide = copyBox(win, G.URL, -38)
		line(win, "Paste this into your AI:", -82, T.text)
		win.ai = copyBox(win, G.AI_LINE, -104)
		line(win, "ChatGPT, Claude or any assistant reads the whole guide from it, asks what your plugin should show, and writes it.",
			-136, T.muted, 11)
		UI.Button(win, CLOSE or "Close", function() win:Hide() end, 100):SetPoint("BOTTOM", 0, 14)
		win:SetScript("OnShow", function()
			win.guide:SetText(G.URL)
			win.ai:SetText(G.AI_LINE)
			win.guide:SetFocus()
			win.guide:HighlightText()
		end)
		win:SetScript("OnHide", function() win.guide:ClearFocus(); win.ai:ClearFocus() end)
		UI.CloseOnEscape(win)
		G.window = win
	end
	win:Show()
end

app:Section("develop", "Build your own", function(stack)
	UI.Header(stack, "Build your own plugin", "Every button on the bar is a plugin, and you can write your own: a few lines of Lua in a tiny addon.")
	UI.Note(stack, "The guide on EverlookDB has a working plugin in 15 lines, the whole API (mini bars, settings that show up in this window, the shared ticker) and the rules that keep the bar fast. It also comes as one brief you can paste into an AI assistant, so it writes the plugin with you.")
	UI.ButtonRow(stack, {
		{ label = "Show the guide link", width = 180, style = "accent", onClick = function() G:Open() end,
			desc = "Shows the address of the plugin guide to copy (addons can't open a browser), and a line to paste into an AI assistant.",
			keywords = { "plugin", "plugins", "module", "modules", "develop", "developer", "API", "guide", "build", "make",
				"write", "own", "code", "Lua", "AI", "LibDataBroker", "LDB", "widget", "author" } },
	})
end)
