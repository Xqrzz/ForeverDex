# Contributing

## Code layout

`ForeverDex.toc` loads the files in this order. They share the private table WoW provides to the addon (`ns`). Each module registers itself in `ns` on its first lines (`ns.Catalog = Catalog`) and names, on its third line, the modules it uses from files loaded before it (`local L, Catalog = ns.L, ns.Catalog`). A module loaded after it is only reached at call time, as `ns.Share`, since it does not exist yet when the file runs.

| File | Responsibility |
| --- | --- |
| `Util.lua` | Small helpers shared by every file (`ns.Util`): reading values the client may mark as secret, protected calls, short player names, frames built on a template the client may lack. Defined before any module runs. |
| `Comm.lua` | Addon messages (`ns.Comm`): the single prefix, whispers, and the dispatch of each message to the file that handles its type (first letter). |
| `Locale.lua`, `Locales/` | Strings for each language. A missing string falls back to English. Also holds `ns.Module`: the other files register their code with it and run at `ADDON_LOADED`, once the saved language is known. |
| `Art.lua` | Client textures, atlases and sounds, with a fallback when an atlas is missing. |
| `Settings.lua` | Settings panel and default values. |
| `Catalog.lua` | Playable combinations, card themes, search, filters and sorting. |
| `Collection.lua` | Reading the target, saved data migration, adding and replacing cards. |
| `CaptureVisuals.lua` | Capture animation and the notification rising from the bottom of the screen. |
| `Duel.lua` | Comparison between two ForeverDex users: request, agreement, exchange over whispered addon messages, and the duel screen. |
| `PresenceIcon.lua` | The glowing icon of the collectors: its layers, its looping animation groups, its arrival and departure, and the icon choices. Shared by the nameplates and the options preview. |
| `Presence.lua` | Nearby ForeverDex players: ping and answer messages (`P`, `H`), the icon hung from the nameplates the player already shows (their nameplate settings are never changed), the tooltip line and the in-game test. It keeps `Icon.look` up to date from the settings. |
| `PresenceOptions.lua` | Collectors settings page, with a live preview. |
| `Share.lua` | Announcements of captures and achievements to other players (guild, group or a custom channel), off by default: channel checks that always refuse the Blizzard channels and /1 /2, message templates with `{fields}`, cooldown, and its settings page. A message is prepared during the player's click and sent when the capture is revealed; a custom channel message leaves at once, since the game may only accept it during a click. |
| `Home.lua` | Data of the home page, without any frame: the daily challenge (drawn from the date among the missing combinations, kept until midnight), the statistics, and the version whose news the home page offers. |
| `News.lua` | Window listing the changes of the release, built on its first opening: from the banner of the home page, `/fdex news`, or the login message after an update. |
| `PortraitCapture.lua` | Capture ball and "already collected" orb on the target frame (Blizzard, ElvUI or another interface). `UI.lua` tells it what the target is worth. |
| `UI.lua` | Adventure Guide style window: race list, card grid, detail page, tabs and capture. Also the registry of the pages that replace the journal (`ns.UI.RegisterPage`) and their side tabs (`ns.UI.AddSideTab`). |
| `HomeUI.lua` | Home page, the first one shown in each session: daily challenge, news and statistics. |
| `AchievementsUI.lua` | Achievements page. |
| `ForeverDex.lua` | Initialization once saved data is loaded, game events, slash command and minimap button. |

`Media/` holds the capture orb (`Ball.tga`, a single image so it can rotate), the addon icons, and the soft halo and ring of the presence icon (`Glow.tga`, `Ring.tga`).

## Saved data

`ForeverDexDB.cards` maps each card to a stable key. A combination uses the game's numeric IDs (`race:class:sex`). A bonus uses `bonus:n` and keeps its original combination. Translated labels are never part of a key.

`ForeverDexDB.version` is the saved data format. To change it, increase `DB_VERSION` in `Collection.lua` and add a conversion to `migrations`, without changing the ones already released. Test it on a copy of real saved data before releasing.

`ForeverDexDB.challenge` keeps the daily challenge (`day`, `key`) until midnight, so that capturing the card does not draw another one. It is drawn again whenever it is missing or out of date.

`ForeverDexDB.view` keeps the sort, tab and filters between sessions. Its filter sets are the tables used by the window, so change them in place and never replace them.

The custom portrait is rendered from the target. Saved data keeps the character's identity and combination. Once the player is no longer targeted, the medallion shows the generic race portrait.

## Pages of the window

A page replaces the journal in the window: it covers `ns.UI.PageArea`, provides `SetShown(shown)` (show or hide its frames, refresh them when shown), and registers with `ns.UI.RegisterPage(mode, page)` and `ns.UI.AddSideTab(index, mode, label, paint)`. `ns.UI.Show(mode)` opens the window on it.

## Releases

The changelog of a release lists only what a player notices: additions, removals, important changes and bug fixes, one short line each. Small adjustments are never detailed: they share one generic last line ("Various interface improvements"). `CHANGELOG.md`, the GitHub release notes and `HOME_NEWS_LINES` in every locale carry the same entries.

Before a release, update `Home.NEWS_VERSION` in `Home.lua` and `HOME_NEWS_LINES` in every locale: they make the news window. `ForeverDexDB.seenVersion` remembers the last version the player logged in with: the login message mentions the news only once after an update.

## Comparison compatibility

Two players must be able to compare collections across different versions. Never change the shape of the `Q`, `A`, `N` and `D` messages in `Duel.lua`. To add data, create a new message type (ignored by older versions) or add a field after a tab in an existing item. Cards whose key is unknown to the catalog are ignored on receipt. `Presence.lua` uses the `P` and `H` types on the same prefix; older versions ignore them.

## In-game checks

Reload the UI with `/reload`. Check opening from the minimap, searching by full name, replacing a card and adding a bonus. Changing target must bring back the generic portrait. Test on both a French and an English client to check labels, tooltips and the confirmation dialog.

## Static checks

`luacheck .` must report no warning. `.luacheckrc` lists every game API the addon reads and every global it writes: add a new API there when you start using it. GitHub runs the same check on each push and pull request.
