-- Everlook Bar: the settings window (/ebar), every setting also from chat, and the chat commands.
-- One definition per setting drives both the window widget and "/ebar <setting> <value>".
local ADDON, ns = ...
local UI = ns.UI
local U = ns.Util
local O = {}
ns.Options = O

ns.editBar = 1 -- the bar the Bars and Plugins pages edit; "/ebar bar 2" or "/ebar bar2.edge left" pick another

local app = UI:NewApp({
	name = ns.NAME,
	addon = ADDON,
	slash = ns.SLASH,
	aliases = { "/everlookbar" },
	frameName = ns.PREFIX,
	tagline = "Your info bars and a clean minimap.",
	accent = ns.ACCENT,
	position = function() return ns.db end,
	buttons = {
		{ label = "Unlock (move things)", text = function() return ns.Unlock.active and "Lock" or "Unlock (move things)" end,
			onClick = function() ns.Unlock:Toggle() end,
			desc = "Drag bars to any edge or anywhere, move the minimap, drag plugins between bars. Escape locks again." },
	},
})
ns.app = app

local function bar() return ns.db and ns.db.bars[ns.editBar] end
local function relayout() ns.Host:RefreshAll() end

local EDGES = {
	{ value = "top", text = "Top of the screen" }, { value = "bottom", text = "Bottom of the screen" },
	{ value = "left", text = "Left side (plugins stacked)" }, { value = "right", text = "Right side (plugins stacked)" },
	{ value = "free", text = "Free: anywhere (drag it in unlock mode)" },
}
local ORIENTS = { { value = "horizontal", text = "Horizontal" }, { value = "vertical", text = "Vertical (stacked)" } }
local ALIGNS = { { value = "start", text = "Start (left / top)" }, { value = "center", text = "Centre" }, { value = "end", text = "End (right / bottom)" } }
local OUTLINES = { { value = "", text = "None" }, { value = "OUTLINE", text = "Outline" }, { value = "THICKOUTLINE", text = "Thick outline" } }
local STRATA = { { value = "BACKGROUND", text = "Background" }, { value = "LOW", text = "Low" }, { value = "MEDIUM", text = "Medium" }, { value = "HIGH", text = "High" } }

------------------------------------------------------------------------
-- Bar settings (the selected bar)
------------------------------------------------------------------------
local function barSetting(def)
	local field = def.field
	def.get = def.get or function() local b = bar(); return b and b[field] end
	def.set = def.set or function(v) local b = bar(); if b then b[field] = v end end
	def.after = def.after or relayout
	def.chatLabel = def.chatLabel or ("Bar " .. "%d " .. def.label:lower())
	local label = def.chatLabel
	def.chatLabel = nil
	local d = app:Setting(def)
	setmetatable(d, { __index = function(t, k) if k == "chatLabel" then return label:format(ns.editBar) end end })
	return d
end

barSetting({ key = "bar.name", field = "name", type = "string", label = "Name", width = 240 })
barSetting({ key = "bar.shown", field = "shown", type = "bool", label = "Show this bar" })
barSetting({ key = "bar.edge", field = "edge", type = "choice", label = "Where", choices = EDGES, width = 300,
	set = function(v) ns.Bars:SetEdge(ns.editBar, v) end, after = function() end,
	desc = "Top and bottom bars run along the edge; left and right bars stack their plugins. In unlock mode you can drag a bar to any edge, or anywhere." })
barSetting({ key = "bar.orient", field = "orient", type = "choice", label = "Free bar direction", choices = ORIENTS, width = 300,
	disabled = function() local b = bar(); return not b or b.edge ~= "free" end,
	get = function() local b = bar(); return b and (b.orient or "horizontal") end })
barSetting({ key = "bar.lanes", field = "lanes", type = "number", label = "Rows (columns on side bars)", min = 1, max = 4,
	desc = "2 gives a two-line bar. Each plugin sits in one row; set it on the Plugins page." })
barSetting({ key = "bar.lanesize", field = "laneSize", type = "number", label = "Thickness of a row (width of a column on side bars)", min = 12, max = 300,
	chatLabel = "Bar %d thickness" })
barSetting({ key = "bar.length", field = "length", type = "number", label = "Length (0 = the whole edge)", min = 0, max = 4000, step = 10 })
barSetting({ key = "bar.align", field = "align", type = "choice", label = "A shorter bar sits at", choices = ALIGNS, width = 240 })
barSetting({ key = "bar.offset", field = "offset", type = "number", label = "Shift along the edge", min = -2000, max = 2000 })
barSetting({ key = "bar.bg", field = "bg", type = "color", label = "Background colour and opacity", hasAlpha = true,
	desc = "Default: black at 60%." })
barSetting({ key = "bar.line", field = "line", type = "bool", label = "Thin accent line on the inner edge" })
barSetting({ key = "bar.font", field = "font", type = "choice", label = "Font", choices = ns.FONTS, width = 300 })
barSetting({ key = "bar.fontsize", field = "fontSize", type = "number", label = "Font size", min = 8, max = 24 })
barSetting({ key = "bar.outline", field = "outline", type = "choice", label = "Text outline", choices = OUTLINES, width = 200 })
barSetting({ key = "bar.spacing", field = "spacing", type = "number", label = "Space between plugins", min = 0, max = 60 })
barSetting({ key = "bar.padding", field = "padding", type = "number", label = "Space at the bar's ends", min = 0, max = 60 })
barSetting({ key = "bar.strata", field = "strata", type = "choice", label = "Draw layer", choices = STRATA, width = 200,
	desc = "Medium sits above the game world and most windows' backgrounds; raise it if another addon covers the bar." })

