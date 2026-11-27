# Proximity interaction (issue #49)

`scripts/interaction.lua` lets the player press `E` next to NPCs and objects.
Pure logic (distance, cone, tie-breaks, edge detection) lives in
`scripts/interaction_logic.lua` and has no engine calls.

## Target selection

Each frame, `interaction.update` takes the enabled interactables and keeps the
ones that are:

- **in range**: the distance from the player's foot-box center to the closest
  point of the interactable rect is within `radius` (default 24 px);
- **in front**: the direction from the player to the interactable center is
  within a ±60° cone around the walker's facing (cosine >= 0.5). Centers closer
  than 4 px always count as in front.

Among those, the closest one wins. Ties go to the nearest center, then to
registration order.

## Registration API

```lua
local interaction = require("interaction")

interaction.register({
  rect = { x = 48, y = 60, w = 16, h = 16 },  -- or entity = e, size = { w, h }
  radius = 24,                                -- optional
  label = "Hablar",                           -- HUD verb
  target = "mamá",                            -- HUD object (optional)
  on_interact = function(it) ... end,         -- called on the key edge
  enabled = function() return true end,       -- optional filter
})
interaction.unregister(it)   -- removes one entry
interaction.clear()          -- removes all and resets the key edge
interaction.from_map(map)    -- builds entries from the TMX (see below)
interaction.update(dt, o)    -- once per frame; o = { x, y, facing, suppress }
```

- `rect` is in world coordinates. With `entity`, the rect is read from
  `get_position` each frame; if the entity no longer exists, the entry is
  skipped.
- `interaction.clear()` runs in the controller's `init`, so a scene reload never
  leaves stale rects or duplicates.

## Per-frame behavior

`interaction.update` returns the HUD text of the current target, or `nil`:

- Label: `E — <label> con <target>` (for example `E — Hablar con mamá`).
- A bobbing `!` is drawn above the target with `draw_text_world` (no asset).
- The town controller shows the text in its prompt slot, only when no door
  prompt is active.

Nothing is drawn or fired when `o.suppress` is true or the interaction is blocked.

## Key edge

Keys: `interact` or `interact_alt` (the same keys as doors: `E` / `Enter`).

- Edge-triggered: `on_interact` fires once on the frame the key goes down.
  Holding the key does not repeat it.
- The key state keeps updating while suppressed or blocked. Closing a dialogue
  with `E` therefore does not trigger a new interaction.

## Blocking

Interaction is blocked while either world flag is set:

- `dialogue.open` (set by `dialogue.lua` while a dialogue is open)
- `libreta.open` (set by the future notebook UI)

While blocked, the indicator and the HUD text are hidden and `E` does nothing.

## Hooks

- `interaction.on_npc(name, obj)`: called for `npc` interactables. `dialogue.attach()` sets it on every scene load and maps `npc` to
  `dialogue.scripts`. Without it, the NPC's `line` property is shown.
- `interaction.say(text)`: shows a one-line message. The town controller sets it
  to its line slot. Without it, the text is printed as `[interaction] ...`.

Interactables with `set_flag` set that world flag to `true` when used.

Narrated stories (issue #68) add three hooks, all wired by `story.attach()`:

- `interaction.story_available(id)`: returns `true` when the story can be started.
  It drives the prompt: with it `true`, the label is `interaction.STORY_LABEL`
  ("Escuchar la historia") and the target is not shown.
- `interaction.on_story(id, npc, obj)`: starts the story. Used when the story is
  available and the NPC has a `story` property.
- `interaction.STORY_LABEL`: the label used for an available story.

An interactable can set `label_fn(it)`, which returns `(label, bare)`. When `bare` is
`true`, the target is not appended to the label. `interaction.update` reads the
label through it on every frame.

While a story is playing, `interaction.is_blocked()` is `true` (flag
`story.open`), so no prompt is handled.

## TMX: `interactable` objects

Put interactables in an object layer (the examples use `interactables`) with
`class="interactable"`. Each object's position is its rect (`x`, `y`, `width`,
`height`); a point object gets a 0x0 rect.

| Property | Meaning |
| --- | --- |
| `npc` | NPC id. Makes the kind `npc` (default verb "Hablar"). |
| `interact` | `npc` or `object`. `door` is not supported here: doors belong in the `doors` layer, and a warning is printed. |
| `label` | HUD verb (default "Hablar" for NPCs, "Examinar" for objects). |
| `target` | HUD object, for example `mamá`. |
| `story` | Id of a narrated story (issue #68). While the story is available, the NPC prompt reads "E — Escuchar la historia" (no target) and E starts it. Otherwise the prompt and action are the NPC's own. |
| `radius` | Range in px (default 24). |
| `line` | One-line message (default `...`). |
| `set_flag` | Flag set to `true` on use (objects). |
| `enabled` | Condition in the door lock syntax (`a`, `!a`, `a,!b`). Missing means enabled. |
| `figure` | Placeholder figure (issue #70): `"r,g,b"` (0-255). Drawn by `interaction.draw_figures()` while the item is enabled. Invalid text is ignored. |

## Placeholder figures (issue #70)

`interaction.draw_figures()` draws a simple body and head at the bottom of each rect
that has a `figure` property. There are no NPC sprites yet, so this is how an NPC
that appears later is seen. The town controller calls it each frame after `draw_world()`.
The figure respects `enabled`, so an NPC that appears on a condition (for example
`mission.chequelo.next_day`) needs only an `interactable` with `enabled` and `figure`.
The helper that parses the colour is `interaction_logic.parse_color(text)`.

## Doors take precedence

Doors stay in `scripts/town_controller.lua`. The controller passes
`suppress = true` to `interaction.update` when:

- the foot box overlaps a door rect,
- a door transition is running,
- `ignore_until_clear` is set (after arriving, until the player leaves every door),
- a fade is in progress (`fade.alpha() > 0`).

So a press never fires a door and an interactable at the same time.

## Manual checklist

Automated tests are not used for this feature. Check in the game after building:

1. In the house, next to mama and facing her: the bobbing `!` and the HUD text
   `E — Hablar con mamá` appear. One `E` shows her line; holding `E` fires once;
   release and press again fires again.
2. Between mama and the radio: facing left selects mama, facing right selects
   the radio, facing down selects neither.
3. `world_state.set("dialogue.open", true)` (or `libreta.open`) hides the
   indicator and the prompt, and `E` does nothing.
4. Doors: the exit prompt `E: salir` still works. After arriving through a door,
   no interactable fires until the player leaves the door area. Nothing fires
   during fades.
5. Leave and re-enter the house: no duplicate entries and no duplicate prompts.

## Time of day: `only` and `sleep` (issue #66)

- `only = "night"` (or `"day"`, `"dusk,night"`) on an `interactable` enables it only in
  those phases; it is ANDed with `enabled`. See `time-of-day.md`.
- `sleep = true` on an `interact = "object"` makes the interaction call
  `interaction.on_sleep()` (the controller wires it to `time_of_day.sleep()`).

## Giving a tool: `give_tool` (issue #53)

`give_tool = "<id>"` on an `interact = "object"` gives the player that tool
([tools.md](tools.md)): it sets the flag `tool.<id>`, says `Conseguiste: <name>` and calls
`interaction.on_tool(id)` (the controller autosaves). Once owned, the interactable disables
itself. An unknown id is ignored with a `[tools]` log.
