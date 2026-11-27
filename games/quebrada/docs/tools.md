# Tools instead of weapons (issue #53)

There are no weapons: the player carries **tools** that come from the legends or the town.
Each one has a single, specific use. `scripts/tools.lua` holds the definitions as data and
`scripts/tools_logic.lua` the pure logic (tested in `tests/tools_logic.lua`). The player and the
controller have no per-tool code.

## Ownership and saving

A tool is owned when the world flag `tool.<id>` is true. Flags survive scene loads and are saved
by `save.lua` through `world_state.snapshot()`, so **tools are saved** with no format change.

This deliberately does not use `InventoryComponent`: entities are recreated on every `load_scene`
(the player is rebuilt when entering a house), so an inventory on the player would be lost. Flags
also work in Tiled `enabled`/`when` conditions. The selected tool (`tools_state.selected`) is not saved;
it falls back to the first owned tool.

## Defining a tool

An entry in `tools.DEFS` (the list order is the bar order):

| Field | Meaning |
| --- | --- |
| `id`, `name`, `label` | Flag name, display name and the short HUD label |
| `color` | `{r, g, b}` of the slot tint |
| `source` | Where it comes from (documentation) |
| `use.when` | Flag condition (`"a,!b"`); if false the tool is not used and `use.blocked` is shown |
| `use.fn(ctx)` | Custom action returning `ok, message`; `ok == false` cancels the rest |
| `use.set_flag` | Flag set to `true` on use (legends read it: `when = "sal.used"`) |
| `use.consume` | `true` removes the tool after use |
| `use.line` | Message shown on use |

Current tools: **foco** (toggles the beam, with battery, see [lighting.md](lighting.md)),
**rosario** and **sal** (set `rosario.used` / `sal.used`, consumed; defined by the legend that
needs them), **machete** (only usable while the flag `mona.battle` is true), **cables**
(set `cables.used`, consumed). To add one, add a definition and a way to get it.

## Getting a tool

- Tiled interactable: `give_tool = "foco"` ([interaction.md](interaction.md)); the house has a
  `linterna` giving the foco.
- Dialogue lines/options: `set_flag = "tool.sal"` ([dialogue.md](dialogue.md)).
- Missions or code: `tools.give("sal")` / `tools.take("sal")`, or `ws.set("tool.sal", true)`.

## Controls and HUD

`1`–`4` select the n-th owned tool and `X` uses it (blocked while a dialogue, the overlay, a story,
a time card or a fade is on). The bar (bottom centre, up to 4 slots) is drawn **only when the player
owns at least one tool**; the selected slot has a bright border and a slot whose `use.when` is not
met is dimmed. The old `G` foco key is gone.

## Manual checklist

- A new game shows no bar. Take the `linterna` in Mamá's house: the bar appears with `FOCO`, `X` toggles the beam.
- With the F3 overlay, set `tool.sal`: a second slot appears, `2` selects it, `X` sets `sal.used` and removes it.
- With `tool.machete`, the slot is dim and `X` says it is not for this until `mona.battle` is true.
- Pick up a tool, wait for the autosave, press `7` on the main scene: the tool is still there.
