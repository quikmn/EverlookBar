-- EverlookDB Bar: the settings window (/ebar), every setting also from chat, and the chat commands.
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
	aiAbout = "EverlookDB Bar puts info bars on the screen edges (or anywhere) and tidies the minimap. A bar holds plugins "
		.. "(LibDataBroker): built-in ones (XP, reputation, professions, gold, bags, clock, location, performance...) and "
		.. "those of other addons. Each plugin sits on one bar, in its left, centre or right group, in one row. The bar.* "
		.. "settings change one bar at a time (the one picked in the window, bar 1 at first); write bar2.edge to change "
		.. "bar 2. Built-in plugins have an <id>.enabled switch and their own settings; the clean minimap has the minimap.* ones.",
	accent = ns.ACCENT,
	position = function() return ns.db end,
	buttons = {
		{ label = "Unlock to move", text = function() return ns.Unlock.active and "Done moving" or "Unlock to move" end,
			onClick = function() ns.Unlock:Toggle() end,
			desc = "Drag bars to any edge or anywhere, the minimap and the pieces around it, and plugins between bars. Done or Escape ends it." },
	},
})
ns.app = app

local function bar() return ns.db and ns.db.bars[ns.editBar] end
local function relayout() ns.Host:RefreshAll() end

local EDGES = {
	{ value = "top", text = "Top of the screen" }, { value = "bottom", text = "Bottom of the screen" },
	{ value = "left", text = "Left side (plugins stacked)" }, { value = "right", text = "Right side (plugins stacked)" },
	{ value = "free", text = "Free: anywhere (Unlock to move, then drag it)" },
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
	if def.default == nil and ns.BAR_DEFAULTS[field] ~= nil then def.default = ns.BAR_DEFAULTS[field] end
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
	desc = "Top and bottom bars run along the edge; left and right bars stack their plugins. Unlock to move lets you drag a bar to any edge, or anywhere." })
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
app:Setting({ key = "autoadd", type = "bool", label = "Put plugins from other addons on bar 1 when they appear", default = ns.DEFAULTS.autoAdd,
	get = function() return ns.db.autoAdd end, set = function(v) ns.db.autoAdd = v end,
	desc = "Off: new plugins wait on the Plugins page until you add them." })
app:Setting({ key = "snap", type = "bool", label = "Snap bars to the grid while moving them", default = ns.DEFAULTS.snap,
	get = function() return ns.db.snap end, set = function(v) ns.db.snap = v end })
app:Setting({ key = "grid", type = "number", label = "Grid size (pixels)", min = 4, max = 64, default = ns.DEFAULTS.grid,
	get = function() return ns.db.grid end, set = function(v) ns.db.grid = v end })
app:Setting({ key = "bagGCD", type = "bool", label = "Hide the global cooldown spin on bag items", default = ns.DEFAULTS.hideBagGCD,
	get = function() return ns.db.hideBagGCD end, set = function(v) ns.db.hideBagGCD = v end,
	keywords = { "bagnon", "bags", "cooldown", "gcd", "spin", "swipe" },
	desc = "WoW Forever shows the global cooldown on every item in your bags after each spell. Real item cooldowns (potions, Hearthstone, trinkets) still show." })
app:Setting({ key = "profiling", type = "bool", label = "Measure EverlookDB Bar's own time per plugin (for /ebar perf)", default = ns.DEFAULTS.profiling,
	get = function() return ns.db.profiling end, set = function(v) ns.db.profiling = v; ns.SetProfiling(v) end,
	desc = "Times every call into a plugin. Costs a little itself; leave it off unless you are measuring." })

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
local function modSetting(id, field, def)
	def.key = id .. "." .. field:lower()
	def.get = def.get or function() return ns:ModuleDB(id)[field] end
	def.set = def.set or function(v) ns:ModuleDB(id)[field] = v end
	def.default = def.default or function() local m = ns.modules[id]; return m and m.defaults and m.defaults[field] end
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
	app:Setting({ key = m.id .. ".enabled", type = "bool", label = m.title, desc = m.desc, keywords = m.keywords,
		chatLabel = m.title .. " module", default = m.default ~= false,
		get = function() return ns:ModuleDB(m.id).enabled end,
		set = function(v) ns:SetModuleEnabled(m, v, true) end,
		after = function() if O.PluginsChanged then O:PluginsChanged() end end })