------------------------------------------------------------------------
-- General
------------------------------------------------------------------------
app:Setting({ key = "autoadd", type = "bool", label = "Put plugins from other addons on bar 1 when they appear",
	get = function() return ns.db.autoAdd end, set = function(v) ns.db.autoAdd = v end,
	desc = "Off: new plugins wait on the Plugins page until you add them." })
app:Setting({ key = "snap", type = "bool", label = "Snap to the grid in unlock mode",
	get = function() return ns.db.snap end, set = function(v) ns.db.snap = v end })
app:Setting({ key = "grid", type = "number", label = "Grid size (pixels)", min = 4, max = 64,
	get = function() return ns.db.grid end, set = function(v) ns.db.grid = v end })
app:Setting({ key = "profiling", type = "bool", label = "Measure Everlook Bar's own time per plugin (for /ebar perf)",
	get = function() return ns.db.profiling end, set = function(v) ns.db.profiling = v; ns.SetProfiling(v) end,
	desc = "Times every call into a plugin. Costs a little itself; leave it off unless you are measuring." })

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
local function modSetting(id, field, def)
	def.key = id .. "." .. field:lower()
	def.get = def.get or function() return ns:ModuleDB(id)[field] end
	def.set = def.set or function(v) ns:ModuleDB(id)[field] = v end
	local after = def.after
	def.after = function(v)
		local m = ns.modules[id]
		if after then after(v) end
		if m and m.running then
			if m.Redraw then ns.SafeCall(m, m.Redraw, m)
			elseif m.Update then ns.SafeCall(m, m.Update, m)
			elseif m.Tick then ns.SafeCall(m, m.Tick, m) end
		end
		relayout()
	end
	return app:Setting(def)
end

for _, m in ipairs(ns.moduleOrder) do
	app:Setting({ key = m.id .. ".enabled", type = "bool", label = m.title, desc = m.desc,
		chatLabel = m.title .. " module",
		get = function() return ns:ModuleDB(m.id).enabled end,
		set = function(v) ns:SetModuleEnabled(m, v, true) end,
		after = function() if O.PluginsChanged then O:PluginsChanged() end end })
end

modSetting("xp", "width", { type = "number", label = "XP bar width", min = 40, max = 600 })
modSetting("xp", "decimals", { type = "number", label = "XP percent decimals", min = 0, max = 2 })
modSetting("xp", "showText", { type = "bool", label = "Show the XP percentage" })
modSetting("xp", "textInBar", { type = "bool", label = "Percentage in the middle of the bar", keywords = { "centre", "center", "inside", "text" } })
modSetting("perf", "fps", { type = "bool", label = "Show FPS" })
modSetting("perf", "latency", { type = "choice", label = "Latency on the bar", width = 260, choices = {
	{ value = "world", text = "World (combat)" }, { value = "home", text = "Home (realm)" }, { value = "both", text = "Both (home/world)" }, { value = "none", text = "None" } } })
modSetting("perf", "memory", { type = "bool", label = "Show total addon memory (read every 30 s)" })
modSetting("perf", "colors", { type = "bool", label = "Colour good / poor values" })
modSetting("location", "zone", { type = "bool", label = "Show the zone" })
modSetting("location", "subzone", { type = "bool", label = "Show the subzone (Tarren Mill, Southshore Inn...)" })
modSetting("location", "coords", { type = "bool", label = "Show coordinates" })
modSetting("location", "colorByPvP", { type = "bool", label = "Colour the zone by PvP status" })
modSetting("bags", "style", { type = "choice", label = "Bag text", width = 200, choices = {
	{ value = "free/total", text = "Free / total" }, { value = "free", text = "Free only" }, { value = "used/total", text = "Used / total" } } })
modSetting("quests", "style", { type = "choice", label = "Quest log text", width = 200, choices = {
	{ value = "used/max", text = "In log / most you can have" }, { value = "left", text = "Slots left" } } })
modSetting("quests", "warn", { type = "number", label = "Quest log: yellow when this many slots are left", min = 0, max = 10 })
modSetting("mail", "hideWhenNone", { type = "bool", label = "Hide the mail plugin when there is no new mail" })
modSetting("gold", "copper", { type = "bool", label = "Show copper" })
modSetting("clock", "realm", { type = "bool", label = "Clock shows realm time (else this computer's)" })
modSetting("clock", "h24", { type = "bool", label = "Clock: 24-hour" })
modSetting("calendar", "style", { type = "choice", label = "Calendar text", width = 300, choices = {
	{ value = "next", text = "Today's next event, else the date" }, { value = "date", text = "The date" },
	{ value = "clock", text = "Clock and date" }, { value = "full", text = "23:59, Wednesday, 26-nov-2026" } } })
