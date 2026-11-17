-- Everlook Bar: the public API, EverlookBar.API. For what LibDataBroker cannot say: custom widgets drawn inside a
-- plugin's button, settings for a module, the shared ticker, and placement. See API.md.
--
-- Compatibility promise: API.VERSION only grows. A function, once published, keeps its name, arguments and meaning
-- in every later version; new things are new functions or new optional fields. Code written for version 1 keeps
-- working on every later version.
local _, ns = ...
local API = {}
ns.API = API
local public = _G[ns.GLOBAL]
public.API = API

API.VERSION = 1
API.widgets = {} -- [ldbName] = spec (internal; read through API.GetWidget)

local function isName(v) return type(v) == "string" and v ~= "" end

-- 1: the API version (a number). Check it with `if EverlookBar.API.GetVersion() >= 1 then`.
function API.GetVersion() return API.VERSION end

-- 1: draw something of your own inside your LDB plugin's button (a bar, a meter, a row of icons).
-- ldbName: your data object's name. spec:
--   width   number, or function(dataobj, ldbName) -> number (0 hides the widget)
--   create  function(frame, dataobj, ldbName), called once with an empty Frame inside the button
--   update  function(frame, dataobj, ldbName), called when the button redraws (your data object changed)
-- The text of your data object still shows after the widget. Other LDB displays just show the text.
-- Returns true. Calling it again for the same name replaces the spec for buttons made after that.
function API.RegisterWidget(ldbName, spec)
	assert(isName(ldbName), "RegisterWidget: ldbName must be a string")
	assert(type(spec) == "table", "RegisterWidget: spec must be a table")
	API.widgets[ldbName] = spec
	local rec = ns.Host and ns.Host.plugins[ldbName]
	if rec and rec.button then
		ns.Bars:AttachWidget(rec, spec)
		ns.Host:OnAttr(nil, ldbName, "text")
	end
	return true
end

function API.GetWidget(ldbName) return API.widgets[ldbName] end

-- 1: ask for a redraw of your plugin (after your widget's data changed without a data object change).
function API.Refresh(ldbName)
	if ns.Host and ns.Host.plugins[ldbName] then ns.Host:OnAttr(nil, ldbName, "text") end
end

-- 1: hide or show your plugin's button without taking it off its bar (e.g. an XP bar at max level).
function API.SetHidden(ldbName, hidden)
	local rec = ns.Host and ns.Host.plugins[ldbName]
	if not rec then return false end
	rec.obj.ebarHidden = hidden and true or nil
	return true
end

-- 1: run fn(task, now) every `interval` seconds on Everlook Bar's one shared ticker (0.1 s resolution).
-- Returns a task with :SetActive(bool), :SetInterval(seconds) and :Cancel(). Errors in fn are caught and shown on
-- the owner's button; `owner` is your LDB name (or any string naming you).
function API.Every(owner, interval, fn)
	assert(type(fn) == "function", "Every: fn must be a function")
	local o = { name = tostring(owner or "plugin"), ldbName = isName(owner) and owner or nil }
	return ns.Every(o, interval, fn)
end

-- 1: settings for your module, shown in the settings window (Built-in page, under your title) and in chat as
-- "/ebar <owner>.<key> <value>". owner: a short id ("myaddon"). title: what the window calls it.
-- settings: { { key, type = "bool"|"number"|"choice"|"color"|"string", label, desc, default,
--               min, max, step (numbers), choices = { { value, text } } (choice), onChange = function(value) } }
-- Values are saved by Everlook Bar per character profile. Returns get(key) and set(key, value) functions.
function API.RegisterSettings(owner, title, settings)
	assert(isName(owner) and owner:match("^[%w_]+$"), "RegisterSettings: owner must be letters, digits or _")
	assert(type(settings) == "table", "RegisterSettings: settings must be a table")
	local store = function()
		if not ns.db then return nil end
		ns.db.ext[owner] = ns.db.ext[owner] or {}
		return ns.db.ext[owner]
	end
	local defaults = {}
	for _, s in ipairs(settings) do defaults[s.key] = s.default end
	local function get(key)
		local t = store()
		local v = t and t[key]
		if v == nil then v = defaults[key] end
		return v
	end
	local function set(key, value)
		local t = store()
		if not t then return end
		t[key] = value
	end
	local group = { owner = owner, title = tostring(title or owner), settings = settings, get = get, set = set }
	ns.extSettings = ns.extSettings or {}
	ns.extSettings[#ns.extSettings + 1] = group
	if ns.Options and ns.Options.AddExtSettings then ns.Options:AddExtSettings(group) end
	return get, set
end

-- 1: put an LDB plugin on a bar. bar: 1.., group: "left" | "center" | "right", index: position in the group (nil:
-- last). Meant for a first-run default; respect a player who moved it (check API.GetPlacement first).
function API.Place(ldbName, bar, group, index)
	if not (ns.Host and ns.db and ns.Host.plugins[ldbName]) then return false end
	ns.Host:Place(ldbName, bar or 1, 1, group or "right", index)
	return true
end

-- 1: where a plugin is: bar, group, index, lane; nil when it is on no bar.
function API.GetPlacement(ldbName)
	local p = ns.db and ns.db.placement[ldbName]
	if not p then return nil end
	local list = ns.Host:GroupList(p.bar, p.lane or 1, p.group)
	local index
	for i, n in ipairs(list) do if n == ldbName then index = i end end
	return p.bar, p.group, index, p.lane or 1
end

-- 1: number of bars.
function API.GetNumBars() return ns.db and #ns.db.bars or 0 end