end

modSetting("xp", "width", { type = "number", label = "XP bar width", min = 40, max = 600 })
modSetting("xp", "decimals", { type = "number", label = "XP percent decimals", min = 0, max = 2 })
modSetting("xp", "showText", { type = "bool", label = "Show the XP percentage" })
modSetting("xp", "textInBar", { type = "bool", label = "XP percentage in the middle of the bar", keywords = { "centre", "center", "inside", "text" } })
modSetting("perf", "fps", { type = "bool", label = "Show FPS" })
modSetting("perf", "latency", { type = "choice", label = "Latency on the bar", width = 260, choices = {
	{ value = "world", text = "World (combat)" }, { value = "home", text = "Home (realm)" }, { value = "both", text = "Both (home/world)" }, { value = "none", text = "None" } } })
modSetting("perf", "memory", { type = "bool", label = "Show total addon memory (read when you hover the plugin)", keywords = { "memory", "ram", "mb" } })
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
local PROF_WORDS = { "profession", "professions", "trade", "skill", "crafting", "tradeskill" }
modSetting("professions", "primary", { type = "bool", label = "On the bar: your main professions (Mining, Tailoring...)", keywords = PROF_WORDS })
modSetting("professions", "cooking", { type = "bool", label = "On the bar: Cooking too (it is always in the fold-out)", keywords = PROF_WORDS })
modSetting("professions", "firstAid", { type = "bool", label = "On the bar: First Aid too", keywords = PROF_WORDS })
modSetting("professions", "fishing", { type = "bool", label = "On the bar: Fishing too", keywords = PROF_WORDS })
modSetting("professions", "riding", { type = "bool", label = "Show Riding", keywords = PROF_WORDS })
modSetting("professions", "names", { type = "choice", label = "Profession names", width = 260, keywords = PROF_WORDS, choices = {
	{ value = "short", text = "Short (Herb 150)" }, { value = "full", text = "Full (Herbalism 150)" }, { value = "none", text = "None, just the icon (150)" } } })
modSetting("professions", "icons", { type = "bool", label = "Profession icons", keywords = PROF_WORDS })
modSetting("professions", "showMax", { type = "bool", label = "Show the cap too (187/225)", keywords = { "profession", "max", "maximum", "cap", "limit", "skill" } })
modSetting("professions", "markCap", { type = "bool", label = "Colour a skill at its cap (time for the next trainer rank)",
	keywords = { "profession", "trainer", "rank", "cap", "max", "colour", "color", "skill" } })
modSetting("professions", "capColor", { type = "color", label = "Colour of a skill at its cap", keywords = { "profession", "trainer", "rank", "cap", "colour", "color" } })
local TRACK_WORDS = ns.modules.tracking.keywords
modSetting("tracking", "show", { type = "choice", label = "Tracking text on the bar", width = 300, keywords = TRACK_WORDS, choices = {
	{ value = "all", text = "What's tracked (Mailbox, Herbs +1)" }, { value = "first", text = "The first one only (Herbs +2)" },
	{ value = "icon", text = "Only the icon" } },
	desc = "The icon is always the first tracked type's. Click the plugin to change what the minimap tracks." })
local REP_WORDS = { "reputation", "rep", "faction", "standing", "exalted", "honored" }
local rep = ns.modules.reputation
modSetting("reputation", "faction", { type = "choice", label = "Faction to track", width = 300, choices = rep.choices,
	keywords = { "reputation", "rep", "faction", "watched", "track", "standing" },
	desc = "The game's watched faction (the default), or any faction you know. Right-click the bar to pick quickly.",
	get = function() return ns:ModuleDB("reputation").faction end,
	set = function(v) rep.Pick(v) end })
