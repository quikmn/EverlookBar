# Changelog

## Unreleased

- Fixed Lua errors on your player frame ("attempt to compare a secret number value ... tainted by 'EverlookBar'") after opening the character or reputation panel from the bar. Durability, Reputation, Quest log and Location now open their panels through the game's own buttons, so nothing of Everlook Bar rubs off on Blizzard's frames. In combat, move the mouse onto the plugin before the fight starts, or open the panel with its key.
- Fixed a Lua error, "invalid key to 'next'", that could show up while plugins updated.
- Bag items no longer all spin with the global cooldown after every spell. WoW Forever reports the global cooldown for every item in your bags; Everlook Bar now clears that in Bagnon, Blizzard's bags and other bag addons, while real item cooldowns (potions, Hearthstone, trinkets) still show. Setting: Hide the global cooldown spin on bag items.

## v0.1.0 (2026-11-19)

- Professions: the bar shows only your two main professions; a click (left or right) folds out every profession, and picking one opens it. Cooking, First Aid and Fishing can still go on the bar in the settings.
- A plugin whose name and text are the same word shows it once ("ForeverAuras" instead of "ForeverAuras ForeverAuras").
- Settings: an AI help button copies a description of every setting for an AI assistant, and `/ebar apply` runs the commands it gives back.
- New plugin: Reputation bar. A thin bar like the XP bar for one faction, coloured by your standing with the game's own colours: red when hostile, orange unfriendly, yellow neutral, green friendly and up. It follows the faction you watch in the reputation panel, or pick any faction in `/ebar` (Built-in, Reputation bar) or with a right-click on the bar. Text: faction name, standing, value/max and percent, in the bar or beside it; your own width. The tooltip shows how much you need for the next standing; a click opens the reputation panel. It sits next to the XP bar and stays when the XP bar hides at max level.
- New plugin: Professions. Your skill in each profession on the bar (Mining 187, Herb 150, Cook 225) with its icon; click one to open that profession's window, right-click for a list of them all. A skill at its cap is coloured (time for the next rank at a trainer); in settings: which professions to show (primary, Cooking, First Aid, Fishing, Riding), the cap too (187/225), short or full names, icons and the cap colour. The tooltip lists every profession with its skill and cap. Herbalism, Skinning, Fishing and Riding have no window to open.
- Both new plugins are placed on your bar once when you update; take them off on the Plugins page if you don't want them.
- Calendar: players who had the old default (today's next event) now get the new one, "23:59, Wednesday, 26-nov-2026". A text you picked yourself stays.
- New plugin: Quest log. Shows how many quests you have out of how many the game lets you have (38/45), yellow when only a few slots are left and red when the log is full, so a quest giver never surprises you. Click opens the quest log; the tooltip says how much room is left and how many quests you track. In settings: show slots left instead, and when it turns yellow.
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
