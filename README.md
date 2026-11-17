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

**Clean minimap.** Move it, size it, square or round, a thin border. Hide or move the zone text, the day/night
indicator, the clock, coordinates and the tracking, calendar and mail pieces. Every addon's minimap button goes into
one small drawer, or is hidden. If another addon already manages the minimap (BasicMinimap, SexyMap...), Everlook Bar
leaves the minimap frame alone and says so once in chat.

## Using it

- `/ebar` opens the settings window. Everything in it also works from chat: `/ebar help`, `/ebar settings`.
- `/ebar unlock` (or the Unlock button): drag bars to any edge or anywhere, the minimap where you like, and plugins
  between bars and groups. A grid helps you line things up. Escape locks again.
- `/ebar perf` shows what Everlook Bar itself costs.

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
shared ticker.

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