modSetting("reputation", "width", { type = "number", label = "Reputation bar width", min = 40, max = 600, keywords = REP_WORDS })
modSetting("reputation", "showName", { type = "bool", label = "Show the faction name", keywords = REP_WORDS })
modSetting("reputation", "showStanding", { type = "bool", label = "Show the standing (Friendly, Honored...)", keywords = REP_WORDS })
modSetting("reputation", "showValue", { type = "bool", label = "Show reputation value / max (1,234/6,000)", keywords = REP_WORDS })
modSetting("reputation", "showPercent", { type = "bool", label = "Show the reputation percentage", keywords = REP_WORDS })
modSetting("reputation", "textInBar", { type = "bool", label = "Reputation text in the middle of the bar", keywords = { "reputation", "rep", "centre", "center", "inside", "text" } })

------------------------------------------------------------------------
-- Minimap
------------------------------------------------------------------------
local mm = ns.modules.minimap
local function mmRedraw() if mm.running then ns.SafeCall(mm, mm.Redraw, mm) end end
local function mmSetting(field, def)
	def.key = "minimap." .. field:lower()
	def.get = def.get or function() return ns:ModuleDB("minimap")[field] end
	def.set = def.set or function(v) ns:ModuleDB("minimap")[field] = v end
	def.default = def.default or function() return mm.defaults and mm.defaults[field] end
	def.after = def.after or mmRedraw
	def.disabled = def.disabled or function() return not mm.running or mm.stepAside ~= nil end
	return app:Setting(def)
end
-- The old "Unlock minimap" switch: now the same as Unlock to move (bars, the minimap and its pieces together). Kept
-- for chat ("/ebar minimap.unlocked on") and old macros; the page has the button instead.
app:Setting({ key = "minimap.unlocked", type = "bool", label = "Unlock to move",
	keywords = { "unlock", "lock", "move", "drag", "edit" },
	get = function() return ns.Unlock.active end,
	set = function(v) if v then ns.Unlock:Start() else ns.Unlock:Stop() end end })
mmSetting("scale", { type = "number", label = "Minimap size", min = 0.5, max = 2.5, step = 0.05, fmt = "%.2f",
	after = function() mm:KeepClear(); mmRedraw() end })
mmSetting("snapEdges", { type = "bool", label = "Minimap snaps to the screen's edges when dropped", keywords = { "sticky", "magnet", "nudge", "edge" } })
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
-- The pieces around the minimap: one on/off switch each ("/ebar minimap.mail on"). A piece this game version does
-- not have, and everything while another addon manages the minimap, is greyed out.
local function pieceDisabled(e)
	if not mm.running or mm.stepAside ~= nil then return true end
	if not mm:Present(e.key) then return true end
	return e.key == "ringart" and ns:ModuleDB("minimap").shape == "square"
end
for _, e in ipairs(mm.ELEMENTS) do
	app:Setting({ key = "minimap." .. e.key, type = "bool", label = e.label, default = e.default and true or false,
		desc = e.desc, keywords = e.keywords, chatLabel = "Minimap: " .. e.label:lower(),
		get = function() return mm:PieceOn(e.key) end,
		set = function(v)
			ns:ModuleDB("minimap").pieceOn[e.key] = v and true or false
			-- a piece switched on next to a bar: the minimap makes room, so the piece is not under the bar
			if v and mm.running and not InCombatLockdown() and mm:KeepClear() then mm:ApplyFrame() end
			if mm.running then mm:ApplyElements() end
			ns.Unlock:SyncMovers()
		end,
		disabled = function() return pieceDisabled(e) end })
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

app:Movable({ what = "bars, plugins, the minimap and the pieces around it (Done or Escape locks)", get = function() return not ns.Unlock.active end,
	set = function(locked) if locked then ns.Unlock:Stop() else ns.Unlock:Start() end end })
app:Command("perf", "perf", "EverlookDB Bar's own memory and CPU use", function() O:PrintPerf() end)
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
	"move things (the same as unlock); put the minimap back; what the minimap module found; collect or skip a button by frame name", function(rest)
	local word, arg = U.Trim(rest):match("^(%S*)%s*(.*)$")
	word = (word or ""):lower()
	local db = ns:ModuleDB("minimap")
	if word == "unlock" or word == "move" then
		ns.Unlock:Start()
	elseif word == "lock" then
		ns.Unlock:Stop()
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
app:Reset("minimap", "the minimap's place and size, and the places of the pieces around it", function() ns.Unlock:ResetPositions() end)

