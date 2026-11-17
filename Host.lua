-- Everlook Bar: the LDB host. Every LibDataBroker data object (from any addon, and our own built-ins) is a plugin
-- that can be put on a bar. Attribute changes mark the plugin dirty; all dirty plugins are redrawn together on the
-- next frame, so a plugin that writes text ten times in one frame costs one redraw.
local _, ns = ...
local Host = { plugins = {}, order = {} }
ns.Host = Host
local L = ns.Layout

local ldb
local dirty = {}
local relayout = false

-- Attributes that change what a button shows.
local VISUAL = {
	text = true, value = true, suffix = true, label = true, icon = true, iconCoords = true,
	iconR = true, iconG = true, iconB = true, ebarHidden = true, type = true,
}

local function plugin(name) return Host.plugins[name] end
Host.Get = plugin

function Host:Kind(rec)
	local t = ns.Str(rec.obj.type)
	if t == "launcher" then return "launcher" end
	return "data source"
end

-- Display options for a plugin (icon, label, text), defaults by kind.
function Host:Config(name)
	local c = ns.db.plugins[name]
	if not c then
		local rec = plugin(name)
		local launcher = rec and self:Kind(rec) == "launcher"
		c = { icon = true, label = launcher, text = true }
		ns.db.plugins[name] = c
	end
	return c
end

-- The module that made a built-in plugin, if any.
function Host:ModuleOf(name)
	for _, m in ipairs(ns.moduleOrder) do
		if m.ldbName == name then return m end
	end
end

-- Should the plugin have a button? Placed, its module (if built in) running, and not asking to be hidden.
function Host:Wanted(name)
	local rec = plugin(name)
	if not rec then return false end
	local p = ns.db.placement[name]
	if not p or not ns.db.bars[p.bar] then return false end
	local m = rec.module
	if m and not m.running then return false end
	if rec.obj.ebarHidden == true then return false end
	return true
end

local function add(name, obj)
	if type(name) ~= "string" or Host.plugins[name] then return end
	local rec = { name = name, obj = obj, errors = 0 }
	rec.module = Host:ModuleOf(name)
	if rec.module then rec.name = rec.module.title or name end
	rec.key = name
	Host.plugins[name] = rec
	Host.order[#Host.order + 1] = name
	if ns.db and ns.db.autoAdd and not rec.module and not ns.db.placement[name] then
		Host:Place(name, 1, 1, "right")
	end
	return rec
end

function Host:Init()
	ldb = LibStub("LibDataBroker-1.1")
	self.ldb = ldb
	for name, obj in ldb:DataObjectIterator() do add(name, obj) end
	ldb.RegisterCallback(self, "LibDataBroker_DataObjectCreated", "OnCreated")
	ldb.RegisterCallback(self, "LibDataBroker_AttributeChanged", "OnAttr")
end

function Host:OnCreated(_, name, obj)
	local rec = add(name, obj)
	if rec and self:Wanted(name) then relayout = true; dirty[name] = true; ns.Soon(Host.Flush, Host) end
	if ns.Options then ns.Options:PluginsChanged() end
end

function Host:OnAttr(_, name, key, value)
	if not VISUAL[key] then return end
	local rec = plugin(name)
	if not rec then return end
	if key == "ebarHidden" then relayout = true end
	dirty[name] = true
	ns.Soon(Host.Flush, Host)
end

-- Redraw dirty plugins; lay bars out again when a width changed.
function Host.Flush()
	for name in pairs(dirty) do
		dirty[name] = nil
		local rec = plugin(name)
		if rec then
			local wanted = Host:Wanted(name)
			if wanted ~= (rec.button ~= nil and rec.button:IsShown()) then relayout = true end
			if wanted and ns.Bars:UpdateButton(rec) then relayout = true end
		end
	end
	if relayout then
		relayout = false
		ns.Bars:LayoutAll()
	end
end

-- A plugin's code failed: its button shows the error marker.
function Host:OnOwnerError(owner)
	local rec = owner
	if owner and owner.ldbName then rec = plugin(owner.ldbName) end
	if rec and rec.errors ~= nil and rec ~= owner then rec.errors = (rec.errors or 0) + 1; rec.lastError = owner.lastError end
	if rec and rec.button then ns.Bars:ShowError(rec) end
end

-- Everything again (settings changed, a module switched).
function Host:RefreshAll()
	if not ns.Bars.ready then return end
	for name in pairs(self.plugins) do dirty[name] = true end
	relayout = true
	Host.Flush()
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
-- Names placed in one group, in order.
function Host:GroupList(bar, lane, group)
	local list = {}
	for name, p in pairs(ns.db.placement) do
		if p.bar == bar and (p.lane or 1) == lane and p.group == group then list[#list + 1] = name end
	end
	table.sort(list, function(a, b)
		local pa, pb = ns.db.placement[a], ns.db.placement[b]
		if pa.order ~= pb.order then return (pa.order or 0) < (pb.order or 0) end
		return a < b
	end)
	return list
end

-- Put `name` on bar/lane/group at index (end when nil).
function Host:Place(name, bar, lane, group, index)
	bar = tonumber(bar) or 1
	lane = tonumber(lane) or 1
	if group ~= "left" and group ~= "center" and group ~= "right" then group = "left" end
	ns.db.placement[name] = ns.db.placement[name] or {}
	local p = ns.db.placement[name]
	p.bar, p.lane, p.group, p.order = bar, lane, group, -1
	local list = L.Reorder(self:GroupList(bar, lane, group), name, index)
	for i, n in ipairs(list) do ns.db.placement[n].order = i end
	self:RefreshAll()
	if ns.Options then ns.Options:PluginsChanged() end
end

function Host:Remove(name)
	ns.db.placement[name] = nil
	self:RefreshAll()
	if ns.Options then ns.Options:PluginsChanged() end
end

-- Move one step left/right inside its group.
function Host:Nudge(name, delta)
	local p = ns.db.placement[name]
	if not p then return end
	local list = self:GroupList(p.bar, p.lane or 1, p.group)
	for i, n in ipairs(list) do
		if n == name then
			self:Place(name, p.bar, p.lane or 1, p.group, math.max(1, i + delta))
			return
		end
	end
end

-- A built-in's first placement: bar 1 in its usual spot, unless it already sits somewhere.
function Host:PlaceDefault(name, place)
	if ns.db.placement[name] then return end
	place = place or {}
	self:Place(name, 1, 1, place.group or "right", place.order)
end

-- A bar was deleted: its plugins come off; later bars move down one number.
function Host:BarRemoved(index)
	for name, p in pairs(ns.db.placement) do
		if p.bar == index then ns.db.placement[name] = nil
		elseif p.bar > index then p.bar = p.bar - 1 end
	end
end

-- Sorted list of plugin names for the settings window.
function Host:Names()
	local t = {}
	for name, rec in pairs(self.plugins) do
		if not rec.module or rec.module.running then t[#t + 1] = name end
	end
	table.sort(t, function(a, b)
		local ra, rb = self.plugins[a], self.plugins[b]
		local ba, bb = ra.module and 0 or 1, rb.module and 0 or 1
		if ba ~= bb then return ba < bb end
		return a:lower() < b:lower()
	end)
	return t
end

-- What the settings window and the tooltip call a plugin.
function Host:Title(name)
	local rec = plugin(name)
	if not rec then return name end
	if rec.module then return rec.module.title end
	local label = ns.Str(rec.obj.label)
	if label and label ~= "" and label ~= name then return name .. " (" .. label .. ")" end
	return name
end
