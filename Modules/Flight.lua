-- EverlookDB Bar: flight timer. While you ride a flight path the bar shows where to and the time left
-- ("» Ironforge 1:42"). It learns each route's time from your own flights (a running average, outliers left out);
-- until you have flown a route it counts down from EverlookDB's estimate ("~1:42", FlightData.lua), and where there
-- is none it counts up ("0:35 (first time)"). Hidden on the ground. The destination comes from a hook on
-- TakeTaxiNode; the start and the landing from UnitOnTaxi, polled only while a flight is picked or under way.
local _, ns = ...

local M = ns:NewModule({
	id = "flight", title = "Flight timer", ldbName = ns.PREFIX .. "_Flight",
	desc = "On a flight path: where you're going and the time left. Hidden on the ground.",
	keywords = { "flight", "flight path", "flight master", "taxi", "gryphon", "wyvern", "hippogryph", "bat", "timer", "countdown", "landed" },
	defaults = { arrival = false, routes = {} },
	place = { group = "left", order = 2 },
})

M.MIN, M.MAX = 5, 3600 -- a flight shorter or longer than this (seconds) is never learned
M.PENDING = 15          -- seconds after picking a destination for the flight to start
M.RECENT = 5            -- routes listed in the tooltip

local obj
local pending -- picked at the flight master, not in the air yet: { from, to, fromID, toID, cont, key, est, at }
local flight  -- in the air: the same fields plus start (GetTime), resumed (after a /reload), unknown (no hook)
local shownKey

local floor = math.floor
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end
local function routes() return ns:ModuleDB("flight").routes end

------------------------------------------------------------------------
-- Pure logic (tests drive these)
------------------------------------------------------------------------
function M.Format(s)
	s = floor((tonumber(s) or 0) + 0.5)
	if s < 0 then s = 0 end
	if s >= 3600 then return string.format("%d:%02d:%02d", floor(s / 3600), floor(s / 60) % 60, s % 60) end
	return string.format("%d:%02d", floor(s / 60), s % 60)
end

-- "Ironforge, Dun Morogh" -> "Ironforge"
function M.Short(name)
	name = tostring(name or "?")
	return name:match("^(.-),") or name
end

-- Node IDs where the client gives them; else the names plus the continent, so the same names elsewhere don't clash.
function M.RouteKey(cont, from, to, fromID, toID)
	if fromID and toID then return "id:" .. fromID .. ">" .. toID end
	return tostring(cont or "?") .. ":" .. tostring(from) .. ">" .. tostring(to)
end

-- Further than this from a route's average and a flight is an outlier (a disconnect, a stop on the way).
function M.Tolerance(avg) return math.max(20, avg * 0.35) end

-- Take one flight's time into a route's running average. Returns true when it was taken. Two outliers in a row
-- that agree with each other mean the route itself changed: they become the new average.
function M.Learn(r, secs)
	secs = tonumber(secs)
	if not secs or secs < M.MIN or secs > M.MAX then return false end
	local n = tonumber(r.n) or 0
	if n == 0 or not r.avg then
		r.avg, r.n, r.alt = secs, 1, nil
		return true
	end
	if math.abs(secs - r.avg) <= M.Tolerance(r.avg) then
		local w = math.min(n, 9) -- after ten flights each new one counts a tenth, so the average can still follow
		r.avg = (r.avg * w + secs) / (w + 1)
		r.n, r.alt = n + 1, nil
		return true
	end
	if r.alt and math.abs(secs - r.alt) <= M.Tolerance(r.alt) then
		r.avg, r.n, r.alt = (secs + r.alt) / 2, 2, nil
		return true
	end
	r.alt = secs
	return false
end

local function hop(a, b)
	local D = ns.FlightData
	local t = D and a and D.hops[a]
	return t and b and t[b] or nil
end

-- The fewest estimated seconds from node a to node b over the known hops.
function M.Shortest(a, b)
	local D = ns.FlightData
	if not D or not a or not b then return nil end
	local dist, done = { [a] = 0 }, {}
	while true do
		local u, best
		for n, d in pairs(dist) do
			if not done[n] and (not best or d < best) then u, best = n, d end
		end
		if not u then return nil end
		if u == b then return best end
		done[u] = true
		for v, s in pairs(D.hops[u] or {}) do
			local nd = best + s
			if not dist[v] or nd < dist[v] then dist[v] = nd end
		end
	end
