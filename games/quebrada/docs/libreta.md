# Libreta (issue #80)

A notebook screen with a small recorder look. `scripts/libreta_ui.lua` draws it and handles input;
all data logic is in `scripts/libreta_logic.lua` (tested in `tests/libreta_logic.lua`). The storage
of clues and leads is still `scripts/libreta.lua` ([stories.md](stories.md)).

## Controls

| Key | Action |
| --- | --- |
| Tab or L | Open / close (works in the town and the house) |
| Left / Right (A / D) | Previous / next tab |
| Up / Down (W / S) | Move in the list |
| E / Enter | On a story with a recorder: listen to the full recording again |

While open the player cannot move and doors, interactions, clues and the HUD wait (like the F3
overlay). The ambience keeps playing; the world is not frozen.

## Tabs

- **Historias**: every legend found (started or heard, resolved, or that left a clue), with teller,
  summary, *Empezada* / *Escuchada* status and the ending reached. After them there are always
  `BLANK_PAGES = 2` empty ruled pages. That number is fixed and never counts the missing legends,
  because the collection is open.
- **Pistas**: the clues, grouped under the legend they came from.
- **Misiones**: *Activas*, *Por hacer* (recommendations: leads whose house or zone marker you have
  not visited yet, e.g. "Ña Chayo vio algo raro...") and *Terminadas* with the outcome.

## Recorder icon and replay

The icon appears **only** when the legend has `kind = "real"` **and** a `sound`
(`libreta_logic.has_recorder`). A legend like `chayo` (real but without a recording) shows none,
and so do generated ones. `E` calls `story.play(id, { replay = true })`: the full recording plays from
the start with the same player as #68 (pause with Space, stop with Backspace / Q), without the
greeting, the mission offer or the closing/recommendation dialogue. The player has no seek, so a replay
is always complete from the start.

The recording must be declared in the scene's `sounds`; `town_demo.lua` and `house_demo.lua` both
declare `story_chequelo` (and the story keys). A new real recording needs the same in both scenes.

## Ending reached

A legend may declare `ending_flag = "chequelo.ending"` and `endings = { stayed_home = "Te quedaste en casa", ... }`.
The page shows `Final: <text>` when the flag has a value (an unmapped value is shown as is).

## "Nuevo"

Each entry has a flag `libreta.seen.<kind>.<id>` (`story`, `clue`, `mission`, `lead`); it is set when the
entry is selected, so it is saved with the game. Unseen entries show a red *Nuevo*, a small sparkle
(a few twinkling `draw_rect` points: there is no particle binding) and a dot on the tab. When the libreta
opens with something new, and also when a new clue, lead or story is added (`libreta.notify()` in
`libreta.lua`, called from `add_clue`, `add_lead` and when a story first starts), it plays `sfx_libreta_new` softly.

The sound is `sounds/sfx/sfx_new.mp3`, declared as `sfx_libreta_new` in both scenes (volume 0.4 on the
`sfx` bus, set in `libreta_ui.lua`). A scene that does not declare it plays nothing.

## Manual checklist

- Tab in a fresh game: no story, two blank pages; Tab again closes it and the player moves.
- Hear Chequelo's recording in the house: Tab shows it with the recorder icon, *Escuchada* and the ending
  once the mission ends; `E` replays it, also from the town, and no closing dialogue appears.
- `chayo` (after entering her house) shows as *Encontrada* with no icon and no replay.
- Clues are grouped by legend; *Por hacer* shows the Chayo lead until you enter her house.
- *Nuevo* disappears after selecting the entry; it stays gone after save and continue (key 7).
