# Everlook Bar

Info bars and a clean minimap for WoW Forever (1.60.1, interface 16001).

![Everlook Bar](screenshots/bar.png)
*(screenshot to come)*

## What it does

**Bars.** As many as you like: along the top, bottom, left or right edge, or anywhere. One row or two (or more),
the whole edge or a set length, any background colour and opacity (black at 60% by default), font, size and
spacing. Side bars stack their plugins. Plugins sit in left, centre and right groups.

**Plugins.** Every LibDataBroker plugin from any addon can go on a bar, the same plugins Titan Panel, ChocolateBar and
ElvUI show. Built in (each one switchable, each one a normal LDB plugin):

- **XP bar**: a thin bar with rested XP and the percentage. Hidden at max level.
- **Performance**: FPS and latency; memory, CPU per addon and bandwidth in the tooltip.
- **Location**: zone, subzone (Tarren Mill, Southshore Inn) and coordinates. Click to open the map.
- **Durability**: your most worn item in percent; every slot in the tooltip.
- **Mail**: new mail or not, with the senders.
- **Bags**: free and total slots; profession bags apart.
- **Gold**: with this session's change in the tooltip.
- **Calendar**: the date or today's next event, pending invites, the coming week in the tooltip; answer invites with
  a right-click.
- **Clock**: off by default.

**Clean minimap.** Unlock it and drag the minimap itself with the left mouse button (mouse wheel to resize,
right-click to lock); it snaps to screen edges and remembers where you put it. Square or round, a border of your
thickness and colour, an optional zone line showing where you stand. Hide or move the zone text, the day/night
indicator, the clock, Blizzard's coordinates and the tracking, calendar and mail pieces. Every addon's minimap button
goes into one small drawer beside the minimap, with its own icon, tooltip and click, or is hidden. If another addon
already manages the minimap (BasicMinimap, SexyMap...), Everlook Bar leaves the minimap frame alone and says so once in
chat.

## Using it

- `/ebar` opens the settings window. Everything in it also works from chat (see Commands below).
- On the Plugins page of `/ebar`, drag a plugin's row to reorder it, move it to another group or bar, or drop it in
  "Not on a bar" to take it off; drag from there onto a bar to add it. Right-click or Escape cancels a drag.
- `/ebar unlock` (or the Unlock button): drag bars to any edge or anywhere, the minimap where you like, and plugins
  between bars and groups. A grid helps you line things up. Escape locks again.
- `/ebar minimap unlock`, `lock`, `reset`: move the minimap on its own, or put it back in the top-right corner.
  `/ebar minimap scan` lists what the minimap module found and any other text shown around the minimap.
- `/ebar perf` shows what Everlook Bar itself costs.

## Commands

`/ebar` (also `/everlookbar`) follows the same pattern as every EverlookDB addon:

- `/ebar` opens the settings window; it's also under Settings > AddOns.
- `/ebar bar.edge left` (or `/ebar set bar.edge left`): change a setting; `/ebar bar2.edge left` changes bar 2. `/ebar get` lists every setting, `/ebar get bar.edge` shows one.
- `/ebar unlock`, `/ebar lock` (or `move`, which flips it): drag bars, the minimap and plugins.
- `/ebar bar`, `bar 2`, `bar add left`, `bar delete 2`; `/ebar plugins`, `place gold 1 right`, `remove gold`.
- `/ebar minimap unlock`, `lock`, `reset`, `scan`, `grab <frame>`, `ignore <frame>`.
- `/ebar reset bars`, `/ebar reset all`, `/ebar minimap reset` ask first (type it again within 10 seconds); `/ebar reset all confirm` still works.
- `/ebar search <words>` opens the window with its search box filled; `/ebar status` (bars, plugins, memory), `/ebar version`, `/ebar perf`.
- `/ebar help` (or `?`) lists every command; a mistyped one suggests the nearest.

## Built to stay out of the way

- One shared ticker for everything, with its own interval per plugin. Most plugins only update on game events;
  Location reads your position only while you move.
- Text is set only when it changed; widths don't wobble when a number ticks.
- Every plugin runs protected: a broken one gets a small red marker, the bar keeps going.
- Secret values (WoW Forever's combat rules) are shown, never read.
- Nothing protected is touched in combat; minimap changes wait until combat ends.
- Windows close with Escape through their own key handler, never through Blizzard's panel lists, so NoAutoClose and
  BlizzMove keep working.

## For plugin authors

See [API.md](API.md): any LibDataBroker plugin works as is; `EverlookBar.API` adds custom widgets, settings and the
shared ticker. The full guide, with a working plugin in 15 lines and a brief to paste into an AI assistant:
https://everlookdb.com/ebar/plugins (also on the "Build your own" page of `/ebar`).

## Renaming

The name lives in one place: the top of `Core.lua` (`ns.NAME`, `ns.SLASH`, `ns.GLOBAL`, `ns.PREFIX`, `ns.SAVED`),
plus the `.toc` (Title, SavedVariables, and the file name if the folder changes).

## Tests

`python -P tests/run.py` runs the offline tests in Lua 5.1 (lupa) against a small fake of the game.

## Credits and license

Everlook Bar is licensed under the GNU General Public License version 3 (GPL-3.0); the full text is in `LICENSE`.
Every line of Everlook Bar is its own; it contains no code from Titan Panel, TomTom, ElvUI or any minimap addon.

Bundled libraries, each under its own terms:

- LibStub: public domain (see its header).
- CallbackHandler-1.0: by the Ace3 Development Team, BSD-style licence in `Libs/CallbackHandler-1.0/LICENSE.txt`.
- EverlookUI: the shared settings window of these addons.
- `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` is Everlook Bar's own implementation of the public LibDataBroker 1.1
  interface (GPL-3.0). The widely shared file carries no licence, so it is not bundled; this one is compatible with it
  and with every LDB plugin.
