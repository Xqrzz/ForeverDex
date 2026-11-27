# Contributing

## Code layout

`ForeverDex.toc` loads the files in this order. They share the private table WoW provides to the addon (`ns`). Each module registers itself in `ns` on its first lines (`ns.Catalog = Catalog`) and names, on its third line, the modules it uses from files loaded before it (`local L, Catalog = ns.L, ns.Catalog`). A module loaded after it is only reached at call time, as `ns.Share`, since it does not exist yet when the file runs.

| File | Responsibility |
| --- | --- |
| `Util.lua` | Helpers for restricted client values, protected calls, full whisper addresses and fallback frame templates. |
| `SavedData.lua` | Prepares saved tables before modules load and preserves saves from newer versions. |
| `Comm.lua` | Addon messages (`ns.Comm`): the single prefix, whispers, and the dispatch of each message to the file that handles its type (first letter). |
| `Locale.lua`, `Locales/` | Strings for each language. A missing string falls back to English. Also holds `ns.Module`: the other files register their code with it and run at `ADDON_LOADED`, once the saved language is known. |
| `Art.lua` | Client textures, atlases and sounds, with a fallback when an atlas is missing. |
| `PopupMenu.lua` | Menus opened by ForeverDex (card and banner menus, dropdowns): the game's menus with the mouse, a small menu of its own with the controller, where an addon's game menu cannot close without a blocked protected action. |
| `Settings.lua` | Settings panel and default values. |
| `Catalog.lua` | Playable combinations, card themes, search, filters and sorting. |
| `Collection.lua` | Reading the target, saved data migration, adding and replacing cards. |
| `Guilds.lua` | Guild captures (right-click on the portrait ball): reading the target's guild, the ordered list in `ForeverDexDB.guilds`, moving and removing guilds, faction colors and crests. |
| `CaptureVisuals.lua` | Capture animation and the notification rising from the bottom of the screen, for a card (capture ball) or a guild (guild ball). |
| `DuelCards.lua` | Shared card format for collection comparison and combat. |
| `DuelExchange.lua` | Comparison requests, transfer timers and version-compatible whisper messages. |
| `Duel.lua` | Comparison screen, prompts, and game entry points. |
| `DuelFight.lua`, `Combat.lua` | Combat state transitions and the interface that renders them. |
| `PresenceIcon.lua` | The glowing icon of the collectors: its layers, its looping animation groups, its arrival and departure, and the icon choices. Shared by the nameplates and the options preview. |
| `Presence.lua` | Nearby ForeverDex players: ping and answer messages (`P`, `H`), the icon hung from the nameplates the player already shows (their nameplate settings are never changed), the tooltip line and the in-game test. It keeps `Icon.look` up to date from the settings. |
| `PresenceOptions.lua` | Collectors settings page, with a live preview. |
| `Share.lua` | Announcements of captures and achievements to other players (guild, group or a custom channel), off by default: channel checks that always refuse the Blizzard channels and /1 /2, message templates with `{fields}`, cooldown, and its settings page. A message is prepared during the player's click and sent when the capture is revealed; a custom channel message leaves at once, since the game may only accept it during a click. |
| `Home.lua` | Data of the home page, without any frame: the daily challenge (drawn from the date among the missing combinations, kept until midnight), the statistics, and the version whose news the home page offers. |
| `News.lua` | Window listing the changes of the release, built on its first opening: from the banner of the home page, `/fdex news`, or the login message after an update. |
| `PortraitCapture.lua` | Capture ball (left-click: the character, right-click: its guild) and "already collected" orb, which turns into the guild ball while only the guild is left to capture, on the target frame (Blizzard, ElvUI or another interface). `UI.lua` tells it what the target is worth. |
| `UI.lua` | Adventure Guide style window: race list, card grid, detail page, tabs and capture. Also the registry of the pages that replace the journal (`ns.UI.RegisterPage`) and their side tabs (`ns.UI.AddSideTab`). |
| `HomeUI.lua` | Home page, the first one shown in each session: daily challenge, news and statistics. |
| `AchievementsUI.lua` | Achievements page. |
| `GuildsUI.lua` | Guilds page: one banner per guild in its faction color, faction filter, drag and drop to reorder. |
| `ForeverDex.lua` | Initialization once saved data is loaded, game events, slash command and minimap button. |

`Media/` holds the capture orb (`Ball.tga`, a single image so it can rotate) and the guild ball (`GuildBall.tga`), the guild banner (`Banner.tga` and `BannerTrim.tga`, white so they can be tinted, and `BannerRod.tga`: the game has no blank banner), the addon icons, and the soft halo and ring of the presence icon (`Glow.tga`, `Ring.tga`).

