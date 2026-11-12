# Changelog

## 1.8.0

- New home page, shown the first time the window opens in each session, with its own side tab above the journal one
- Daily challenge: a race, class and gender still missing from your journal, drawn on its race's scenery, with the progress of that race and class. A new one each day at midnight, with a countdown. Nothing to win, it is only a suggestion. Once captured, the card is marked as met; with a complete journal, the challenge becomes finding a funnier name than the current one
- "What's new" box summarizing the latest release
- Short statistics: journal progress, captures of the last seven days, last capture, most captured class, favorite hunting ground and achievements
- `/fdex home` opens the home page

## 1.7.8

- Announcements: ForeverDex can tell your guild, your group or a custom channel you joined about your captures and achievements, with a funny line picked at random (several dozen, in every language). Off by default
- New Announcements settings page: channel for captures and for achievements, new cards only or replacements too, bonus cards and pets, minimum points of an announced achievement, custom channel name with a live status, [ForeverDex] tag, minimum delay between two announcements, and a local preview
- General, Trade, LocalDefense, LookingForGroup and the other Blizzard channels are always refused, as are /1 and /2
- Several achievements earned at once make a single message
- `/fdex share` opens the Announcements page
- The capture lines and the card messages no longer assume the character is male in French, Spanish, Italian, Portuguese and Russian

## 1.7.7

- Each new capture remembers which of your characters made it, shown on its detail page as "Captured by"
- New "Captured by" filter, under Gender, as soon as cards were captured by at least two characters (older captures are listed as Unknown)
- Search also looks at the capturing character
- Achievements: 34 ForeverDex achievements for the number of captures, every race and every class seen, each race, class and gender completed, the full journal, the bonus slots and the pets. They are announced with an alert in the style of the game's achievements, its fanfare, and a line in the chat
- What your collection already deserves is granted silently the first time, without a flood of alerts
- Achievements page, through a new tab on the right of the window: your points out of the total on a bar, the categories in a column like the races, and the achievements of each one on parchment sheets with their own progress bar, the ones still to earn greyed out. `/fdex achievements` (or `/fdex hf`) and a click on the alert open it too
- New setting to turn the achievement alert off
- The cards no longer overlap the carved top edge of the journal background, and its empty scroll bar rail on the right is no longer shown

## 1.7.6

- Fixed Skyborne players added from chat always going into the Horde card: the faction is now read from the player when they are visible (target, nameplate, group…), and from chat channels that only reach your own faction
- When a Skyborne speaks in /say, /yell or an emote and is not visible, ForeverDex asks which faction they belong to (Alliance or Horde) before adding them
- "Compare our captures" from chat also shows the right Skyborne card

## 1.7.5

- Collectors: a glowing ForeverDex icon on the nameplate of nearby friendly players (10, 30 or 40 yards) who have the addon too, and a line in their tooltip, so you know who you can compare with. Your nameplate settings are never changed: the icon needs friendly nameplates (Shift+V)
- New Collectors settings page with a live preview: icon (capture orb, spark of light, or one of the eight raid markers), detection distance, glow intensity, opacity, size, height, and permanent display or a ping of a few seconds
- Option to stay invisible to other ForeverDex players
- Works with nameplate addons: the icon goes above and in front of their bar
- Opening the settings from the minimap icon, `/fdex options` or the book no longer leaves the Escape menu open
- Settings tooltips with choices list each choice on its own line, its name in gold
- `/fdex collectors` lists the nearby players who have ForeverDex
- Demo to try the icon in game: "Test in game" on the Collectors page, or `/fdex collectors demo`, shows it above every friendly player nearby without sending anything

## 1.7.1

- Fixed Follow being blocked (and controller buttons locking up) when opening a player's portrait menu with a controller: in controller mode, "Compare our captures" is no longer added to portrait menus
- New key binding to compare collections with your target, usable on a controller button

## 1.7.0

- Combat mode on the duel screen: pick a champion, then vote for the best name
- Pets: capture hunter pets with their name, family and owner, in a new Pets tab with 60 slots

## 1.6.1

- Key bindings (keyboard or controller) to capture the target and open the collection
- `/fdex capture` to capture the target from a macro
- The capture ball now shows on the target frame of other interfaces, like EllesmereUI

## 1.6.0

- Right-click menu on every card: favorite, bonus, delete
- Bonus cards can go back to their standard card when it is free
- Sort, tab and filters are remembered between sessions
- Search also looks at guild and zone
- `/fdex` shortcut
- German, Spanish, Italian, Portuguese and Russian
- Language setting, independent of the game client
- Long names shrink to fit instead of being cut off
- "Sex" filter renamed to "Gender"
- Duel filters show how many cards each one contains
- Fixed large collections failing to compare inside instances
- Removed fallbacks for old game APIs

## 1.5.0

First release on CurseForge.