app:StatusLines(function()
	local u, n = O:Usage(), 0
	for _ in pairs(ns.Host.plugins) do n = n + 1 end
	local lines = { #ns.db.bars .. " bar(s), " .. n .. " plugin(s); " .. (u.memKB and string.format("%.0f KB", u.memKB) or "memory ?")
		.. ". " .. ns.SLASH .. " perf for CPU." }
	for _, l in ipairs(mm:StatusLines()) do lines[#lines + 1] = l end
	return lines
end)

-- "bar2.edge" = bar.edge of bar 2: from chat ("/ebar bar2.edge left", "/ebar set bar2.edge left ; bar3.shown off") and
-- in the AI apply box (/ebar apply), where the bar picked before is put back afterwards.
function app:ResolveSetting(word)
	local n, rest = tostring(word or ""):match("^[Bb][Aa][Rr](%d+)%.(.+)$")
	if not n then return self:GetSetting(word) end
	n = tonumber(n)
	if not ns.db.bars[n] then return nil, "there is no bar " .. n .. " (" .. #ns.db.bars .. " bar" .. (#ns.db.bars == 1 and "" or "s") .. ")" end
	local def = self:GetSetting("bar." .. rest)
	if not def then return nil end
	return def, function()
		local before = ns.editBar
		ns.editBar = n
		return function() ns.editBar = before end
	end
end

-- More for the AI text (/ebar ai): every bar with its main bar.* values, and where each plugin sits.
local AI_BAR_KEYS = { "name", "shown", "edge", "lanes", "lanesize", "length", "align", "fontsize", "bg" }
app:AiExtra(function(a)
	local out = { "Bars (" .. #ns.db.bars .. "). Change one with " .. ns.SLASH .. " bar<n>.<key> <value>, e.g. "
		.. ns.SLASH .. " bar2.edge bottom; the bar.* values above are bar " .. ns.editBar .. "'s. "
		.. ns.SLASH .. " bar add [top|bottom|left|right|free] adds a bar (chat only)." }
	local before = ns.editBar
	for i in ipairs(ns.db.bars) do
		ns.editBar = i
		local vals = {}
		for _, k in ipairs(AI_BAR_KEYS) do
			local def = a:GetSetting("bar." .. k)
			local ok, v = pcall(def.get)
			vals[#vals + 1] = k .. " " .. (ok and a:AiValue(def, v) or "?")
		end
		out[#out + 1] = "- bar " .. i .. ": " .. table.concat(vals, ", ")
	end
	ns.editBar = before
	out[#out + 1] = ""
	out[#out + 1] = "Plugins and where they sit. Move one with " .. ns.SLASH .. " place <plugin> <bar> [left|center|right] [row], "
		.. "take one off with " .. ns.SLASH .. " remove <plugin>. Type these in chat, one at a time: the apply window doesn't run them."
	for _, name in ipairs(ns.Host:Names()) do
		local p = ns.db.placement[name]
		out[#out + 1] = "- " .. ns.Host:Title(name) .. ": "
			.. (p and ("bar " .. p.bar .. ", " .. (p.group or "right") .. " group, row " .. (p.lane or 1)) or "not on a bar")
	end
	return table.concat(out, "\n")
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
	ns:Print("added bar " .. ns.editBar .. " (" .. edge .. "). Put plugins on it on the Plugins page, or press Unlock to move and drag them there.")
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
	UI.Header(stack, "Bars", "As many bars as you like, on any edge or anywhere. Press Unlock to move and drag them, or set them here.")
	if not (ns.db.taskbar and ns.db.taskbar.enabled) then
		UI.Note(stack, "New: a taskbar with a Start menu, like on a PC. Switch it on on the Taskbar page.", ns.UI.Theme.accent)
	end
	barPicker(stack)
	UI.ButtonRow(stack, {
		{ label = "New bar", style = "accent", width = 140, onClick = function() O:AddBar("bottom") end,
			desc = "A new bar at the bottom of the screen. Press Unlock to move and drag it, or change Where below." },
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
	app:Widget(stack, "xp.width"); app:Widget(stack, "xp.decimals"); app:Widget(stack, "xp.showtext"); app:Widget(stack, "xp.textinbar")
	UI.Header(stack, "Reputation bar", "Coloured by standing. Right-click the bar to pick a faction; at max level it keeps its place when the XP bar hides.")
	app:Widget(stack, "reputation.faction", { items = function() return rep.Items() end, format = rep.ChoiceText })
	app:Widget(stack, "reputation.width"); app:Widget(stack, "reputation.showname"); app:Widget(stack, "reputation.showstanding")
	app:Widget(stack, "reputation.showvalue"); app:Widget(stack, "reputation.showpercent"); app:Widget(stack, "reputation.textinbar")
	UI.Header(stack, "Professions", "Click a profession on the bar to open it; right-click lists them all.")
	app:Widget(stack, "professions.primary"); app:Widget(stack, "professions.cooking"); app:Widget(stack, "professions.firstaid")
	app:Widget(stack, "professions.fishing"); app:Widget(stack, "professions.riding")
	app:Widget(stack, "professions.names"); app:Widget(stack, "professions.icons"); app:Widget(stack, "professions.showmax")
	app:Widget(stack, "professions.markcap"); app:Widget(stack, "professions.capcolor")
	UI.Header(stack, "Tracking", "What the minimap tracks. Click the plugin to tick Mailbox, Find Herbs and the rest; right-click to untrack all.")
	app:Widget(stack, "tracking.show")
	UI.Header(stack, "Performance")
	app:Widget(stack, "perf.fps"); app:Widget(stack, "perf.latency"); app:Widget(stack, "perf.memory"); app:Widget(stack, "perf.colors")
	UI.Header(stack, "Location")
	app:Widget(stack, "location.zone"); app:Widget(stack, "location.subzone"); app:Widget(stack, "location.coords"); app:Widget(stack, "location.colorbypvp")
	UI.Header(stack, "Bags, mail, gold")
	app:Widget(stack, "bags.style"); app:Widget(stack, "bagGCD"); app:Widget(stack, "mail.hidewhennone"); app:Widget(stack, "gold.copper")
	UI.Header(stack, "Quest log")
	app:Widget(stack, "quests.style"); app:Widget(stack, "quests.warn")
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

-- One piece around the minimap as a row: a small picture of it, its name, Reset (back to its own place on the
-- edge) and the on/off switch. The row is the setting's own switch (so the settings search finds it and chat sets
-- it); a piece this game version does not have folds away.
local PIECE_ICON, PIECE_RESET = 30, 58
local function pieceRow(stack, e)
	local T = stack.T
	local f = app:Widget(stack, "minimap." .. e.key)
	local art = f:CreateTexture(nil, "ARTWORK")
	art:SetPoint("CENTER", f, "LEFT", 10, 0)
	f.art = art
	if not e.fixed then
		local reset = UI.Button(f, "Reset", function()
			mm:ResetPiece(e.key)
			app:Refresh()
		end, PIECE_RESET)
		reset:SetHeight(22)
		reset:SetPoint("RIGHT", f.switch, "LEFT", -10, 0)
		f.reset = reset
	end
	-- room for the picture on the left and Reset on the right
	local measure = f.eluiMeasure
	f.eluiControlW = (f.eluiControlW or 36) + PIECE_ICON + (f.reset and (PIECE_RESET + 10) or 0)
	f.eluiMeasure = function(self, width)
		if self.absent then return 0 end
		local h = measure(self, width)
		local _, _, _, _, y = self.label:GetPoint(1)
		self.label:ClearAllPoints()
		self.label:SetPoint("TOPLEFT", self, "TOPLEFT", PIECE_ICON, y or 0)
		return h
	end
	local refresh = f.Refresh
	function f:Refresh()
		-- not in this game version (and nothing to say about it): no row
		local absent = mm.running and not mm.stepAside and not mm:Present(e.key)
		if absent ~= (self.absent or false) then
			self.absent = absent
			self:SetShown(not absent)
		end
		stack:SetHeightOf(self, self.eluiMeasure(self, stack.width))
		if absent then return end
		refresh(self)
		local a = mm.running and mm:Preview(e.key) or nil
		local w, h = 18, 18
		if a and a.w and a.h and a.w > 0 and a.h > 0 then
			local k = 20 / math.max(a.w, a.h)
			w, h = math.max(8, a.w * k), math.max(8, a.h * k)
		end
		art:SetSize(w, h)
		if a and a.atlas and art.SetAtlas then
			art:SetTexCoord(0, 1, 0, 1)
			art:SetAtlas(a.atlas)
			art:SetVertexColor(1, 1, 1, 1)
			art:Show()
		elseif a and a.file then
			art:SetTexture(a.file)
			if a.coords and #a.coords >= 4 then art:SetTexCoord(unpack(a.coords)) else art:SetTexCoord(0, 1, 0, 1) end
			art:SetVertexColor(1, 1, 1, 1)
			art:Show()
		else
			UI.SetIcon(art, e.icon or "dot")
			art:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 1)
		end
		if self.desc then
			local text = e.desc
			if mm.waiting[e.key] then
				text = "|cffffd25aWaits for combat to end, then it is applied.|r"
			elseif e.key == "ringart" and ns:ModuleDB("minimap").shape == "square" then
				text = "For a round minimap only."
			elseif mm:IsMoved(e.key) then
				text = text .. " |cffffd25aMoved.|r"
			end
			self.desc:SetText(text)
		end
		if self.reset then self.reset:SetUsable(mm.running and not mm.stepAside and mm:IsMoved(e.key)) end
	end
	f:Refresh()
	return f
end
O.PieceRow = pieceRow

app:Section("minimap", "Minimap", function(stack)
	UI.Header(stack, "Minimap", "Move and shape the minimap, and choose what sits around it.")
	-- the page's one gold button, and Reset positions beside it (the row is the "minimap.unlocked" setting to the
	-- settings search and to chat)
	do
		local row = CreateFrame("Frame")
		row:SetParent(stack.parent)
		local help = "Drag the minimap, the pieces around it, bars and plugins. Done (in the middle of the minimap) or Escape ends it."
		local unlock = UI.Button(row, "Unlock to move", function() ns.Unlock:Toggle() end, 170, "accent")
		unlock:SetPoint("LEFT", 0, 0)
		local reset = UI.ConfirmButton(row, "Reset positions", function() ns.Unlock:ResetPositions(); app:Refresh() end, 170, "plain")
		reset:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
		row.buttons = { unlock, reset }
		row.searchInfo = { label = "Unlock to move / Reset positions", key = "minimap.unlocked",
			desc = help .. " Reset positions: the minimap back in the top-right corner at 100%, every piece back in its own place.",
			keywords = { "unlock", "lock", "move", "drag", "edit", "place", "position", "reset", "default", "corner" } }
		function row:Refresh()
			unlock:SetText(ns.Unlock.active and "Done moving" or "Unlock to move")
			reset:SetUsable(mm.running and mm.stepAside == nil)
		end
		stack:Add(row, 26, 12)
		row:Refresh()
		O.unlockRow = row
	end
	UI.Note(stack, function()
		if not mm.running then
			return "The clean minimap is off, so the game shows its own minimap. Turning it off fully gives the minimap back after /reload."
		end
		local s = ""
		if mm.stepAside then
			s = "|cffffd25a" .. mm.stepAside .. " is managing the minimap, so " .. ns.NAME .. " leaves it alone and this page is greyed out.|r To use it, disable "
				.. mm.stepAside .. " (Esc > AddOns) and /reload. "
		end
		if mm.buttonRival then s = s .. "|cffffd25a" .. mm.buttonRival .. " collects the minimap buttons, so the drawer is off.|r " end
		if s ~= "" then return s end
		if mm:Waiting() then
			return "|cffffd25aYou are in combat: what the game locks in combat is applied when combat ends.|r"
		end
		if ns.Unlock.active then
			return "Moving: drag the minimap, the pieces around it, bars and plugins. Mouse wheel over the minimap changes its size. Done or Escape ends it."
		end
		return "Unlock to move, then drag the minimap and the pieces around it. Mouse wheel over the minimap changes its size."
	end)
	app:Widget(stack, "minimap.enabled")
	UI.Header(stack, "Size and shape")
	app:Widget(stack, "minimap.shape"); app:Widget(stack, "minimap.scale")
	app:Widget(stack, "minimap.border"); app:Widget(stack, "minimap.bordersize"); app:Widget(stack, "minimap.bordercolor")
	app:Widget(stack, "minimap.wheelzoom"); app:Widget(stack, "minimap.snapedges")
	UI.Header(stack, "Pieces around the minimap", "Switch one on and it sits on the minimap's edge. To move it: Unlock to move, then drag it.")
	for _, e in ipairs(mm.ELEMENTS) do pieceRow(stack, e) end
	UI.Header(stack, "Zone line", "Our own line of text with where you are, instead of the game's zone name.")
	app:Widget(stack, "minimap.zonelabel"); app:Widget(stack, "minimap.zonelabelpos")
	UI.Note(stack, function()
		local list = mm.running and mm:ForeignCoords() or {}
		if #list == 0 then return "Still see text by the minimap? " .. ns.SLASH .. " minimap scan lists it with the addon it comes from." end
		local s = ""
		for _, c in ipairs(list) do s = s .. "|cffffd25a" .. c.addon .. "|r " .. c.fix .. "\n" end
		return s
	end)
	UI.Header(stack, "Addon buttons", "The minimap buttons other addons add.")
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
	UI.Note(stack, s .. "  this window\n" .. s .. " unlock / lock  move bars, plugins, the minimap and its pieces (the Unlock to move button)\n"
		.. s .. " bar  list bars;  " .. s .. " bar 2  edit bar 2;  " .. s .. " bar add left  new bar\n"
		.. s .. " bar2.edge right  change one bar setting directly\n"
		.. s .. " plugins, " .. s .. " place gold 1 right, " .. s .. " remove gold\n"
		.. s .. " minimap.mail on  switch a piece around the minimap;  " .. s .. " minimap reset  put it all back\n"
		.. s .. " minimap scan  what the minimap module found, and any text near the minimap\n"
		.. s .. " taskbar on  the taskbar;  " .. s .. " start  the Start menu;  " .. s .. " tile  tile your windows\n"
		.. s .. " perf  memory and CPU;  " .. s .. " status  bars, plugins, memory\n"
		.. s .. " get  every setting (get bar.edge: one)\n" .. s .. " search <words>  find a setting\n"
		.. s .. " reset bars | all | minimap  asks first (type it twice)\n" .. s .. " help  all of this in chat")
end)

------------------------------------------------------------------------
-- Taskbar
------------------------------------------------------------------------
local TB_EDGES = { { value = "bottom", text = "Bottom of the screen" }, { value = "top", text = "Top of the screen" },
	{ value = "left", text = "Left side" }, { value = "right", text = "Right side" } }
local function tdb() return ns.db.taskbar end
local function tbRefresh() if ns.Taskbar then ns.Taskbar:Refresh() end end
app:Setting({ key = "taskbar.enabled", type = "bool", label = "Taskbar with a Start menu", default = false,
	get = function() return tdb().enabled end, set = function(v) ns.Taskbar:SetEnabled(v) end,
	keywords = { "start", "menu", "windows", "taskbar", "minimize", "tile", "tiling", "snap", "maximize" },
	desc = "A bar with a Start button and a button for every open window: minimize, bring back, maximize, snap and tile them." })
app:Setting({ key = "taskbar.edge", type = "choice", label = "Taskbar sits at", choices = TB_EDGES, width = 240, default = "bottom",
	get = function() return tdb().edge end, set = function(v) ns.Taskbar:SetEdge(v) end })
app:Setting({ key = "taskbar.size", type = "number", label = "Taskbar thickness (width on the left or right)", min = 20, max = 300, default = 32,
	get = function() return ns.Taskbar:Size() end, set = function(v) ns.Taskbar:SetSize(v) end })
app:Setting({ key = "taskbar.labels", type = "bool", label = "Window names on the buttons", default = true,
	get = function() return tdb().labels end, set = function(v) tdb().labels = v end, after = tbRefresh,
	desc = "Off: icons only, so more windows fit." })
app:Setting({ key = "taskbar.snap", type = "bool", label = "Snap windows dragged to a screen edge", default = true,
	get = function() return tdb().snap end, set = function(v) tdb().snap = v end,
	desc = "Drag an EverlookDB window to the top edge to maximize it, to the left or right edge for half the screen, into a corner for a quarter." })
app:Setting({ key = "taskbar.gap", type = "number", label = "Space around snapped and tiled windows", min = 0, max = 30, default = 4,
	get = function() return tdb().gap end, set = function(v) tdb().gap = v end })
app:Setting({ key = "taskbar.blizzard", type = "bool", label = "List the game's windows", default = true,
	get = function() return tdb().blizzard end, set = function(v) tdb().blizzard = v; if ns.WM.running then ns.WM:Scan(true) end end,
	desc = "Character, spellbook, map, bags and the rest. Click opens and closes them; the game keeps them in their place." })
app:Setting({ key = "taskbar.others", type = "bool", label = "List other addons' windows", default = true,
	get = function() return tdb().others end, set = function(v) tdb().others = v; if ns.WM.running then ns.WM:Scan(true) end end,
	desc = "Windows of other addons that can be moved. Right-click one's button and pick Don't list this window to leave it out." })

local function needTaskbar()
	if tdb().enabled then return true end
	ns:Print("the taskbar is off. " .. ns.SLASH .. " taskbar on switches it on.")
	return false
end
app:Command("start", "start [words]", "open the Start menu (with a search)", function(rest) ns.StartMenu:Show(U.Trim(rest)) end)
app:Command("tile", "tile", "tile all open windows", function() if needTaskbar() then ns.Taskbar:TileAll() end end)
app:Command("desktop", "desktop", "minimize all windows", function() if needTaskbar() then ns.WM:MinimizeAll() end end, { "minimize" })
app:Command("restore", "restore", "bring every minimized window back", function() if needTaskbar() then ns.WM:RestoreAll() end end)
app:Command("taskbar", "taskbar [on|off|top|bottom|left|right]", "the taskbar: switch it, or put it on an edge", function(rest)
	local w = U.Trim(rest):lower()
	if w == "on" or w == "off" then
		ns.Taskbar:SetEnabled(w == "on")
		ns:Print("taskbar " .. w .. ".")
	elseif w == "top" or w == "bottom" or w == "left" or w == "right" then
		ns.Taskbar:SetEdge(w)
		if not tdb().enabled then ns.Taskbar:SetEnabled(true) end
		ns:Print("taskbar at the " .. w .. ".")
	else
		app:Open("taskbar")
	end
end)

app:Section("taskbar", "Taskbar", function(stack)
	UI.Header(stack, "Taskbar", "A Start button and your open windows, like on a PC.")
	UI.Note(stack, "Start lists every window you can open: EverlookDB windows and pages, the game's panels, your professions and addon buttons. Type to search, Enter opens the first; right-click one to pin it.\n"
		.. "Click a window's button to bring it to the front; click again to minimize it. Right-click for maximize, snap to a half, quarter or third, and close. Drag an EverlookDB window to a screen edge to snap it.")
	local function Wd(k) return app:Widget(stack, k) end
	Wd("taskbar.enabled"); Wd("taskbar.edge"); Wd("taskbar.size"); Wd("taskbar.labels")
	UI.Header(stack, "Windows")
	Wd("taskbar.snap"); Wd("taskbar.gap"); Wd("taskbar.blizzard"); Wd("taskbar.others")
	UI.ButtonRow(stack, {
		{ label = "Open the Start menu", width = 170, onClick = function() ns.StartMenu:Show() end,
			desc = "Also " .. ns.SLASH .. " start, or a key: Settings > Keybindings > AddOns > " .. ns.NAME .. "." },
		{ label = "Tile all windows", width = 150, onClick = function() if needTaskbar() then ns.Taskbar:TileAll() end end },
	})
	UI.Note(stack, "The game's own windows keep the place the game gives them, so they aren't moved or tiled. In combat, windows the game protects change when combat ends.",
		ns.UI.Theme.muted)
end, { icon = "frames", desc = "A Start menu and a button for every open window." })

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