end

-- EverlookDB's estimate for a flight: the hops the game says it flies, summed; else the direct hop; else the
-- shortest way over the known hops. nil when the nodes are unknown.
function M.Estimate(fromID, toID, path)
	if not fromID or not toID then return nil end
	if type(path) == "table" and #path >= 2 then
		local sum = 0
		for i = 1, #path - 1 do
			local s = hop(path[i], path[i + 1]) or hop(path[i + 1], path[i])
			if not s then sum = nil break end
			sum = sum + s
		end
		if sum then return sum end
	end
	return hop(fromID, toID) or hop(toID, fromID) or M.Shortest(fromID, toID)
end

-- The time to count down from: your own average, else the estimate. Returns secs, "yours"|"estimate", flights.
function M.Expected(f)
	local r = f and f.key and routes()[f.key]
	if r and (tonumber(r.n) or 0) > 0 and r.avg then return r.avg, "yours", r.n end
	if f and f.est then return f.est, "estimate", 0 end
	return nil
end

function M.Text(f, elapsed)
	if f.unknown then return "In flight " .. M.Format(elapsed) end
	local dest = "» " .. M.Short(f.to) .. " "
	local exp, kind = M.Expected(f)
	if kind == "yours" then return dest .. M.Format(exp - elapsed) end
	if kind == "estimate" then return dest .. "~" .. M.Format(exp - elapsed) end
	return dest .. M.Format(elapsed) .. " (first time)"
end

-- Learned routes, the most recently flown first.
function M.Recent(max)
	local list = {}
	for _, r in pairs(routes()) do
		if type(r) == "table" and (tonumber(r.n) or 0) > 0 then list[#list + 1] = r end
	end
	table.sort(list, function(a, b) return (tonumber(a.last) or 0) > (tonumber(b.last) or 0) end)
	local total = #list
	for i = #list, (max or #list) + 1, -1 do list[i] = nil end
	return list, total
end

------------------------------------------------------------------------
-- The game
------------------------------------------------------------------------
local function onTaxi()
	local v = call(UnitOnTaxi, "player")
	if ns.IsSecret(v) then return false end
	return v and true or false
end

local idByName
local function nodeByName(name)
	local D = ns.FlightData
	if not name or not D then return nil end
	if not idByName then
		idByName = {}
		for id, n in pairs(D.nodes) do idByName[n[1]] = id end
	end
	return idByName[name]
end

-- The continent's map ID (or the zone's, if the client has no map tree); only used to key routes by name.
function M.Continent()
	local C = C_Map
	if not C then return "?" end
	local best = ns.Num(call(C.GetBestMapForUnit, "player"))
	local CONT = Enum and Enum.UIMapType and ns.Num(Enum.UIMapType.Continent) or 2
	local id = best
	for _ = 1, 8 do
		if not id or id == 0 then break end
		local info = call(C.GetMapInfo, id)
		if type(info) ~= "table" then break end
		if ns.Num(info.mapType) == CONT then return id end
		id = ns.Num(info.parentMapID)
	end
	return best or "?"
end

-- The open flight map: [slot] = { id = taxi node ID or nil, name }, and the slot you stand at.
function M.ReadMap()
	local bySlot, cur = {}, nil
	local list = C_TaxiMap and call(C_TaxiMap.GetAllTaxiNodes, ns.Num(call(GetTaxiMapID)))
	if type(list) == "table" then
		local CURRENT = Enum and Enum.FlightPathState and ns.Num(Enum.FlightPathState.Current)
		for _, info in ipairs(list) do
			if type(info) == "table" then
				local slot = ns.Num(info.slotIndex)
				if slot then
					bySlot[slot] = { id = ns.Num(info.nodeID), name = ns.Str(info.name) }
					if CURRENT and ns.Num(info.state) == CURRENT then cur = slot end
				end
			end
		end
	end
	local n = ns.Num(call(NumTaxiNodes)) or 0
	for i = 1, n do
		local s = bySlot[i] or {}
		bySlot[i] = s
		s.name = s.name or ns.Str(call(TaxiNodeName, i))
		if not cur and ns.Str(call(TaxiNodeGetType, i)) == "CURRENT" then cur = i end
	end
	for _, s in pairs(bySlot) do s.id = s.id or nodeByName(s.name) end
	return bySlot, cur
