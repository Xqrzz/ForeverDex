# Contributing

## Code layout

`ForeverDex.toc` loads the modules in this order. They share the private table WoW provides to the addon.

| File | Responsibility |
| --- | --- |
| `Locale.lua`, `Locales/` | Strings for each language. A missing string falls back to English. Also holds `ns.Module`: the other files register their code with it and run at `ADDON_LOADED`, once the saved language is known. |
| `Art.lua` | Client textures, atlases and sounds, with a fallback when an atlas is missing. `/foreverdex textures` lists missing atlases. |
| `Settings.lua` | Settings panel and default values. |
| `Catalog.lua` | Playable combinations, card themes, search, filters and sorting. |
| `Collection.lua` | Reading the target, saved data migration, adding and replacing cards. |
| `CaptureVisuals.lua` | Capture animation and the notification rising from the bottom of the screen. |
| `Duel.lua` | Comparison between two ForeverDex users: request, agreement, exchange over whispered addon messages, and the duel screen. |
| `Presence.lua` | Glowing icon above nearby ForeverDex players: ping and answer over whispered addon messages, icon hung from the nameplate, game settings saved and given back, and its settings page with a live preview. |
| `UI.lua` | Adventure Guide style window: race list, card grid, detail page, tabs and capture. |
| `ForeverDex.lua` | Initialization once saved data is loaded, game events, slash command and minimap button. |

`Media/` holds the capture orb (`Ball.tga`, a single image so it can rotate), the addon icons, and the presence icons (`Star.tga`, `Gem.tga`) with their soft halo and ring (`Glow.tga`, `Ring.tga`).

## Saved data

`ForeverDexDB.cards` maps each card to a stable key. A combination uses the game's numeric IDs (`race:class:sex`). A bonus uses `bonus:n` and keeps its original combination. Translated labels are never part of a key.

`ForeverDexDB.version` is the saved data format. To change it, increase `DB_VERSION` in `Collection.lua` and add a conversion to `migrations`, without changing the ones already released. Test it on a copy of real saved data before releasing.

`ForeverDexDB.view` keeps the sort, tab and filters between sessions. Its filter sets are the tables used by the window, so change them in place and never replace them.

The custom portrait is rendered from the target. Saved data keeps the character's identity and combination. Once the player is no longer targeted, the medallion shows the generic race portrait.

## Comparison compatibility

Two players must be able to compare collections across different versions. Never change the shape of the `Q`, `A`, `N` and `D` messages in `Duel.lua`. To add data, create a new message type (ignored by older versions) or add a field after a tab in an existing item. Cards whose key is unknown to the catalog are ignored on receipt. `Presence.lua` uses the `P` and `H` types on the same prefix; older versions ignore them.

## In-game checks

Reload the UI with `/reload`. Check opening from the minimap, searching by full name, replacing a card and adding a bonus. Changing target must bring back the generic portrait. Test on both a French and an English client to check labels, tooltips and the confirmation dialog.
