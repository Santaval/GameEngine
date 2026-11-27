# Dialogue box (issue #50)

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
| `set_flag` | World flag set to `true` when the line is finished. |
| `choices` | Shown after the last page of the line. Each entry is a string or `{ text, set_flag?, next? }`. |

For a choice table, `set_flag` is set when the option is chosen, and `next` is a
script (list of lines) spliced in right after the current line.

## API

- `dialogue.start(script, opts?)`: starts a dialogue and returns its handle, or
  `nil` if one is already open or the script is empty. `opts.on_choice(idx, line, opt)`
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

## Limits

- One dialogue at a time.
- The box is drawn with rectangles; there is no 9-slice art. `dialogue.box` and
  `dialogue.nine_slice` are hooks for it but nothing sets them.
- Glyph coverage is whatever DejaVu Sans Mono has (covers á é í ó ú ñ ¿ ¡).
- The Lua environment has no `utf8` library, so the module counts UTF-8
  characters with patterns.
