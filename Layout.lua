-- EverlookDB Bar: layout maths. Pure functions, no game API, so the tests can check them directly.
-- Screen coordinates: x from the left, y from the bottom, in UIParent units. Positions inside a bar: x from its left,
-- y downwards from its top (0, 1, 2...), the way the bar code anchors buttons with TOPLEFT.
local _, ns = ...
local L = {}
ns.Layout = L

local floor, max, min = math.floor, math.max, math.min

local function vertical(bar)
	if bar.edge == "left" or bar.edge == "right" then return true end
	if bar.edge == "free" then return bar.orient == "vertical" end
	return false
end
L.IsVertical = vertical

-- A bar's thickness across its edge and its length along it.
function L.Size(bar, W, H)
	local lanes = max(1, floor(tonumber(bar.lanes) or 1))
	local thick = lanes * max(8, tonumber(bar.laneSize) or 22)
	local full = vertical(bar) and H or W
	local len = tonumber(bar.length) or 0
	if len <= 0 then
		len = bar.edge == "free" and min(400, full) or full
	end
	len = min(len, full)
	return thick, len
end

local function along(bar, full, len)
	local pos
	if bar.align == "start" then pos = 0
	elseif bar.align == "end" then pos = full - len
	else pos = (full - len) / 2 end
	pos = pos + (tonumber(bar.offset) or 0)
	return max(0, min(full - len, pos))
end

