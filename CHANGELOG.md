# Changelog

## Unreleased

- Right-click the bar to open its settings: anywhere between plugins, or on a plugin that has no clicks of its own.
- Chat commands now follow one pattern across all EverlookDB addons: `/ebar help` (or `?`) lists them; `get` and `set <setting> <value>`; `search <words>`; `status` and `version`; `/ebar reset bars`, `reset all` and `minimap reset` ask first (type it again within 10 seconds; `reset all confirm` still works); a mistyped command suggests the nearest one. `/everlookbar` also works.
- Plugins page in `/ebar`: drag and drop. Drag a plugin's row (a grip on its left) to reorder it in its group, move
  it to another group or another bar, or drop it in "Not on a bar" to take it off; drag from there onto a bar to add
  it at that spot. A ghost of the row follows the cursor, a thin blue line shows where it lands, the group lights up
  and the page scrolls near its edges; right-click or Escape cancels. The bar changes at once, in combat too. With
  more than one bar, each bar's groups show under its name. The < and > buttons still move one step.
- "Build your own" page in `/ebar`: build your own plugin for Everlook Bar. Its button shows the address of the full
  guide on EverlookDB (everlookdb.com/ebar/plugins) to copy, and a line to paste into an AI assistant so it writes the
  plugin with you. The settings search finds it ("plugin", "module", "develop", "API", "guide").
- Minimap: "Unlock minimap" is the first setting on its page (or `/ebar minimap unlock`): drag the minimap itself with
  the left mouse button, mouse wheel to resize, right-click or Lock to lock; snaps to screen edges, `/ebar minimap
  reset` puts it back. Fixed the round shape showing black, the drawer showing empty grey circles instead of the
  addon icons (and opening away from the minimap), Blizzard's coordinates under the minimap staying visible, and a
  Lua error from Blizzard's mail icon (UPDATE_PENDING_MAIL) after hiding it. New: border thickness, a zone line
  showing the subzone, and `/ebar minimap scan` naming any other text around the minimap.
- First version. Info bars for LibDataBroker plugins: any number of bars on any edge or anywhere, one or more rows,
  your own length, colour, opacity, font and spacing; plugins in left, centre and right groups, placed from the
  settings window or by dragging in unlock mode.
- Built-in plugins: XP bar, Performance, Location, Durability, Mail, Bags, Gold, Calendar (with invite answers) and a
  Clock (off by default).
- Clean minimap: move, size, square or round, thin border; hide or move the zone text, day/night indicator, clock,
  coordinates and the tracking, calendar and mail pieces; addon minimap buttons in one drawer or hidden. Steps aside
  when another minimap addon manages the minimap.
- `/ebar` opens the settings window; every setting also works from chat. `/ebar unlock` to move things, `/ebar perf`
  for Everlook Bar's own memory and CPU.
- `EverlookBar.API` (version 1) for plugin authors: custom widgets, settings, the shared ticker, placement. See API.md.
