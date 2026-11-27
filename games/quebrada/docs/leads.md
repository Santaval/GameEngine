# Word-of-mouth leads (issue #69)

Part of #34. Each legend says who to ask next ("andá donde fulano"). When a legend
resolves, the game shows a lead line, saves the lead in the libreta, sets `unlock.*`
flags and puts a subtle marker on the target door or gate. Locked zones are gated.

Modules: `scripts/leads_logic.lua` (pure: rules, graph, reachability, flag keys,
markers, gates) and `scripts/leads.lua` (engine glue). All state lives in `world_state`.

## The `next` field

`next` is a list of rules. The first rule whose `when` is `nil` or true wins; a rule
without `when` is the default. A single rule table is accepted as shorthand.

| Rule field | Meaning |
| --- | --- |
| `when` | Optional missions condition. |
| `person` | Points to every legend whose `teller` is that person. |
| `legend` | Explicit target legend id (overrides `person`). |
| `line` | Lead line shown on screen. Required with `person` or `legend`; keep it at most 70 bytes. |
| `unlocks` | List of `house.<id>` or `zone.<id>`. |
| `pending` | `true` when the target is not recorded yet (warning instead of error). |

A rule without `person` or `legend` is terminal and is only allowed on a legend with
`final = true`. Other legend fields: `final` (may lead nowhere) and `resolve_when`
(a condition; when present it is the only trigger).

## Triggers and timing

- Default trigger: the story was heard (`story.<id>.heard`) or the legend's
  `mission_offer` mission left `none` and `offered` (accepted or rejected).
- `leads.tick` runs every frame, only on a clear screen (no dialogue, story, F3,
  transition or fade). It resolves at most one legend per frame.
- A legend resolves once: `lead.resolved.<id>` makes it idempotent.

## Flags

| Flag | Meaning |
| --- | --- |
| `lead.resolved.<legend>` | The legend has been resolved. |
| `lead.rule.<legend>` | Index of the rule that was picked. |
| `lead.person.<person>` | A lead to that person was given. |
| `unlock.house.<id>` / `unlock.zone.<id>` | The target is open. |
| `lead.mark.<key>` | Show the marker for `house.<id>` / `zone.<id>`. |
| `lead.seen.<key>` | The player visited the target; the marker goes away. |

## Libreta

`libreta.add_lead(id, text, person, source)`, `has_lead(id)`, `leads()` and
`lead_count()`. Flag layout in [stories.md](stories.md). A rule with a `person` adds a
lead; a terminal rule only shows its line.

## Tiled

- `lead="house.<id>"` or `lead="zone.<id>"` on a `door`, `gate` or `marker` object. A
  bobbing 3x3 dot shows above it while `lead.mark.<key>` is set and `lead.seen.<key>` is
  not. `seen` is set when a door carrying that `lead` is entered, or when the matching
  zone toast fires. For `marker`, point or rect, only `lead` is read.
- Class `gate` in layer `gates`: `locked` (same syntax as doors) and `locked_line`.
- Doors: `locked="!unlock.house.<id>"`.

## Gating

Static colliders cannot be toggled from Lua, so while a gate is locked and the player's
foot box overlaps it, the controller restores the last safe position and shows
`locked_line`. Keep gates at least 12 px thick so the player cannot tunnel through.
Teleport doors such as `door_shed` bypass gates, so lock them with the same
`unlock.zone.<id>`.

## Validator

```
lua5.3 games/quebrada/tools/validate_legends.lua [root]
```

Errors: repeated or missing id, rules without `line`, invalid unlock keys, targets with
no legend (unless `pending`), dead ends (no valid `next` and no `final`), legends not
reachable from the root (`chequelo`). Warnings: long lines, no default rule, unlocks not
used by any `locked` in the maps. The exit code is 1 on errors. It does not load
`story.lua`. In game, `leads.validate()` prints the same checks when the scene starts.

## Adding a legend (data only)

1. Create `scripts/legends/<id>.lua` (the `sound` is optional).
2. Add it to `scripts/legend_index.lua`.
3. Point a previous legend's `next` at its `teller` (or `legend` id).
4. Optionally add a door or gate with `lead` and `locked`.

## Retesting

In F3, clear `lead.resolved.<id>`, `libreta.lead.<id>`, `lead.seen.<key>` and
`unlock.<key>` to replay a lead.
