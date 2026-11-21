# Changelog

## Unreleased
- The pieces around the minimap are reworked. Each one (zone name, tracking button, mail icon, calendar button, day and night dial, clock, coordinates, zoom buttons, addon menu button) now has a plain on/off switch with a small picture and a Reset button, in one short list on the Minimap page. Switching one works at once, also in combat; if the game locks a piece in combat, it changes when combat ends and the page says so.
- A piece that is on now sits on the minimap's edge, above the map, and moves and grows with the minimap. Before, "Show" left it in the top-right corner of the screen (under a top bar, and far from a minimap you had moved), and "Move" put it in the middle of the map, partly underneath it.
- Moving is one button: **Unlock to move**, on the Minimap page and at the bottom left of the settings window (`/ebar unlock` still works). It covers bars, plugins, the minimap and its pieces together. Every piece gets a box with its name; drag it along the minimap's edge. It snaps to the corners and the middle of the sides on a square minimap and every 45 degrees on a round one; hold Shift to put it anywhere; right-click a box to put that piece back. Before, the page's "Unlock minimap" switch only unlocked the minimap itself, so the pieces could not be moved from there.
- While you are moving things, a small control in the middle of the minimap has Done and Reset positions and shows the minimap's size (mouse wheel over the map). The old banner at the top of the screen, which sat under a top bar, is gone. Escape ends it too. If another addon manages the minimap, the control is in the middle of the screen instead.
- Round and square: a piece's place is saved as a spot on the edge, so when you change the shape, the size or the border, the pieces stay on the edge instead of floating or ending up inside the map.
- New players get a square minimap. If you already use EverlookDB Bar, your shape stays as it is.
- The minimap keeps clear of your bars when you drop it, resize it or switch a piece on next to a bar, so neither the map nor its pieces end up under a bar.
- The calendar button now belongs to "Calendar button" (it used to follow the day/night setting), and "Day and night dial" is the small sun or moon. The zoom buttons, when on, stay visible instead of only under the mouse. Pieces this game version doesn't have (world map button, dungeon difficulty flag) are no longer listed.
- Your saved settings carry over: "Show" and "Move" become on, "Hide" becomes off, and a piece you had moved stays where you put it. From chat it is now `/ebar minimap.mail on` or `off` (`show` and `hide` still work; `move` is gone, use Unlock to move).
- New plugin: Tracking. It shows what your minimap tracks (Herbs, Mailbox) and a click opens a menu of everything you can track, find spells and townsfolk apart, each with a tick box: Mailbox, trainers, Flight Master, Find Herbs, Find Minerals and the rest. Right-click to untrack all. In combat the menu only shows; change it after combat. With the minimap's tracking button hidden, this is the way to change tracking. New characters get it on the bar; if you already had a layout, it waits on the Plugins page (put it on with `/ebar place tracking 1 right`).
- The addon is now called EverlookDB Bar (was Everlook Bar), like the rest of the EverlookDB family. Settings, commands and the folder stay the same.

## v0.2.2 (2026-11-21)
- Bags, Calendar and Clock open through the game's own buttons (the backpack button, the calendar button), like Durability, Reputation, Quest log and Location already did, so nothing of Everlook Bar rubs off on Blizzard's bag frames or calendar. A bag item clicked in combat can no longer be blocked because the bar opened your bags.
- Plugins that open a Blizzard panel now work in combat even when the mouse came onto them during the fight: when combat starts, each one gets its secure click. A plugin under the mouse when combat ends gets it at once, and the click stays right when a bar moves its plugins.
- Reputation bar: clicking it twice opens and closes the reputation panel, without moving the mouse away in between.
- Fixed a possible Lua error from the bag cooldown fix in combat (a secret cooldown value was compared). Secret cooldowns are now left alone.
- Gold: this session's change no longer counts your whole purse as a gain when the game reported 0 gold before you were in the world.
- XP bar: hides at once when you reach the top level.
- Settings window: "XP percentage in the middle of the bar", "Hide the global cooldown spin on bag items" and the Quest log settings were only in chat; they are now on the Built-in page, and the settings search finds them.
- Professions: a skill the game gives no cap shows its number alone instead of "150/0".
- A plugin from another addon whose text has line breaks stays on one line.
- The "Build your own" link window can be moved.

## v0.2.1 (2026-11-21)
- The addon has its own icon in the addon list, in the EverlookDB style (the database stack with a bar).

## v0.2.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.
- Quest log: a click opens your quest log again. When the game's own quest log button doesn't open it, the bar opens it itself.
- The bag counter also counts your reagent bag (WoW Forever's extra bag slot).

- Minimap drawer: a minimap button that its own addon is dragging (Everlook Pets, for one) is no longer pulled back into the drawer while you drag it; it returns to its place when you let go.
- Performance: addon memory is only measured while you hover the plugin, never on a timer (measuring walks every addon and can cause a small hitch). With "Show total addon memory" on, the bar shows the last reading.
- Quieter chat: "another addon is managing the minimap" (and the notes about minimap buttons and coordinates from other addons) is said once, not on every login and /reload. The minimap page and `/ebar status` still say it. "Locked for combat" is said once instead of twice, and turning the minimap off no longer prints a line.
- Professions: a left-click on a profession opens it again; right-click shows the list of all your professions. Herbalism, Skinning and others without a window still show the list.
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
