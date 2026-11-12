# ForeverDex

A collection journal for World of Warcraft: Forever. Meet a player with a funny name? Capture them and fill your journal, one race, class and gender combination at a time.

## Features

- **112 cards**, one for each race, class and gender combination, plus **39 bonus slots** for the names you just can't leave behind
- **Capture from the target portrait** or by right-clicking a name in chat, with a full capture animation (which can be shortened or turned off)
- **Detail page for each capture**: date, zone, level and guild when the game provides them, and which of your characters made the capture
- **Search by name, guild or zone**, with filters (race, class, gender, capturing character) and sorting that are remembered between sessions, plus a Favorites tab
- **Duels**: compare your collection with another ForeverDex user
- **Announcements** (optional): share your captures and achievements with your guild, group or a custom channel
- **Home page**: a daily challenge (a combination to look for, just for fun), the latest news and a few statistics about your collection
- **Achievements**: 34 goals (captures, races, classes, genders, pets…) announced with an achievement-style alert
- Available in **English, French, German, Spanish, Italian, Portuguese and Russian**, with a language setting independent of the game client

## Installation

Install it with your addon manager once it is available on CurseForge, or manually:

1. Download the latest version from the [tags page](https://github.com/Xqrzz/ForeverDex/tags).
2. Extract it to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Rename the extracted folder to `ForeverDex`.

## Usage

Open the journal with the minimap icon or `/foreverdex`. Each session starts on the home page; the side tabs on the right switch between the home page, the journal and the achievements.

- **Capture a player:** target them and click the ball on their portrait, or right-click their name in chat and choose **Add to ForeverDex**. Captures from chat do not include level or guild.
- **Card already taken?** You can replace it or add the new character as a bonus.
- **Fill a bonus slot:** open the **Bonus** tab, target a player and choose **Add as bonus**.
- **Capture a pet:** target a hunter's pet and click the ball. Its name, family and owner go into the **Pets** tab.
- **Manage a card:** right-click it to add it to your favorites, move it to or from the bonus cards, or delete it.
- **Spot other collectors:** a glowing ForeverDex icon appears on the nameplate of nearby friendly players who have the addon too (friendly nameplates must be on, Shift+V), and their tooltip says they have ForeverDex. Pick the icon (capture orb, spark of light or a raid marker), the detection distance (10, 30 or 40 yards), its glow, opacity, size and whether it stays or only pings for a few seconds under Options → AddOns → ForeverDex → Collectors, with a live preview. You can also stop showing yourself to others.
- **Announce your captures:** under Options → AddOns → ForeverDex → Announcements (or `/fdex share`), turn on the announcements of your captures and achievements to your guild, your group or a custom channel you joined. Off by default; Blizzard channels (General, Trade…) are never used.
- **Compare collections:** right-click a player portrait, a party or raid member, or a name in chat, then choose **Compare our captures**. With a controller, use the **Compare collections with target** key binding instead.

| Command | Action |
| --- | --- |
| `/foreverdex` or `/fdex` | Open or close the journal |
| `/fdex home` | Open the home page: daily challenge, news and statistics |
| `/fdex capture` | Capture your target (works in macros) |
| `/fdex compare` | Compare collections with your target (works in macros) |
| `/fdex collectors` | List the nearby players who have ForeverDex (`/fdex presence` also works) |
| `/fdex collectors demo` | Show the icon above every friendly player nearby, to try it out (nothing is sent) |
| `/fdex achievements` or `/fdex hf` | Open the achievements page (also the tab on the right of the window) |
| `/fdex share` | Open the Announcements settings |
| `/fdex options` | Open the settings |

Capturing the target, comparing collections with it and opening the journal can also be bound to a key or a controller button, under Options → Keybindings → AddOns → ForeverDex.

Settings are also available under Options → AddOns → ForeverDex, or by right-clicking the minimap icon.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/Xqrzz/ForeverDex/issues).

Want to look at the code? See [CONTRIBUTING.md](CONTRIBUTING.md).