modSetting("calendar", "days", { type = "number", label = "Days ahead in the tooltip", min = 1, max = 14 })
modSetting("calendar", "filter", { type = "choice", label = "Calendar tooltip shows", width = 240, choices = {
	{ value = "all", text = "Everything" }, { value = "invites", text = "Invites only" }, { value = "holidays", text = "Holidays only" },
	{ value = "guild", text = "Guild events only" } } })
modSetting("calendar", "lockouts", { type = "bool", label = "Calendar: include raid lockouts and resets" })
modSetting("calendar", "h24", { type = "bool", label = "Calendar: 24-hour times" })

------------------------------------------------------------------------
-- Minimap
------------------------------------------------------------------------
local mm = ns.modules.minimap
local function mmRedraw() if mm.running then ns.SafeCall(mm, mm.Redraw, mm) end end
local function mmSetting(field, def)
	def.key = "minimap." .. field:lower()
	def.get = def.get or function() return ns:ModuleDB("minimap")[field] end
	def.set = def.set or function(v) ns:ModuleDB("minimap")[field] = v end
	def.after = def.after or mmRedraw
	def.disabled = def.disabled or function() return not mm.running or mm.stepAside ~= nil end
	return app:Setting(def)
end
app:Setting({ key = "minimap.unlocked", type = "bool", label = "Unlock minimap (drag it with the left mouse button)",
	chatLabel = "Unlock minimap",
	get = function() return mm.unlocked end,
	set = function(v) mm:SetUnlocked(v) end,
	disabled = function() return not mm.running or mm.stepAside ~= nil end })
mmSetting("scale", { type = "number", label = "Minimap size", min = 0.5, max = 2.5, step = 0.05, fmt = "%.2f" })
mmSetting("snapEdges", { type = "bool", label = "Snap to screen edges when dropped", keywords = { "sticky", "magnet", "nudge", "edge" } })
mmSetting("zoneLabel", { type = "choice", label = "Zone line on the minimap", width = 260, choices = {
	{ value = "off", text = "Off" }, { value = "subzone", text = "Where you stand (subzone)" },
	{ value = "zone", text = "The zone" }, { value = "both", text = "Zone: subzone" } } })
mmSetting("zoneLabelPos", { type = "choice", label = "Zone line position", width = 200, choices = {
	{ value = "top", text = "Above the minimap" }, { value = "bottom", text = "Under the minimap" } },
	disabled = function() return not mm.running or mm.stepAside ~= nil or ns:ModuleDB("minimap").zoneLabel == "off" end })
mmSetting("borderSize", { type = "number", label = "Border thickness", min = 1, max = 8, step = 1 })
mmSetting("shape", { type = "choice", label = "Shape", width = 200, choices = { { value = "round", text = "Round" }, { value = "square", text = "Square" } } })
mmSetting("border", { type = "bool", label = "Thin border" })
mmSetting("borderColor", { type = "color", label = "Border colour", hasAlpha = true })
mmSetting("wheelZoom", { type = "bool", label = "Zoom with the mouse wheel" })
mmSetting("buttons", { type = "choice", label = "Addon minimap buttons", width = 320, choices = {
	{ value = "drawer", text = "Collect into one drawer button" }, { value = "hide", text = "Hide them all" },
	{ value = "leave", text = "Leave them alone" } },
	disabled = function() return not mm.running or mm.buttonRival ~= nil end,
	after = function(v) if v == "leave" then mm:ReleaseButtons() end; mmRedraw() end })
mmSetting("drawerCorner", { type = "choice", label = "Drawer button corner", width = 200, choices = {
	{ value = "TOPLEFT", text = "Top left" }, { value = "TOPRIGHT", text = "Top right" },
	{ value = "BOTTOMLEFT", text = "Bottom left" }, { value = "BOTTOMRIGHT", text = "Bottom right" } },
	disabled = function() return not mm.running or mm.buttonRival ~= nil end })
mmSetting("drawerCols", { type = "number", label = "Buttons per row in the drawer", min = 1, max = 12,
	disabled = function() return not mm.running or mm.buttonRival ~= nil end })
local MODES = { { value = "show", text = "Show (game's place)" }, { value = "hide", text = "Hide" }, { value = "move", text = "Move (unlock mode)" } }
for _, e in ipairs(mm.ELEMENTS) do
	app:Setting({ key = "minimap." .. e.key, type = "choice", label = e.label, choices = MODES, width = 220,
		get = function() return mm:Mode(e.key) end,
		set = function(v) ns:ModuleDB("minimap").elements[e.key] = v end,
		disabled = function() return not mm.running or mm.stepAside ~= nil end,
		after = function() if mm.running then ns.AfterCombat("minimap-elements", function() mm:ApplyElements() end); ns.Unlock:SyncMovers() end end })
end

