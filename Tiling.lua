-- EverlookDB Bar: the window-tiling maths of the taskbar. Pure functions, no game API, so the tests check them
-- directly. Rectangles are { x, y, w, h } in UIParent units, x from the left, y from the bottom.
local _, ns = ...
local T = {}
ns.Tiling = T

local floor, max, min, ceil, sqrt = math.floor, math.max, math.min, math.ceil, math.sqrt

-- Every snap layout, in menu order, with the words the menus and chat use.
T.ZONES = {
	{ id = "max", text = "Maximize" },
	{ id = "left", text = "Left half" }, { id = "right", text = "Right half" },
	{ id = "top", text = "Top half" }, { id = "bottom", text = "Bottom half" },
	{ id = "topleft", text = "Top left quarter" }, { id = "topright", text = "Top right quarter" },
	{ id = "bottomleft", text = "Bottom left quarter" }, { id = "bottomright", text = "Bottom right quarter" },
	{ id = "left3", text = "Left third" }, { id = "center3", text = "Middle third" }, { id = "right3", text = "Right third" },
	{ id = "left23", text = "Left two thirds" }, { id = "right23", text = "Right two thirds" },
}
T.ZONE = {}
for _, z in ipairs(T.ZONES) do T.ZONE[z.id] = z end

-- The screen minus every bar docked to an edge (shown bars only; free bars float over windows).
function T.WorkArea(bars, W, H)
	local L = ns.Layout
	local stack = { top = 0, bottom = 0, left = 0, right = 0 }
	for _, bar in ipairs(bars or {}) do
		local e = bar.edge
		if bar.shown ~= false and stack[e] then
			local thick = L.Size(bar, W, H)
			stack[e] = stack[e] + thick
		end
	end
	local x, y = stack.left, stack.bottom
	return { x = x, y = y, w = max(1, W - stack.left - stack.right), h = max(1, H - stack.top - stack.bottom) }
end

-- The rectangle of a snap layout inside `area`, with `gap` pixels around and between windows.
-- Fractions: { left, bottom, width, height } of the area.
local FRACTIONS = {
	max = { 0, 0, 1, 1 },
	left = { 0, 0, 0.5, 1 }, right = { 0.5, 0, 0.5, 1 },
	top = { 0, 0.5, 1, 0.5 }, bottom = { 0, 0, 1, 0.5 },
	topleft = { 0, 0.5, 0.5, 0.5 }, topright = { 0.5, 0.5, 0.5, 0.5 },
	bottomleft = { 0, 0, 0.5, 0.5 }, bottomright = { 0.5, 0, 0.5, 0.5 },
	left3 = { 0, 0, 1 / 3, 1 }, center3 = { 1 / 3, 0, 1 / 3, 1 }, right3 = { 2 / 3, 0, 1 / 3, 1 },
	left23 = { 0, 0, 2 / 3, 1 }, right23 = { 1 / 3, 0, 2 / 3, 1 },
}

-- A cell [fx, fx + fw] of the area, with a gap at the area's edges and half a gap where two cells meet, so every
-- window has the same gap all round and neighbours sit exactly `gap` apart.
local function cell(area, fx, fy, fw, fh, gap)
	local g = gap or 0
	local x0, x1 = area.x + area.w * fx, area.x + area.w * (fx + fw)
	local y0, y1 = area.y + area.h * fy, area.y + area.h * (fy + fh)
	local eps = 0.001
	local l = fx <= eps and g or g / 2
	local r = fx + fw >= 1 - eps and g or g / 2
	local b = fy <= eps and g or g / 2
	local t = fy + fh >= 1 - eps and g or g / 2
	return { x = floor(x0 + l + 0.5), y = floor(y0 + b + 0.5), w = floor(x1 - x0 - l - r + 0.5), h = floor(y1 - y0 - b - t + 0.5) }
end

function T.SnapRect(zone, area, gap)
	local f = FRACTIONS[zone]
	if not f or not area then return nil end
	return cell(area, f[1], f[2], f[3], f[4], gap)
end

-- "Tile all": n windows in a coherent grid. Columns follow the area's shape (a wide screen gets more columns than
-- rows); a short last row stretches its windows across the whole width, so there are no holes. Returns rects in
-- order, filling rows from the top left.
function T.Grid(n, aspect)
	if n <= 0 then return 0, 0 end
	aspect = aspect and aspect > 0 and aspect or 16 / 9
	local cols = max(1, min(n, floor(sqrt(n * aspect) + 0.5)))
	local rows = ceil(n / cols)
	-- fewest empty cells: drop a column while the rows still hold them all
	while cols > 1 and (cols - 1) * rows >= n do cols = cols - 1 end
	return cols, rows
end

