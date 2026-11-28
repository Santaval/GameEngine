# Dialogue box (issues #50, #51)

A box at the bottom of the screen with a speaker tab, word-wrapped typewriter
text, pages and optional choices. Code: `scripts/dialogue.lua` (glue and
drawing), `scripts/dialogue_logic.lua` (pure logic), `scripts/dialogues.lua`
(data).

## Data format

`dialogues.lua` returns a table keyed by the `npc` property of a TMX object.
Each value is a list of lines:

| Field | Meaning |
| --- | --- |
| `speaker` | Name shown in the tab above the box. Empty or missing hides the tab. |
| `text` | The line. `\n` forces a paragraph break. |
| `voice` | Reserved. Sound id played on the `voice` bus when the line starts and stopped when it ends. It does not drive timing yet. An unknown id logs one engine line. |
| `set_flag` | World flag set to `true` when the line is finished. `set_flag = "tool.sal"` gives the player a tool ([tools.md](tools.md)). |
| `choices` | Shown after the last page of the line. Each entry is a string or `{ text, set_flag?, next?, when?, mission_accept?, mission_reject?, call? }`. |
| `when` | Condition: a function, or a string such as `"a,!b"` over world flags. If false, the line is skipped. |
| `mission_offer` | Mission id offered (state `none` to `offered`) when the line starts. Lines with `choices` never emit "done", so the offer cannot wait for the end of the line. It is idempotent. |

For a choice table, `set_flag` is set when the option is chosen, and `next` is a
script (list of lines) spliced in right after the current line.

Choice fields beyond those: `when` hides the option when false, `mission_accept` /
`mission_reject` call `missions.accept` / `missions.reject` with that id, and `call`
is a function `fn(opt)` run when the option is chosen. Order on choosing: `on_choice`
callbacks, then the option effects (`set_flag`, missions, `call`), then `next` is
spliced, then the next line is selected.

## Conditions (`when`)

- `when` is evaluated lazily, each time the dialogue arrives at a line or builds its
  choices, never when the script is loaded. Spliced lines (`next`) are tested the same way.
- Because choices are filtered, the indices passed to `on_choice` and stored in
  `results` refer to the filtered list.
- A `when` function that errors logs a message and counts as false. An empty string
  is false too (omit the field instead).
- Reaction-lines-after-choice pattern: put the reactions after the choice line, each
  with a `when` on the mission state. After the choice changes the state, the matching
  line plays next and the others are skipped. See `scripts/dialogues.lua`.

## API

- `dialogue.start(script, opts?)`: starts a dialogue and returns its handle, or
  `nil` if one is already open or the script is empty or every line is filtered out by `when`. In the filtered case the dialogue ends inside `start`, so `on_end` has already run (with an empty results list) before `nil` is returned. `opts.on_choice(idx, line, opt)`
  runs when a choice is confirmed. `opts.on_end(results)` runs at the end, with
  the list of chosen indices. A line may also carry its own `on_choice(idx, opt)`.
- `dialogue.is_open()`: true while a dialogue is running.
- `dialogue.reset()`: clears the state and the `dialogue.open` flag. Call it on
  every scene load (the flag is global and survives scene reloads).
- `dialogue.attach()`: sets `interaction.on_npc` so an `npc` property maps to
  `dialogue.scripts[npc]`. Call it on every scene load. The town controller does
  both.
- `dialogue.register_script(name, script)`: adds or replaces a script.
- `dialogue.update(dt)`: updates and draws the box. The town controller calls it
  after the door and interaction logic, so the key press that closes a dialogue
  is already consumed before a door can see it.

## Controls

- `E` / `Enter`: the first press skips the typewriter, the next one advances the
  page or closes the line.
- Arrow keys / `W` `S`: move the selection among choices (clamped, no wrap).
- `E` / `Enter`: confirms the choice.

The key that opened the dialogue does not advance it (edges are seeded with the
current key state).

## Text rules

- Wrapping is done in Lua: greedy by words, UTF-8 aware, using `measure_text`.
  A word wider than the box is broken between characters.
- Pages hold 3 lines (`dialogue.MAX_LINES`). A blinking `v` marks a finished page.
- The typewriter reveals 40 characters per second (`dialogue.CPS`).
- Font id `dialogue` (DejaVu Sans Mono, 16) must be declared in the scene.
  Text is rasterized at native resolution while positions scale.

## While open

The player is frozen (the walker input is replaced and restored afterwards),
`dialogue.open` is set, doors and interactables are blocked, the back key is
ignored, and the toast, line and prompt texts are hidden.

## Narrated stories (issue #68)

A story's `greeting`, `closing` and `recommendations` are ordinary scripts
started with `dialogue.start`. The greeting's `on_end` starts the recording.
The story overlay and the dialogue never show at the same time.
See [stories.md](stories.md).

## Consequence comments (issue #70)

`dialogue.attach()` builds each NPC's script with `consequences.build_script(npc, base)`:
the entries of `scripts/consequences_data.lua` whose `who` matches the NPC and whose
`when` holds are **prepended** to the NPC's base script, in data order. An entry with
`once = true` is shown once: when its script is built it sets `comment.<id>.seen`.
Without matching entries the base script is used unchanged (or the `line` property).
See [consequences.md](consequences.md).

## Limits

- One dialogue at a time.
- The box is drawn with rectangles; there is no 9-slice art. `dialogue.box` and
  `dialogue.nine_slice` are hooks for it but nothing sets them.
- Glyph coverage is whatever DejaVu Sans Mono has (covers á é í ó ú ñ ¿ ¡).
- The Lua environment has no `utf8` library, so the module counts UTF-8
  characters with patterns.

## Abuela Paula and Abuelo Pepe

`npc = abuela_paula` and `npc = abuelo_pepe` (interactables in `maps/house_paula.tmx`) have scripts in `scripts/dialogues.lua`: Abuela Paula warns about the monte during the Chequelo night (`when = mission_is("chequelo", "night_active")`) and otherwise talks about the coffee and her crochet;
Abuelo Pepe talks about the old monte and the cafetal. No flags or missions; they are placeholder figures (`figure = "r,g,b"`) like mama.