## Saved data

`ForeverDexDB.cards` maps each card to a stable key. A combination uses the game's numeric IDs (`race:class:sex`). A bonus uses `bonus:n` and keeps its original combination. Translated labels are never part of a key.

`ForeverDexDB.version` is the saved data format. Increase `SavedData.VERSION` and add a conversion to `migrations` in `Collection.lua` while preserving the released conversions. Test it on a copy of real saved data before releasing.

The guild identity on a card combines its name and faction. The version 2 migration uses the card’s race where possible, including the original combination of a bonus card. Cards with an unknown faction belong to the neutral identity for that name. A captured guild saved without a faction takes the faction of its member's card, or of the only one known for that name, unless a guild with that identity is already captured. The bonus achievement keeps its original goal of 39 even as the catalog grows.

`ForeverDexDB.challenge` keeps the daily challenge (`day`, `key`) until midnight, so that capturing the card does not draw another one. It is drawn again whenever it is missing or out of date.

`ForeverDexDB.view` keeps the sort, tab and filters between sessions. Its filter sets are the tables used by the window, so change them in place and never replace them.

The custom portrait is rendered from the target. Saved data keeps the character's identity and combination. Once the player is no longer targeted, the medallion shows the generic race portrait.

## Pages of the window

A page replaces the journal in the window: it covers `ns.UI.PageArea`, provides `SetShown(shown)` (show or hide its frames, refresh them when shown), and registers with `ns.UI.RegisterPage(mode, page)` and `ns.UI.AddSideTab(index, mode, label, paint)`. `ns.UI.Show(mode)` opens the window on it.

## Releases

The changelog of a release lists only what a player notices: additions, removals, important changes and bug fixes, one short line each. Small adjustments are never detailed: they share one generic last line ("Various interface improvements"). `CHANGELOG.md`, the GitHub release notes and `HOME_NEWS_LINES` in every locale carry the same entries.

Before a release, update `Home.NEWS_VERSION` in `Home.lua` and `HOME_NEWS_LINES` in every locale: they make the news window. `ForeverDexDB.seenVersion` remembers the last version the player logged in with: the login message mentions the news only once after an update.

## Comparison compatibility

Two players must be able to compare collections across versions. Keep the base `Q`, `A`, `N`, `D` and `C` message shapes in `DuelExchange.lua`. The optional tab-delimited comparison token in `Q` and `A` allows newer peers to use `T` for collection chunks and `W` for combat. The combat message then includes a round number. A peer that does not echo the token continues on the historical exchange. Clients ignore card keys outside their catalog. In 1.8.2, this includes `bonus:40` through `bonus:139`. Since bonus cards have no limit, comparisons and combats use the standard journal and the favorites, bonus ones included. Current clients add a `favorites` field to the `Q` and `A` identity. They send the standard cards, then the favorite bonus cards while the payload fits in 200 chunks of 220 characters (`DuelCards.MAX_PAYLOAD`). They keep received bonus cards only from a peer with that field, since older versions send all of theirs, and offer only standard cards for combat against such a peer, which cannot read bonus numbers past its own last slot.

All messages use the same whisper prefix and a full player address. `Presence.lua` still uses `P` and `H`, with replies applied to the matching outstanding ping.

## In-game checks

Reload the UI with `/reload`. Check opening from the minimap, searching by full name, replacing a card and adding a bonus. Changing target must bring back the generic portrait. Test on both a French and an English client to check labels, tooltips and the confirmation dialog. Check mouse and controller during and after combat, nameplates, a full collection exchange between two updated clients, and a comparison with 1.8.2.

For performance checks, compare rapid target changes, the guild board while moving focus with a controller, and the combat stage after the verdict, using the same saved collection and graphics settings. The guild-filter regression checks how often the collection is scanned offline. Use the game profiler for frame time and addon CPU.

## Static checks

`luacheck .` must report no warning. `.luacheckrc` lists every game API the addon reads and every global it writes: add a new API there when you start using it. GitHub runs the same check on each push and pull request.

Run `TZ=Europe/Paris lua5.1 tests/regressions.lua` (or use `luajit`) from the addon directory. The fixtures use simulated game APIs, two comparison peers, and the 1.8.2 message format. They cover confirmation races, interrupted reveals, announcement audiences, migrations, guild filters, clock changes, presence and combat transitions. GitHub runs the same suite and `tests/startup.lua`, which loads the manifest in order and exercises addon initialization.