function T.TileRects(n, area, gap)
	local out = {}
	if n <= 0 or not area then return out end
	local cols, rows = T.Grid(n, area.w / max(1, area.h))
	local i = 0
	for r = 1, rows do
		local left = n - i
		local inRow = r < rows and cols or left
		for c = 1, inRow do
			i = i + 1
			-- row 1 is the top row
			out[i] = cell(area, (c - 1) / inRow, (rows - r) / rows, 1 / inRow, 1 / rows, gap)
		end
	end
	return out
end

-- Where a window dragged with the cursor at (cx, cy) snaps, like Windows: the top edge maximizes, the left and right
-- edges take a half, the corners a quarter. margin: how close to the screen's edge counts; corner: how far along an
-- edge from a corner still counts as that corner. nil: no snap.
function T.DragZone(cx, cy, W, H, margin, corner)
	margin, corner = margin or 6, corner or 60
	if not cx or not cy then return nil end
	local atL, atR = cx <= margin, cx >= W - margin
	local atT, atB = cy >= H - margin, cy <= margin
	local nearT, nearB = cy >= H - corner, cy <= corner
	local nearL, nearR = cx <= corner, cx >= W - corner
	if (atL and nearT) or (atT and nearL) then return "topleft" end
	if (atR and nearT) or (atT and nearR) then return "topright" end
	if (atL and nearB) or (atB and nearL) then return "bottomleft" end
	if (atR and nearB) or (atB and nearR) then return "bottomright" end
	if atT then return "max" end
	if atL then return "left" end
	if atR then return "right" end
	return nil
end

-- The rectangle a window really takes in `rect`: a window that can't be resized keeps its size (but never more than
-- the screen) and is centred in the rect; a resizable one fills it, within its own size limits. W, H: the screen.
-- win: { w, h, resizable, minW, minH, maxW, maxH }.
function T.Fit(rect, win, W, H)
	local w, h
	if win.resizable then
		w = max(win.minW or 0, rect.w)
		h = max(win.minH or 0, rect.h)
		if win.maxW and win.maxW > 0 then w = min(w, win.maxW) end
		if win.maxH and win.maxH > 0 then h = min(h, win.maxH) end
	else
		w, h = win.w or rect.w, win.h or rect.h
	end
	w, h = min(w, W or w), min(h, H or h)
	-- centred across, top aligned (like a window that fills the cell)
	local x, y = rect.x + (rect.w - w) / 2, rect.y + rect.h - h
	if W then x = max(0, min(W - w, x)) end
	if H then y = max(0, min(H - h, y)) end
	return { x = floor(x + 0.5), y = floor(y + 0.5), w = floor(w + 0.5), h = floor(h + 0.5) }
end

-- The taskbar's window buttons. length: the room along the bar; n: buttons; vertical: a side bar (buttons stack, each
-- `itemH` high); maxW/minW: a horizontal button's width range. Returns size (each button's length along the bar),
-- shown (how many fit; the rest go into a "more" button) and more (true when a "more" button is needed, which takes
-- one more slot of `moreW`).
function T.Strip(n, length, opts)
	opts = opts or {}
	local gap = opts.gap or 2
	if n <= 0 or length <= 0 then return 0, 0, false end
	if opts.vertical then
		local size = opts.itemH or 24
		local fit = floor((length + gap) / (size + gap))
		if fit >= n then return size, n, false end
		return size, max(0, fit - 1), true
	end
	local maxW, minW = opts.maxW or 170, opts.minW or 40
	local size = floor((length - gap * (n - 1)) / n)
	if size >= minW then return min(maxW, size), n, false end
	local moreW = opts.moreW or 32
	local fit = floor((length - moreW + gap) / (minW + gap))
	return minW, max(0, min(n, fit)), true
end

------------------------------------------------------------------------
-- A queue of actions that wait for combat to end: one entry per key (the newest wins and moves to the end), run in
-- order. Pure: the caller runs it on PLAYER_REGEN_ENABLED.
------------------------------------------------------------------------
local Queue = {}
Queue.__index = Queue
function T.NewQueue() return setmetatable({ keys = {}, fns = {} }, Queue) end
function Queue:Add(key, fn)
	if self.fns[key] then
		for i, k in ipairs(self.keys) do if k == key then table.remove(self.keys, i) break end end
	end
	self.keys[#self.keys + 1] = key
	self.fns[key] = fn
end
function Queue:Count() return #self.keys end
function Queue:Has(key) return self.fns[key] ~= nil end
function Queue:Drop(key)
	if not self.fns[key] then return end
	self.fns[key] = nil
	for i, k in ipairs(self.keys) do if k == key then table.remove(self.keys, i) break end end
end
-- Runs every queued fn through call(fn, key) (default: fn()); a run that queues again goes to the next round.
function Queue:Run(call)
	local keys, fns = self.keys, self.fns
	self.keys, self.fns = {}, {}
	for _, k in ipairs(keys) do
		local fn = fns[k]
		if fn then if call then call(fn, k) else fn() end end
	end
	return #keys
end