------------------------------------------------------------------------
-- Settings from other addons (EverlookBar.API.RegisterSettings)
------------------------------------------------------------------------
local extGroups = {}
function O:AddExtSettings(group)
	extGroups[#extGroups + 1] = group
	for _, s in ipairs(group.settings) do
		local key = group.owner .. "." .. tostring(s.key)
		if not app:GetSetting(key) then
			app:Setting({ key = key, type = s.type or "bool", label = s.label or s.key, desc = s.desc,
				min = s.min, max = s.max, step = s.step, choices = s.choices, hasAlpha = s.hasAlpha, width = s.width,
				chatLabel = group.title .. ": " .. (s.label or s.key),
				get = function() return group.get(s.key) end,
				set = function(v) group.set(s.key, v) end,
				after = function(v) if type(s.onChange) == "function" then ns.SafeCall({ name = group.title }, s.onChange, v) end end })
		end
	end
	if app.sections.modules then app:RebuildSection("modules") end
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
local function selectBar(n)
	n = tonumber(n)
	if not n or not ns.db.bars[n] then
		ns:Print("|cffff6060no bar " .. tostring(n) .. ".|r There " .. (#ns.db.bars == 1 and "is 1 bar." or ("are " .. #ns.db.bars .. " bars.")))
		return false
	end
	ns.editBar = n
	app:Refresh()
	return true
end
O.SelectBar = selectBar

local function findPlugin(text)
	text = U.Trim(text):lower()
	if text == "" then return nil end
	local exact, partial
	for name in pairs(ns.Host.plugins) do
		local title = ns.Host:Title(name):lower()
		if name:lower() == text or title == text then exact = name end
		if not partial and (name:lower():find(text, 1, true) or title:find(text, 1, true)) then partial = name end
	end
	return exact or partial
end

app:Movable({ what = "bars, the minimap and plugins (Escape locks)", get = function() return not ns.Unlock.active end,
	set = function(locked) if locked then ns.Unlock:Stop() else ns.Unlock:Start() end end })
app:Command("perf", "perf", "Everlook Bar's own memory and CPU use", function() O:PrintPerf() end)
app:Command("bar", "bar <n> | bar add [edge] | bar delete <n>", "pick the bar that bar.* settings change; add or delete bars", function(rest)
	local word, arg = U.Trim(rest):match("^(%S*)%s*(.*)$")
	word = (word or ""):lower()
	if word == "add" or word == "new" then
		O:AddBar(arg ~= "" and arg:lower() or nil)
	elseif word == "delete" or word == "remove" then
		O:DeleteBar(tonumber(arg) or ns.editBar)
	elseif word ~= "" then
		if selectBar(word) then ns:Print("editing bar " .. ns.editBar .. " (" .. (bar().name or "") .. "). /ebar settings lists its bar.* values.") end
	else
		for i, b in ipairs(ns.db.bars) do
			ns:Print((i == ns.editBar and "> " or "  ") .. i .. ": " .. U.Escape(b.name or "Bar") .. " (" .. b.edge .. ", " .. b.lanes .. " row(s))")
		end
	end
end)
app:Command("plugins", "plugins", "list every plugin and where it is", function()
	for _, name in ipairs(ns.Host:Names()) do
		local p = ns.db.placement[name]
		local rec = ns.Host.plugins[name]
		ns:Print(U.Escape(ns.Host:Title(name)) .. ": " .. (p and ("bar " .. p.bar .. ", " .. p.group .. ", row " .. (p.lane or 1)) or "|cff8d94a3not on a bar|r")
			.. (rec.errors > 0 and (" |cffff6060" .. rec.errors .. " error(s)|r") or ""))
	end
end)
app:Command("place", "place <plugin> <bar> [left|center|right] [row]", "put a plugin on a bar", function(rest)
	local text, b, g, lane = rest:match("^(.-)%s+(%d+)%s*(%a*)%s*(%d*)$")
	local name = text and findPlugin(text)
	if not name or not ns.db.bars[tonumber(b)] then ns:Print("|cffff6060usage:|r " .. ns.SLASH .. " place gold 1 right") return end
	ns.Host:Place(name, tonumber(b), tonumber(lane) or 1, (g ~= "" and g:lower() or "right"))
	ns:Print(ns.Host:Title(name) .. " is on bar " .. b .. ".")
end)
app:Command("remove", "remove <plugin>", "take a plugin off its bar", function(rest)
	local name = findPlugin(rest)
	if not name then ns:Print("|cffff6060no plugin like that.|r " .. ns.SLASH .. " plugins lists them.") return end
	ns.Host:Remove(name)
	ns:Print(ns.Host:Title(name) .. " is off the bars.")
end)
app:Command("minimap", "minimap unlock | lock | reset | scan | grab <frame> | ignore <frame>",
	"move the minimap; put it back; what the minimap module found; collect or skip a button by frame name", function(rest)
	local word, arg = U.Trim(rest):match("^(%S*)%s*(.*)$")
	word = (word or ""):lower()
	local db = ns:ModuleDB("minimap")
	if word == "unlock" or word == "move" then
		mm:SetUnlocked(true)
	elseif word == "lock" then
		mm:SetUnlocked(false)
	elseif word == "reset" then
		app:HandleReset("minimap")
	elseif word == "grab" and arg ~= "" then
		db.grab[arg], db.ignore[arg] = true, nil
		mm:ApplyAll(); ns:Print("will collect " .. U.Escape(arg) .. ".")
	elseif word == "ignore" and arg ~= "" then
		db.ignore[arg], db.grab[arg] = true, nil
		mm:ReleaseButtons(arg); ns:Print("will leave " .. U.Escape(arg) .. " alone.")
	else
		if not mm.running then ns:Print("the clean minimap is off (" .. ns.SLASH .. " minimap.enabled on).") return end
		mm:DetectRivals()
		if mm.stepAside then ns:Print(mm.stepAside .. " manages the minimap; " .. ns.NAME .. " leaves the frame alone.") end
		mm:Report()
	end
end)
-- Resets ask first: the same command again within 10 s does it.
app:Reset("bars", "the bars (one top bar, plugins back in place)", function()
	wipe(ns.db.bars); wipe(ns.db.placement)
	ns.db.bars[1] = U.CopyTable(ns.BAR_DEFAULTS); ns.db.bars[1].name = "Top bar"
	for _, m in ipairs(ns.moduleOrder) do if m.running and m.ldbName then ns.Host:PlaceDefault(m.ldbName, m.place) end end
	ns.editBar = 1
	ns.Host:RefreshAll()
end)
app:Reset("all", "every " .. ns.NAME .. " setting (reloads the UI)", function() _G[ns.SAVED] = nil; ReloadUI() end)
app:Reset("minimap", "the minimap's place and size", function() mm:ResetPosition() end)

app:StatusLines(function()
	local u, n = O:Usage(), 0
	for _ in pairs(ns.Host.plugins) do n = n + 1 end
	return { #ns.db.bars .. " bar(s), " .. n .. " plugin(s); " .. (u.memKB and string.format("%.0f KB", u.memKB) or "memory ?")
		.. ". " .. ns.SLASH .. " perf for CPU." }
end)

-- "/ebar bar2.edge left" = pick bar 2, then set bar.edge.
local baseHandle = app.HandleSlash
function app:HandleSlash(msg)
	if U.Trim(msg or ""):lower() == "reset all confirm" then _G[ns.SAVED] = nil; ReloadUI() return "reset" end -- old macros
	local n, rest = U.Trim(msg or ""):match("^[Bb][Aa][Rr](%d+)%.(.+)$")
	if n then
		if not selectBar(n) then return "unknown" end
		return baseHandle(self, "bar." .. rest)
	end
	return baseHandle(self, msg)
end

------------------------------------------------------------------------
-- Bars: add and delete
------------------------------------------------------------------------
function O:AddBar(edge)
	local ok = { top = true, bottom = true, left = true, right = true, free = true }
	edge = ok[edge or ""] and edge or "bottom"
	local spec = { name = "Bar " .. (#ns.db.bars + 1), edge = edge }
	if edge == "left" or edge == "right" then spec.laneSize = 150 end
	if edge == "free" then spec.x, spec.y, spec.length = 200, 200, 400 end
	ns.editBar = ns.Bars:AddBar(spec)
	ns.Host:RefreshAll()
	app:Refresh()
	ns:Print("added bar " .. ns.editBar .. " (" .. edge .. "). Put plugins on it on the Plugins page, or drag them there in unlock mode.")
end

function O:DeleteBar(i)
	if #ns.db.bars <= 1 then ns:Print("the last bar cannot be deleted (hide it instead).") return end
	if not ns.Bars:RemoveBar(i) then ns:Print("|cffff6060no bar " .. tostring(i) .. ".|r") return end
	ns.editBar = math.min(ns.editBar, #ns.db.bars)
	app:Refresh()
	O:PluginsChanged()
	ns:Print("bar " .. i .. " deleted; its plugins are off the bars.")
end

------------------------------------------------------------------------
-- Perf
------------------------------------------------------------------------
function O:Usage()
	local out = {}
	if UpdateAddOnMemoryUsage and not InCombatLockdown() then UpdateAddOnMemoryUsage() end
	out.memKB = GetAddOnMemoryUsage and ns.Num(GetAddOnMemoryUsage(ADDON))
	local P = C_AddOnProfiler
	if P and P.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
		local E = Enum.AddOnProfilerMetric
		local function metric(k) local ok, v = pcall(P.GetAddOnMetric, ADDON, E[k]); return ok and ns.Num(v) or nil end
		out.recent, out.session, out.peak = metric("RecentAverageTime"), metric("SessionAverageTime"), metric("PeakTime")
		out.over1 = metric("CountTimeOver1Ms")
	end
	return out
end

function O:PrintPerf()
	local u = self:Usage()
	ns:Print("performance:")
	local function line(s) DEFAULT_CHAT_FRAME:AddMessage("  " .. s) end
	line("memory: " .. (u.memKB and string.format("%.0f KB", u.memKB) or "?"))
	if u.recent then
		line(string.format("CPU (game's addon profiler): %.4f ms per frame recently, %.4f ms per frame since login, peak %.2f ms, frames over 1 ms: %d",
			u.recent, u.session or 0, u.peak or 0, u.over1 or 0))
	else
		line("CPU: the game's addon profiler is not available here.")
	end
	if ns.db.profiling then
		local P = ns.prof
		local secs = math.max(1, GetTime() - P.since)
		local fps = ns.Num(GetFramerate()) or 60
		line(string.format("own timing: %.1f ms in %d calls over %d s = about %.4f ms per frame at %d fps", P.total, P.calls, secs,
			P.total / (secs * math.max(1, fps)), fps))
		local rows = {}
		for k, v in pairs(P.by) do rows[#rows + 1] = { k, v } end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		for i = 1, math.min(8, #rows) do line(string.format("   %s: %.2f ms", U.Escape(rows[i][1]), rows[i][2])) end
	else
		line("per-plugin timing: off (" .. ns.SLASH .. " profiling on, then " .. ns.SLASH .. " perf again after a while).")
	end
end

------------------------------------------------------------------------
-- Window sections
------------------------------------------------------------------------
local function barChoices()
	local t = {}
	for i, b in ipairs(ns.db.bars) do t[#t + 1] = { value = i, text = i .. ": " .. (b.name or "Bar") .. " (" .. b.edge .. ")" } end
	return t
end

local function barPicker(stack)
	return UI.Dropdown(stack, { label = "Bar to edit", width = 300, items = barChoices,
		get = function() return ns.editBar end,
		set = function(v) ns.editBar = v end,
		after = function() app:Refresh() end })
end

app:Section("bars", "Bars", function(stack)
	UI.Header(stack, "Bars", "As many bars as you like, on any edge or anywhere. Drag them in unlock mode, or set them here.")
	barPicker(stack)
	UI.ButtonRow(stack, {
		{ label = "New bar", style = "accent", width = 140, onClick = function() O:AddBar("bottom") end,
			desc = "A new bar at the bottom of the screen. Move it in unlock mode or change Where below." },
		{ label = "Delete this bar", width = 150, confirm = true, onClick = function() O:DeleteBar(ns.editBar) end },
	})
	local function W(k) return app:Widget(stack, k) end
	W("bar.name"); W("bar.shown")
	UI.Header(stack, "Place")
	W("bar.edge"); W("bar.orient"); W("bar.length"); W("bar.align"); W("bar.offset")
	UI.Header(stack, "Size and look")
	W("bar.lanes"); W("bar.lanesize"); W("bar.bg"); W("bar.line")
	W("bar.font"); W("bar.fontsize"); W("bar.outline"); W("bar.spacing"); W("bar.padding"); W("bar.strata")
end)

local function lookPopup(name, button)
	local c = ns.Host:Config(name)
	local function mark(on) return on and "|cffffc74aon|r" or "|cff8d94a3off|r" end
	UI.OpenPopup(button, {
		{ title = true, text = ns.Host:Title(name) },
		{ value = "icon", text = "Icon: " .. mark(c.icon ~= false) },
		{ value = "label", text = "Label: " .. mark(c.label) },
		{ value = "text", text = "Text: " .. mark(c.text ~= false) },
	}, nil, function(v)
		if v == "icon" or v == "text" then c[v] = c[v] == false else c[v] = not c[v] end
		ns.Host:RefreshAll()
	end, { width = 200 })
end

local function pluginIcon(n)
	local rec = ns.Host.plugins[n]
	local i = rec and rec.obj.icon
	if i ~= nil and not ns.IsSecret(i) and (type(i) == "string" or type(i) == "number") then return i end
end

-- One group of one bar: its heading and its rows (drag them, or use the buttons).
local function groupList(stack, barIndex, group, title)
	local function theBar() return ns.db.bars[barIndex] end
	local function items()
		local out = {}
		local b = theBar()
		if not b then return out end
		for lane = 1, b.lanes or 1 do
			for _, n in ipairs(ns.Host:GroupList(barIndex, lane, group)) do out[#out + 1] = n end
		end
		return out
	end
	local heading = UI.Note(stack, title, ns.Theme.text)
	local list = UI.List(stack, {
		empty = "Empty. Drag a plugin here.",
		rowHeight = 28,
		titleWidth = 200,
		items = items,
		title = function(n) return ns.Host:Title(n) end,
		detail = function(n)
			local p = ns.db.placement[n]
			local rec = ns.Host.plugins[n]
			local s = (theBar() and (theBar().lanes or 1) > 1) and ("row " .. (p and p.lane or 1)) or ""
			if rec and rec.errors > 0 then s = s .. " |cffff6060error|r" end
			return s
		end,
		icon = pluginIcon,
		buttons = {
			{ label = "<", width = 26, onClick = function(n) ns.Host:Nudge(n, -1) end },
			{ label = ">", width = 26, onClick = function(n) ns.Host:Nudge(n, 1) end },
			{ label = "Row", width = 44, shown = function() return theBar() and (theBar().lanes or 1) > 1 end, onClick = function(n)
				local p = ns.db.placement[n]
				local lanes = theBar().lanes or 1
				ns.Host:Place(n, p.bar, (p.lane or 1) % lanes + 1, p.group)
			end },
			{ label = "Group", width = 54, onClick = function(n, btn)
				UI.OpenPopup(btn, { { value = "left", text = "Left / top" }, { value = "center", text = "Centre" }, { value = "right", text = "Right / bottom" } },
					ns.db.placement[n].group, function(g) local p = ns.db.placement[n]; ns.Host:Place(n, p.bar, p.lane or 1, g) end, { width = 140 })
			end },
			{ label = "Look", width = 46, onClick = function(n, btn) lookPopup(n, btn) end },
			{ label = "Off", width = 36, onClick = function(n) ns.Host:Remove(n) end },
		},
	})
	ns.PluginDrag:AddZone({ list = list, title = heading, items = items, bar = barIndex, group = group, rowH = 28 })
	return list
end

local GROUP_TITLES = { { "left", "Left (top on side bars)" }, { "center", "Centre" }, { "right", "Right (bottom on side bars)" } }

app:Section("plugins", "Plugins", function(stack)
	ns.PluginDrag:Reset()
	UI.Header(stack, "Plugins", "Drag a row by its grip to move it: inside a group, to another group"
		.. (#ns.db.bars > 1 and " or bar" or "") .. ", or down to Not on a bar. Right-click or Escape cancels. < and > move one step.")
	barPicker(stack)
	-- the page is built for these bars; a bar added, deleted, renamed or moved to another edge builds it again
	local function barsKey()
		local t = {}
		for i, b in ipairs(ns.db.bars) do t[i] = tostring(b.name) .. " @ " .. tostring(b.edge) end
		return table.concat(t, " ; ")
	end
	local built = barsKey()
	local watch = CreateFrame("Frame")
	function watch:Refresh()
		if barsKey() ~= built then
			built = barsKey() -- once: the rebuild comes on the next frame
			C_Timer.After(0, function() app:RebuildSection("plugins") end)
		end
	end
	stack:Add(watch, 0, 0)
	local many = #ns.db.bars > 1
	for i, b in ipairs(ns.db.bars) do
		if many then UI.Header(stack, "Bar " .. i .. ": " .. (b.name or "Bar") .. " (" .. b.edge .. ")") end
		for _, g in ipairs(GROUP_TITLES) do groupList(stack, i, g[1], g[2]) end
	end
	local offHeading = UI.Header(stack, "Not on a bar", "Drag one onto a group above, or Add puts it at the right end of the bar picked above.")
	local function offItems()
		local out = {}
		for _, n in ipairs(ns.Host:Names()) do if not ns.db.placement[n] then out[#out + 1] = n end end
		return out
	end
	local off = UI.List(stack, {
		empty = "Every plugin is on a bar. Drag one here to take it off.",
		rowHeight = 28,
		titleWidth = 260,
		items = offItems,
		title = function(n) return ns.Host:Title(n) end,
		detail = function(n)
			local rec = ns.Host.plugins[n]
			return rec and ns.Host:Kind(rec) or ""
		end,
		icon = pluginIcon,
		buttons = { { label = "Add", width = 56, onClick = function(n) ns.Host:Place(n, ns.editBar, 1, "right") end } },
	})
	ns.PluginDrag:AddZone({ list = off, title = offHeading, items = offItems, rowH = 28 })
end)

app:Section("modules", "Built-in", function(stack)
	UI.Header(stack, "Built-in plugins", "Each is an ordinary LibDataBroker plugin: switched off, it costs nothing. Place them on the Plugins page.")
	for _, m in ipairs(ns.moduleOrder) do
		if m.id ~= "minimap" then app:Widget(stack, m.id .. ".enabled") end
	end
	UI.Header(stack, "XP bar")
	app:Widget(stack, "xp.width"); app:Widget(stack, "xp.decimals"); app:Widget(stack, "xp.showtext")
	UI.Header(stack, "Performance")
	app:Widget(stack, "perf.fps"); app:Widget(stack, "perf.latency"); app:Widget(stack, "perf.memory"); app:Widget(stack, "perf.colors")
	UI.Header(stack, "Location")
	app:Widget(stack, "location.zone"); app:Widget(stack, "location.subzone"); app:Widget(stack, "location.coords"); app:Widget(stack, "location.colorbypvp")
	UI.Header(stack, "Bags, mail, gold")
	app:Widget(stack, "bags.style"); app:Widget(stack, "mail.hidewhennone"); app:Widget(stack, "gold.copper")
	UI.Header(stack, "Clock and calendar")
	app:Widget(stack, "clock.realm"); app:Widget(stack, "clock.h24")
	app:Widget(stack, "calendar.style"); app:Widget(stack, "calendar.days"); app:Widget(stack, "calendar.filter")
	app:Widget(stack, "calendar.lockouts"); app:Widget(stack, "calendar.h24")
	UI.Note(stack, function()
		local cal = ns.modules.calendar
		if cal and not cal:Available() then return "The calendar API is missing in this client, so the Calendar plugin stays off." end
		return ""
	end)
	for _, g in ipairs(extGroups) do
		UI.Header(stack, g.title, "Settings from " .. g.title .. ".")
		for _, s in ipairs(g.settings) do app:Widget(stack, g.owner .. "." .. tostring(s.key)) end
	end
end)

app:Section("minimap", "Minimap", function(stack)
	UI.Header(stack, "Clean minimap", "Unlock it, then drag the minimap itself. Nothing here changes in combat; it waits for combat to end.")
	app:Widget(stack, "minimap.unlocked")
	UI.Note(stack, function()
		if mm.unlocked then
			return "Unlocked: drag the minimap with the left mouse button, mouse wheel over it to resize. Right-click it or press Lock to lock. Clicks reach the map again once locked."
		end
		return "Locked: clicks go to the map. " .. ns.SLASH .. " minimap unlock also works; moving waits until you are out of combat."
	end)
	UI.ButtonRow(stack, { { label = "Reset position", width = 140, onClick = function() mm:ResetPosition() end } })
	app:Widget(stack, "minimap.enabled")
	UI.Note(stack, function()
		if not mm.running then return "Off. Turning it off fully gives the minimap back after /reload." end
		local s = ""
		if mm.stepAside then
			s = "|cffffd25a" .. mm.stepAside .. " is managing the minimap, so " .. ns.NAME .. " leaves the minimap frame alone.|r To use this page, disable "
				.. mm.stepAside .. " (Esc > AddOns) and /reload. "
		end
		if mm.buttonRival then s = s .. "|cffffd25a" .. mm.buttonRival .. " collects the minimap buttons, so the drawer is off.|r" end
		return s
	end)
	app:Widget(stack, "minimap.scale"); app:Widget(stack, "minimap.snapedges"); app:Widget(stack, "minimap.shape")
	app:Widget(stack, "minimap.border"); app:Widget(stack, "minimap.bordersize"); app:Widget(stack, "minimap.bordercolor")
	app:Widget(stack, "minimap.wheelzoom")
	app:Widget(stack, "minimap.zonelabel"); app:Widget(stack, "minimap.zonelabelpos")
	UI.Header(stack, "Pieces around the minimap", "Blizzard's pieces: hide them, leave them, or move them (drag them in " .. ns.SLASH .. " unlock).")
	for _, e in ipairs(mm.ELEMENTS) do app:Widget(stack, "minimap." .. e.key) end
	UI.Note(stack, function()
		local list = mm.running and mm:ForeignCoords() or {}
		if #list == 0 then return "Still see text by the minimap? " .. ns.SLASH .. " minimap scan lists it with the addon it comes from." end
		local s = ""
		for _, c in ipairs(list) do s = s .. "|cffffd25a" .. c.addon .. "|r " .. c.fix .. "\n" end
		return s
	end)
	UI.Header(stack, "Addon buttons", "LibDBIcon buttons and loose buttons on the minimap.")
	app:Widget(stack, "minimap.buttons"); app:Widget(stack, "minimap.drawercorner"); app:Widget(stack, "minimap.drawercols")
	UI.ButtonRow(stack, { { label = "Look for buttons again", width = 190, onClick = function() mm:ApplyAll(); app:Refresh() end } })
	UI.List(stack, {
		empty = "No addon buttons held.",
		rowHeight = 26,
		titleWidth = 300,
		items = function() return mm:Held() end,
		title = function(b) return (b.GetName and b:GetName()) or "(unnamed)" end,
		buttons = { { label = "Leave alone", width = 100, onClick = function(b)
			local n = b.GetName and b:GetName()
			if n then ns:ModuleDB("minimap").ignore[n] = true; mm:ReleaseButtons(n); app:Refresh() end
		end } },
	})
end)

app:Section("general", "General", function(stack)
	UI.Header(stack, "General")
	app:Widget(stack, "autoadd"); app:Widget(stack, "snap"); app:Widget(stack, "grid")
	UI.Header(stack, "Performance", "What " .. ns.NAME .. " itself costs.")
	app:Widget(stack, "profiling")
	UI.Stat(stack, "Memory", function() local u = O:Usage(); return u.memKB and string.format("%.0f KB", u.memKB) or "?" end)
	UI.Stat(stack, "CPU per frame (recent)", function() local u = O:Usage(); return u.recent and string.format("%.4f ms", u.recent) or "not available" end)
	UI.Stat(stack, "CPU per frame (since login)", function() local u = O:Usage(); return u.session and string.format("%.4f ms", u.session) or "not available" end)
	UI.Header(stack, "Chat commands", "Everything here also works from chat.")
	local s = ns.SLASH
	UI.Note(stack, s .. "  this window\n" .. s .. " unlock / lock  move bars, the minimap and plugins\n"
		.. s .. " bar  list bars;  " .. s .. " bar 2  edit bar 2;  " .. s .. " bar add left  new bar\n"
		.. s .. " bar2.edge right  change one bar setting directly\n"
		.. s .. " plugins, " .. s .. " place gold 1 right, " .. s .. " remove gold\n"
		.. s .. " minimap unlock / lock / reset  move the minimap, or put it back in the corner\n"
		.. s .. " minimap scan  what the minimap module found, and any text near the minimap\n"
		.. s .. " perf  memory and CPU;  " .. s .. " status  bars, plugins, memory\n"
		.. s .. " get  every setting (get bar.edge: one)\n" .. s .. " search <words>  find a setting\n"
		.. s .. " reset bars | all | minimap  asks first (type it twice)\n" .. s .. " help  all of this in chat")
end)

------------------------------------------------------------------------
-- Hooks for the rest of the addon
------------------------------------------------------------------------
function O:Init()
	app:RegisterSlash(ns.PREFIX:upper()) -- /ebar, also /everlookbar
	for _, g in ipairs(ns.extSettings or {}) do
		local known = false
		for _, e in ipairs(extGroups) do if e == g then known = true end end
		if not known then O:AddExtSettings(g) end
	end
end

function O:PluginsChanged()
	if app:IsShown() then app:Refresh() end
end
function O:Refresh() app:Refresh() end
function O:Open(id) app:Open(id) end
