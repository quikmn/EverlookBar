# Everlook Bar for plugin authors

Everlook Bar shows **LibDataBroker-1.1 (LDB)** plugins, like Titan Panel, ChocolateBar, Bazooka and ElvUI do. If your
addon already has an LDB data object, it already works on Everlook Bar: the player adds it on the Plugins page or
drags it onto a bar in unlock mode. Everlook Bar's own plugins (XP, Performance, Location...) are plain LDB objects and
use the same path you do.

For the few things LDB cannot express, there is a small public API: `EverlookBar.API`.

## 1. An LDB plugin (works everywhere)

```lua
local ldb = LibStub("LibDataBroker-1.1")
local obj = ldb:NewDataObject("MyAddon", {
	type = "data source",              -- or "launcher" (an icon you click)
	label = "My Addon",
	text = "0 kills",
	icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	OnClick = function(frame, button) MyAddon:Toggle() end,
	OnTooltipShow = function(tooltip)
		tooltip:AddLine("My Addon")
		tooltip:AddDoubleLine("Kills", MyAddon.kills)
	end,
})

-- later, whenever the value changes:
obj.text = MyAddon.kills .. " kills"
```

What Everlook Bar reads:

| Attribute | Use |
|---|---|
| `type` | `"data source"` shows text; `"launcher"` shows icon and label by default |
| `text` | the text on the bar. If missing: `value` and `suffix` |
| `label` | shown before the text when the player turns Label on (Look button) |
| `icon`, `iconCoords`, `iconR`, `iconG`, `iconB` | the icon and its tint |
| `OnClick(frame, button)` | left, right, middle clicks |
| `tooltip` | your own tooltip frame: Everlook Bar anchors and shows it |
| `OnEnter(frame)`, `OnLeave(frame)` | you show your own tooltip (e.g. LibQTip) |
| `OnTooltipShow(tooltip)` | fill the GameTooltip; Everlook Bar anchors it away from the bar's edge |

Good to know:

- Updates are cheap: Everlook Bar redraws a plugin at most once per frame however often you write `text`, and only
  sets the text when it changed. Still, write `text` when your value changes, not every frame.
- Your code runs protected. If `OnClick` or `OnTooltipShow` raises an error, only your button gets a small red
  marker and the error shows in its tooltip; the bar keeps working. Your code is not called again for that click.
- Secret values (WoW Forever / Midnight rules): you may put a secret value in `text`. Everlook Bar passes it to the
  font string as it is and never compares, measures or does maths on it (the button keeps its last width).

## 2. EverlookBar.API

Check that it is there and new enough:

```lua
local API = EverlookBar and EverlookBar.API
if API and API.GetVersion() >= 1 then
	-- use it
end
```

**Compatibility promise.** `API.GetVersion()` only grows. A published function keeps its name, its arguments and its
meaning in every later version. New features come as new functions or new optional fields. Code written against
version 1 keeps working.

Add `## OptionalDeps: EverlookBar` to your .toc so Everlook Bar loads first when both are installed.

### Version 1

#### `API.GetVersion() -> number`
The API version (currently `1`).

#### `API.RegisterWidget(ldbName, spec) -> true`
Draw something of your own inside your plugin's button: a small bar, a meter, a row of icons. Other LDB displays still
show your `text`, so keep it meaningful.

`spec` fields:

- `width`: a number, or `function(dataobj, ldbName) -> number`. `0` hides the widget.
- `create(frame, dataobj, ldbName)`: called once with an empty Frame inside the button. Make your textures here.
- `update(frame, dataobj, ldbName)`: called whenever the button redraws (your data object changed, or you called
  `API.Refresh`). Keep it cheap: set sizes and colours, make nothing new.

The widget sits after the icon; your text follows it. Its height follows the bar's thickness.

```lua
local ldb = LibStub("LibDataBroker-1.1")
local obj = ldb:NewDataObject("MyMana", { type = "data source", text = "0%" })
local pct = 0

if EverlookBar and EverlookBar.API then
	EverlookBar.API.RegisterWidget("MyMana", {
		width = 80,
		create = function(f)
			f.bg = f:CreateTexture(nil, "BACKGROUND")
			f.bg:SetAllPoints()
			f.bg:SetColorTexture(1, 1, 1, 0.1)
			f.fill = f:CreateTexture(nil, "ARTWORK")
			f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT")
			f.fill:SetColorTexture(0.2, 0.5, 1, 0.9)
		end,
		update = function(f)
			f.fill:SetWidth(math.max(0.01, 80 * pct))
		end,
	})
end

-- when the value changes: the text change redraws the widget too
pct = 0.42
obj.text = "42%"
```

#### `API.Refresh(ldbName)`
Redraw your button now, for when your widget's data changed but your data object did not.

#### `API.SetHidden(ldbName, hidden)`
Hide your button without taking it off its bar (the XP bar does this at max level). `false` shows it again.
Returns `false` if Everlook Bar does not know that plugin yet.

#### `API.Every(owner, interval, fn) -> task`
Run `fn(task, now)` every `interval` seconds on Everlook Bar's one shared ticker (0.1 s resolution) instead of an
OnUpdate script of your own. Errors are caught and shown on the button of `owner` (your LDB name). A task that fails
50 times is stopped until /reload.

```lua
local task = EverlookBar.API.Every("MyAddon", 1, function(task, now)
	obj.text = MyAddon:Count() .. " kills"
end)
task:SetActive(false)   -- pause (costs nothing while paused)
task:SetInterval(5)     -- slower
task:Cancel()           -- gone
```

#### `API.RegisterSettings(owner, title, settings) -> get, set`
Settings for your plugin: they appear in Everlook Bar's window (Built-in page, under your title) and in chat as
`/ebar <owner>.<key> <value>`. Everlook Bar saves them.

- `owner`: a short id, letters, digits and `_` (`"myaddon"`).
- `title`: what the window calls your section.
- `settings`: a list of `{ key, type, label, desc, default, onChange }`, where `type` is `"bool"`, `"number"`
  (with `min`, `max`, `step`), `"choice"` (with `choices = { { value = "a", text = "A" }, ... }`), `"color"` or
  `"string"`. `onChange(value)` runs after a change (protected like everything else).

Returns `get(key)` and `set(key, value)`.

```lua
local get = EverlookBar.API.RegisterSettings("mykills", "My Kills", {
	{ key = "showtotal", type = "bool", label = "Show the total", default = true,
		onChange = function() MyKills:Update() end },
	{ key = "decimals", type = "number", label = "Decimals", min = 0, max = 2, default = 0 },
})
if get("showtotal") then ... end
-- in chat: /ebar mykills.decimals 1
```

#### `API.Place(ldbName, bar, group, index) -> bool`
Put a plugin on a bar: `bar` 1.., `group` `"left"`, `"center"` or `"right"`, `index` the position in the group (nil:
last). Meant for a first-run default. Respect a player who already moved it:

```lua
if not EverlookBar.API.GetPlacement("MyAddon") then EverlookBar.API.Place("MyAddon", 1, "right") end
```

#### `API.GetPlacement(ldbName) -> bar, group, index, row`
Where a plugin is, or `nil` when it is on no bar.

#### `API.GetNumBars() -> number`
How many bars there are.

## 3. Rules Everlook Bar follows (and you can count on)

- One shared ticker for everything; no OnUpdate per plugin.
- No frames are made per update; buttons are reused.
- Nothing protected is touched in combat.
- Secret values are shown, never read.