end

-- The nodes the game will fly through to reach `slot`, as node IDs (nil when it doesn't say).
local function hopsTo(map, slot)
	local hops = ns.Num(call(GetNumRoutes, slot))
	if not hops or hops < 1 then return nil end
	local path = {}
	for h = 1, hops do
		local src = ns.Num(call(TaxiGetNodeSlot, slot, h, true))
		local dst = ns.Num(call(TaxiGetNodeSlot, slot, h, false))
		local a, b = src and map[src] and map[src].id, dst and map[dst] and map[dst].id
		if not a or not b then return nil end
		if h == 1 then path[1] = a end
		path[h + 1] = b
	end
	return path
end

-- TakeTaxiNode(slot) was called: note the route. The flight itself starts when UnitOnTaxi turns true.
function M.OnTakeTaxi(slot)
	if not M.running then return end
	slot = ns.Num(slot)
	if not slot then return end
	local map, cur = M.ReadMap()
	local dest = map[slot]
	if not dest or not dest.name then return end
	local from = cur and map[cur] or {}
	local p = { to = dest.name, toID = dest.id, from = from.name, fromID = from.id, at = GetTime() }
	if p.fromID and ns.FlightData and ns.FlightData.nodes[p.fromID] then p.cont = ns.FlightData.nodes[p.fromID][2]
	else p.cont = M.Continent() end
	p.est = M.Estimate(p.fromID, p.toID, hopsTo(map, slot))
	if p.from then p.key = M.RouteKey(p.cont, p.from, p.to, p.fromID, p.toID) end
	pending = p
	M.task:SetActive(true)
end

local SAVE = { "from", "to", "fromID", "toID", "cont", "key", "est", "unknown" }

function M:Land(secs)
	local f = flight
	flight = nil
	local mdb = ns:ModuleDB("flight")
	mdb.current = nil
	-- only a flight seen from take-off to landing is learned (a resumed one may hide a disconnect)
	if f.key and not f.resumed and not f.unknown then
		local all = routes()
		local r = all[f.key] or { n = 0 }
		if M.Learn(r, secs) then
			r.from, r.to, r.fromID, r.toID, r.cont = f.from, f.to, f.fromID, f.toID, f.cont
			r.est = f.est
			r.real = floor(secs + 0.5)                       -- the last real time
			r.off = f.est and (r.real - f.est) or nil         -- and how far the estimate was off
			r.last = time()
			all[f.key] = r
		end -- an outlier on a known route stays noted in r.alt
	end
	if mdb.arrival then
		local where = f.to and M.Short(f.to) or ns.Str(GetSubZoneText and GetSubZoneText()) or ns.Str(GetZoneText and GetZoneText())
		if where and where ~= "" then
			ns:Print(string.format("Landed in %s after %s", where, M.Format(secs)))
		else
			ns:Print("Landed after " .. M.Format(secs))
		end
	end
end

function M:Render(now)
	if not flight then
		if shownKey ~= false then
			shownKey = false
			obj.text = ""
			ns.API.SetHidden(self.ldbName, true)
		end
		return
	end
	local elapsed = (now or GetTime()) - flight.start
	local key = floor(elapsed)
	if key == shownKey then return end
	if shownKey == false or shownKey == nil then ns.API.SetHidden(self.ldbName, false) end
	shownKey = key
	obj.text = M.Text(flight, elapsed)
end

-- Poll: did the flight start, or end?
function M:Check()
	local now = GetTime()
	local air = onTaxi()
	if air and not flight then
		if pending and now - pending.at <= M.PENDING then flight = pending else flight = { unknown = true } end
		pending = nil
		flight.start = now
		local c = { startedAt = time() }
		for _, k in ipairs(SAVE) do c[k] = flight[k] end
		ns:ModuleDB("flight").current = c
	elseif not air and flight then
		self:Land(now - flight.start)
	elseif pending and now - pending.at > M.PENDING then
		pending = nil -- picked but never took off (no money, closed the map...)
	end
	self.task:SetActive(flight ~= nil or pending ~= nil)
	self:Render(now)
end

-- After a /reload in the air: pick the flight up again from its saved start and destination. Else forget it.
function M:Resume()
	local mdb = ns:ModuleDB("flight")
	local c = mdb.current
	if flight or type(c) ~= "table" then return end
	local ago = time() - (tonumber(c.startedAt) or -1e9)
	if not onTaxi() or ago < 0 or ago > M.MAX then mdb.current = nil return end
	flight = {}
	for _, k in ipairs(SAVE) do flight[k] = c[k] end
	flight.start, flight.resumed = GetTime() - ago, true
end

function M.Tooltip(tip)
	ns.TipHeader(tip, "Flight")
	local W, V = 0.9, 1
	if flight then
		local el = GetTime() - flight.start
		if flight.unknown then
			tip:AddDoubleLine("Flying for", M.Format(el), W, W, W, V, V, V)
			ns.TipHint(tip, "This flight didn't start from the flight map, so its destination isn't known.")
		else
			tip:AddDoubleLine("From", flight.from or "?", W, W, W, V, V, V)
			tip:AddDoubleLine("To", flight.to or "?", W, W, W, V, V, V)
			local exp, kind, n = M.Expected(flight)
			if exp then
				tip:AddDoubleLine("Expected", M.Format(exp) .. (kind == "yours" and ("  (your flights: " .. n .. ")") or "  (estimate)"), W, W, W, V, V, V)
				tip:AddDoubleLine("Time left", M.Format(exp - el), W, W, W, V, V, V)
				if kind == "yours" and flight.est then tip:AddDoubleLine("Estimate", "~" .. M.Format(flight.est), W, W, W, 0.6, 0.6, 0.6) end
			else
				tip:AddDoubleLine("Expected", "first time: learning it", W, W, W, 0.6, 0.6, 0.6)
			end
			tip:AddDoubleLine("Flying for", M.Format(el), W, W, W, V, V, V)
			local r = flight.key and routes()[flight.key]
			local times = r and tonumber(r.n) or 0
			tip:AddDoubleLine("Flown before", times == 0 and "not yet" or times == 1 and "once" or (times .. " times"), W, W, W, V, V, V)
		end
	else
		ns.TipHint(tip, "Not on a flight. Take a flight path and the time left shows here.")
	end
	local list, total = M.Recent(M.RECENT)
	if total > 0 then
		tip:AddLine(" ")
		tip:AddLine("Your routes (" .. total .. ")", 1, 0.82, 0.29)
		for _, r in ipairs(list) do
			tip:AddDoubleLine(M.Short(r.from) .. " » " .. M.Short(r.to), M.Format(r.avg) .. "  (" .. r.n .. "x)", W, W, W, V, V, V)
		end
	end
	tip:AddLine(" ")
	ns.TipHint(tip, "Times come from your own flights. Until you've flown a route, it counts down from an estimate (~).")
end

function M:Enable()
	obj = ns.Plugin(self, {
		type = "data source", label = "Flight", text = "", icon = "Interface\\Icons\\Ability_Mount_Gryphon_01",
		OnTooltipShow = function(tip) M.Tooltip(tip) end,
	})
	local mdb = ns:ModuleDB("flight")
	if type(mdb.routes) ~= "table" then mdb.routes = {} end
	if not M.hooked and type(TakeTaxiNode) == "function" and hooksecurefunc then
		M.hooked = pcall(hooksecurefunc, "TakeTaxiNode", function(slot) ns.SafeCall(M, M.OnTakeTaxi, slot) end)
	end
	self.task = self.task or ns.Every(self, 0.25, function() M:Check() end, false)
	local function check() M:Check() end
	ns.On("PLAYER_CONTROL_LOST", self, check)
	ns.On("PLAYER_CONTROL_GAINED", self, check)
	ns.On("PLAYER_ENTERING_WORLD", self, function() M:Resume(); M:Check() end)
	shownKey = nil
	-- before the world is in (a /reload), PLAYER_ENTERING_WORLD resumes the flight; checking now would start over
	if IsLoggedIn and IsLoggedIn() then self:Resume(); self:Check() else self:Render() end
end

function M:Disable()
	flight, pending = nil, nil
	if self.task then self.task:SetActive(false) end
	shownKey = nil
	ns.API.SetHidden(self.ldbName, true)
end

-- tests: drop the in-memory flight
function M.Reset() flight, pending, shownKey = nil, nil, nil end