-- Rectangles for all bars: rects[i] = { x, y, w, h, vertical }. Bars on the same edge stack outwards to inwards in
-- list order, the taskbar (kind "taskbar") outermost of all; hidden bars take no room.
function L.BarRects(bars, W, H)
	local rects, stack = {}, { top = 0, bottom = 0, left = 0, right = 0 }
	local order = {}
	for i, bar in ipairs(bars) do if bar.kind == "taskbar" then order[#order + 1] = i end end
	for i, bar in ipairs(bars) do if bar.kind ~= "taskbar" then order[#order + 1] = i end end
	for _, i in ipairs(order) do
		local bar = bars[i]
		local thick, len = L.Size(bar, W, H)
		local v = vertical(bar)
		local r = { vertical = v }
		local e = bar.edge
		if e == "top" or e == "bottom" then
			r.w, r.h = len, thick
			r.x = along(bar, W, len)
			if e == "top" then r.y = H - stack.top - thick else r.y = stack.bottom end
		elseif e == "left" or e == "right" then
			r.w, r.h = thick, len
			-- "start" is the top of the screen for a side bar
			r.y = H - len - along(bar, H, len)
			if e == "left" then r.x = stack.left else r.x = W - stack.right - thick end
		else
			if v then r.w, r.h = thick, len else r.w, r.h = len, thick end
			r.x = max(0, min(W - r.w, tonumber(bar.x) or 0))
			r.y = max(0, min(H - r.h, tonumber(bar.y) or 0))
		end
		if bar.shown ~= false and stack[e] then stack[e] = stack[e] + thick end
		rects[i] = r
	end
	return rects
end

local GROUP_ORDER = { left = 1, center = 2, right = 3 }
L.GROUPS = { "left", "center", "right" }

local function byOrder(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return (a.key or "") < (b.key or "")
end

-- The taskbar's strip (the Start button and the window buttons): first in the left group of row 1, as long as the
-- room left before the first centre or right plugin of that row (and after its other left plugins) allows.
-- Returns the strip's length along the bar (0 or more).
function L.TaskStripLength(bar, barW, barH, items, itemH)
	local v = vertical(bar)
	local spacing = max(0, tonumber(bar.spacing) or 0)
	local pad = max(0, tonumber(bar.padding) or 0)
	local length = v and barH or barW
	local pos = L.PlaceItems(bar, barW, barH, items, itemH)
	local stop, leftEnd = length - pad, nil
	for _, it in ipairs(items) do
		if max(1, floor(tonumber(it.lane) or 1)) == 1 then
			local p = pos[it]
			local a, e = v and p.y or p.x, v and (p.y + p.h) or (p.x + p.w)
			if it.group == "center" or it.group == "right" then
				stop = min(stop, a - spacing)
			else
				leftEnd = max(leftEnd or 0, e)
			end
		end
	end
	local used = leftEnd and (leftEnd - pad + spacing) or 0
	return max(0, floor(stop - pad - used))
end

-- Positions of the plugins on one bar.
-- items: { { key, w, lane, group, order } } (w = width the plugin wants); itemH: a plugin's height in side bars.
-- Returns pos[item] = { x, y, w, h } (y downwards from the bar's top). Every group of a lane keeps the visual
-- left-to-right (or top-to-bottom) order of `order`; the right group ends at the bar's far end.
function L.PlaceItems(bar, barW, barH, items, itemH)
	local v = vertical(bar)
	local lanes = max(1, floor(tonumber(bar.lanes) or 1))
	local laneSize = max(8, tonumber(bar.laneSize) or 22)
	local spacing = max(0, tonumber(bar.spacing) or 0)
	local pad = max(0, tonumber(bar.padding) or 0)
	itemH = itemH or laneSize
	local groups = {}
	for _, it in ipairs(items) do
		local lane = max(1, min(lanes, floor(tonumber(it.lane) or 1)))
		local g = GROUP_ORDER[it.group] and it.group or "left"
		local k = lane .. g
		groups[k] = groups[k] or {}
		table.insert(groups[k], it)
	end
	local pos = {}
	local length = v and barH or barW
	for lane = 1, lanes do
		for _, g in ipairs(L.GROUPS) do
			local list = groups[lane .. g]
			if list then
				table.sort(list, byOrder)
				-- size of each item along the bar
				local total = 0
				for i, it in ipairs(list) do
					local s = tonumber(it.len) or (v and itemH or max(0, tonumber(it.w) or 0))
					it._s = s
					total = total + s + (i > 1 and spacing or 0)
				end
				local start
				if g == "left" then start = pad
				elseif g == "right" then start = length - pad - total
				else start = floor((length - total) / 2 + 0.5) end
				local cursor = start
				for _, it in ipairs(list) do
					local p
					if v then
						p = { x = (lane - 1) * laneSize, y = cursor, w = laneSize, h = it._s }
					else
						p = { x = cursor, y = (lane - 1) * laneSize, w = it._s, h = laneSize }
					end
					pos[it] = p
					cursor = cursor + it._s + spacing
					it._s = nil
				end
			end
		end
	end
	return pos
end

-- Where a plugin dropped at (cx, cy) inside a bar goes. cx, cy: from the bar's top-left, y downwards.
-- placed: { { key, x, y, w, h, lane, group } } (the plugins already there, minus the dragged one).
-- Returns lane, group, index (1-based position inside that group).
function L.DropTarget(bar, barW, barH, cx, cy, placed)
	local v = vertical(bar)
	local lanes = max(1, floor(tonumber(bar.lanes) or 1))
	local laneSize = max(8, tonumber(bar.laneSize) or 22)
	local across, alongPos, length = v and cx or cy, v and cy or cx, v and barH or barW
	local lane = max(1, min(lanes, floor(across / laneSize) + 1))
	local third = length / 3
	local group = alongPos < third and "left" or (alongPos < 2 * third and "center" or "right")
	local index = 1
	for _, p in ipairs(placed or {}) do
		if p.lane == lane and p.group == group then
			local centre = v and (p.y + p.h / 2) or (p.x + p.w / 2)
			if centre < alongPos then index = index + 1 end
		end
	end
	return lane, group, index
end

-- Width that does not wobble: grow at once, shrink only when it would save more than `slack` pixels.
function L.StickyWidth(old, new, slack)
	if not old or new >= old then return new end
	if old - new > (slack or 8) then return new end
	return old
end

function L.Snap(v, grid)
	grid = tonumber(grid) or 0
	if grid <= 1 then return floor(v + 0.5) end
	return floor(v / grid + 0.5) * grid
end

-- After dragging a bar to (x, y, w, h): the edge it belongs to (within `margin` of one), or "free".
function L.EdgeForDrop(x, y, w, h, W, H, margin)
	margin = margin or 24
	local best, dist = "free", margin + 1
	local d = { top = H - (y + h), bottom = y, left = x, right = W - (x + w) }
	for _, e in ipairs({ "top", "bottom", "left", "right" }) do
		if d[e] <= margin and d[e] < dist then best, dist = e, d[e] end
	end
	return best
end

-- Renumber a group's orders 1..n after a move (items sorted by order); `insert` at index for `key`.
function L.Reorder(list, key, index)
	local out = {}
	for _, k in ipairs(list) do if k ~= key then out[#out + 1] = k end end
	index = max(1, min(#out + 1, index or #out + 1))
	table.insert(out, index, key)
	return out
end

------------------------------------------------------------------------
-- Settings window lists (the Plugins page): where a dragged row lands. Positions run downwards from a list's top.
------------------------------------------------------------------------
-- The insertion slot for `pos` among rows whose centres are `centres` (top-down): 1 = above the first row,
-- #centres + 1 = under the last.
function L.InsertSlot(centres, pos)
	local slot = 1
	for _, c in ipairs(centres) do
		if c < pos then slot = slot + 1 end
	end
	return slot
end

-- Row centres of a list with rows `rowH` high and `gap` apart.
function L.RowCentres(n, rowH, gap)
	local t = {}
	for i = 1, n do t[i] = (i - 1) * (rowH + gap) + rowH / 2 end
	return t
end

-- A group's list shows its rows lane by lane: lanes[i] is the lane (bar row) of the i-th row shown.
-- Dropping at `slot` (see InsertSlot; counted with the dragged row still shown at `skip`, nil when it comes from
-- elsewhere) puts it in the lane of the row above the line (else the row below, else `fallback`) at `index` inside
-- that lane, ready for Host:Place. Returns lane, index.
function L.ListDrop(lanes, slot, skip, fallback)
	local rest = {}
	for i, lane in ipairs(lanes) do
		if i ~= skip then rest[#rest + 1] = lane end
	end
	if skip and slot > skip then slot = slot - 1 end
	slot = max(1, min(#rest + 1, slot))
	local lane = rest[slot - 1] or rest[slot] or fallback or 1
	local index = 1
	for i = 1, slot - 1 do
		if rest[i] == lane then index = index + 1 end
	end
	return lane, index
end

-- Which of `zones` ({ top, bottom }, positions downwards) is at `pos`: the one it is in, else the nearest.
function L.NearestZone(zones, pos)
	local best, dist
	for i, z in ipairs(zones) do
		local d = 0
		if pos < z.top then d = z.top - pos elseif pos > z.bottom then d = pos - z.bottom end
		if not dist or d < dist then best, dist = i, d end
	end
	return best
end
