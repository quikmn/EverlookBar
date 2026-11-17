-- Everlook Bar: location. Zone and subzone (Southshore Inn, Tarren Mill) from zone events, coordinates with one
-- decimal from C_Map. Coordinates are read on the shared ticker only while you move (or ride a taxi); standing
-- still costs nothing. Where the game hides your position (most instances) the coordinates are left out.
local _, ns = ...

local M = ns:NewModule({
	id = "location", title = "Location", ldbName = ns.PREFIX .. "_Location",
	desc = "Zone, subzone and coordinates. Click to open the map.",
	defaults = { zone = true, subzone = true, coords = true, colorByPvP = true, interval = 0.2 },
	place = { group = "left", order = 1 },
})

local obj
local mapID
local zoneText = ""
local cx, cy = -1, -1 -- last shown coordinates in tenths (integers: compared, never strings)
local moving = false

local PVP_COLORS = {
	sanctuary = "|cff68ccef", friendly = "|cff62cf88", hostile = "|cffef5d5d", contested = "|cffffd25a",
	combat = "|cffef5d5d", arena = "|cffef5d5d",
}

local function zoneLabel(mdb)
	local zone = ns.Str(GetZoneText()) or ""
	local sub = ns.Str(GetSubZoneText()) or ""
	if sub == "" then sub = ns.Str(GetMinimapZoneText and GetMinimapZoneText()) or "" end
	local s = ""
	if mdb.zone then s = zone end
	if mdb.subzone and sub ~= "" and sub ~= zone then
		s = (s ~= "" and (s .. ": ") or "") .. sub
	end
	if mdb.colorByPvP and GetZonePVPInfo then
		local kind = ns.Str((GetZonePVPInfo()))
		local c = kind and PVP_COLORS[kind]
		if c and s ~= "" then s = c .. s .. "|r" end
	end
	return s
end

-- Player position on the current map in tenths of a percent, or nil where the game hides it.
function M.Position()
	if not mapID then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok or pos == nil or ns.IsSecret(pos) then return nil end
	local x, y
	if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() else return nil end
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	return math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

local function render()
	local mdb = ns:ModuleDB("location")
	local text = zoneText
	if mdb.coords and cx >= 0 then
		local c = string.format("%.1f, %.1f", cx / 10, cy / 10)
		text = text ~= "" and (text .. "  " .. c) or c
	end
	obj.text = text
end

function M:UpdateCoords()
	local x, y = M.Position()
	if not x then x, y = -1, -1 end
	if x == cx and y == cy then return end
	cx, cy = x, y
	render()
end

function M:UpdateZone()
	local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	mapID = ns.Num(m)
	zoneText = zoneLabel(ns:ModuleDB("location"))
	cx = -2 -- force a redraw
	self:UpdateCoords()
	render()
end

local function setMoving(on)
	moving = on
	local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
	M.task:SetActive((on or onTaxi) and ns:ModuleDB("location").coords and true or false)
	if not on then M:UpdateCoords() end
end

function M.Tooltip(tip)
	local zone = ns.Str(GetZoneText()) or "?"
	local sub = ns.Str(GetSubZoneText()) or ""
	ns.TipHeader(tip, zone)
	if sub ~= "" and sub ~= zone then tip:AddLine(sub, 1, 1, 1) end
	if GetZonePVPInfo then
		local kind, _, faction = GetZonePVPInfo()
		kind, faction = ns.Str(kind), ns.Str(faction)
		if kind then tip:AddLine(kind:sub(1, 1):upper() .. kind:sub(2) .. (faction and (" (" .. faction .. ")") or ""), 0.7, 0.7, 0.7) end
	end
	local x, y = M.Position()
	if x then
		tip:AddDoubleLine("Coordinates", string.format("%.1f, %.1f", x / 10, y / 10), 0.9, 0.9, 0.9, 1, 1, 1)
	else
		ns.TipHint(tip, "Coordinates are hidden here by the game.")
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "Click: open the map.")
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Location", text = "", icon = "Interface\\Icons\\INV_Misc_Map_01",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
		OnClick = function(_, button)
			if button == "LeftButton" then
				if ToggleWorldMap then ToggleWorldMap()
				elseif WorldMapFrame then WorldMapFrame:SetShown(not WorldMapFrame:IsShown()) end
			end
		end,
	})
	local mdb = ns:ModuleDB("location")
	self.task = self.task or ns.Every(self, mdb.interval or 0.2, function() M:UpdateCoords() end, false)
	local function zone() M:UpdateZone() end
	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns.On(e, self, zone)
	end
	ns.On("PLAYER_STARTED_MOVING", self, function() setMoving(true) end)
	ns.On("PLAYER_STOPPED_MOVING", self, function() setMoving(false) end)
	ns.On("PLAYER_CONTROL_LOST", self, function() setMoving(moving) end)
	ns.On("PLAYER_CONTROL_GAINED", self, function() setMoving(moving) end)
	self:UpdateZone()
end

function M:Disable() if self.task then self.task:SetActive(false) end end

-- Settings changed (zone/subzone/coords switches).
function M:Redraw() if self.running then self:UpdateZone(); setMoving(moving) end end
