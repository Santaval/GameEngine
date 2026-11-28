# Narrated stories (issue #68)

A narrator NPC can tell a legend. The NPC prompt switches from "Hablar" to
"E — Escuchar la historia" once the story is available. Listening plays the full
recording with a player overlay, and the story's clues are saved to the libreta.

Code: `scripts/story.lua` (glue), `scripts/story_logic.lua` (pure logic),
`scripts/libreta.lua` (clue store), `scripts/legend_index.lua` (list of legends),
`scripts/legends/<id>.lua` (one file per legend).

## Flow

1. The NPC's TMX object has `story="<id>"`. While the story is available, the
   prompt reads "E — Escuchar la historia" (no "con <target>").
2. Pressing E starts the legend's `greeting` as a dialogue (`dialogue.start`).
   The greeting's `on_end` starts the recording. If the greeting was already
   shown (`story.<id>.greeted`), the recording starts directly.
3. The recording plays on the `voice` bus. The ambience and music duck to 0.35.
   The overlay shows the teller, the title, the summary, a progress bar with a
   mark at the "heard" threshold, and `m:ss / m:ss  NN%`.
4. Controls while listening: Space pauses and resumes, Backspace or Q stops.
   The player, doors, interaction, F3, the 0 key and dialogue are blocked.
5. `closing` and `recommendations` play as a dialogue when the recording ends, or
   when the player stops it after the threshold was crossed in that session. A
   stop before the threshold plays nothing. The lines are never played for a
   handle lost to a scene reload.
6. A story with `repeatable = false` is not offered again after it is heard.

The overlay and the dialogue box never show at the same time.

## Legend fields

| Field | Meaning |
| --- | --- |
| `id` | Unique id. Used in the TMX `story` property and in flag names. |
| `teller` | Value of the NPC's `npc` property (for example `mama`). |
| `teller_name` | Name shown on the overlay. |
| `sound` | assetId of the recording. It must be declared in the scene's `sounds`. Optional: a legend without a recording is a valid node of the lead graph, but the prompt never offers it. |
| `kind` | `"real"` (recording) or `"generated"`. The libreta shows the recorder icon only when `kind == "real"` **and** `sound` is set. |
| `ending_flag`, `endings` | Optional. Flag holding the ending reached and a `value -> text` table; the libreta shows it on the story page (see [libreta.md](libreta.md)). |
| `title` | Title shown on the overlay. |
| `summary` | Short text shown on the overlay (wrapped, at most 6 lines). |
| `heard_at` | Fraction (0 < x <= 1) at which the story counts as heard. Default `0.8`. |
| `lived` | Optional. `value -> text` table (same keys as `endings`): the libreta shows the text below the summary for that ending. A key with no entry shows nothing extra (issue #82). |
| `repeatable` | `true` lets a heard story be listened to again from the prompt. The chequelo story uses it (issue #82). |
| `requires` | Optional condition (missions `when` function) that makes the story available. The chequelo story has none: it is available from the first visit. |
| `mission_offer` | Optional mission id, offered when the story starts (idempotent). |
| `greeting` | Lines `{ speaker, text }` played before the recording, once. |
| `closing` | Lines played after the recording ends, or after it is stopped once heard. |
| `recommendations` | Lines appended after `closing`. Optional; the word-of-mouth lead now comes from `next`, not from here. |
| `clues` | List of clues (see below). |
| `next` | Word-of-mouth rules (issue #69). See [leads.md](leads.md). |
| `final` | `true` lets the legend lead nowhere (see [leads.md](leads.md)). |
| `resolve_when` | Condition that resolves the lead; when present it is the only trigger (see [leads.md](leads.md)). |
| `on_heard` | Optional function `fn(id)`, called once when the story becomes heard. |

## Adding a legend

1. Create `scripts/legends/<id>.lua` that returns the table above.
2. Add `require("legends.<id>")` to `scripts/legend_index.lua`.
3. Declare the recording in each scene that plays it, with `stream = true`:
   `{ assetId = "story_<id>", filePath = "sounds/stories/<file>.mp3", stream = true }`.
   Recordings live in `sounds/stories/`.
4. Put `<property name="story" value="<id>"/>` on the NPC's `interactable` object
   in the TMX.

Scenes that do not declare the sound cannot play it: `play_sound` returns `0` and
the overlay does not open. The message "No se pudo reproducir la grabación." is
shown instead.

## Heard threshold

- `started`: the playback position is above 0.
- `heard`: the fraction reaches `heard_at` (default 0.8).

Progress is saved (`story.<id>.progress`) when the story is paused, stopped, ends,
the scene reloads, or the threshold is crossed. Nothing is written per frame.
The status never goes back: a story that was heard stays heard.

An unknown duration (`sound_duration` returns `nil`) gives a fraction of 0, so the
story is never marked heard.

## Flags

| Flag | Meaning |
| --- | --- |
| `story.<id>.started` | Set when the story has been started (any progress). |
| `story.<id>.heard` | Set once the threshold is reached. |
| `story.<id>.progress` | Highest fraction reached, rounded to 0.01. |
| `story.<id>.greeted` | Set when the greeting has been shown. |
| `story.open` | Transient. `true` while the overlay is open. Not saved. |

These flags can be used in `when` strings, for example `"story.chequelo.heard"`.

## Clues

A clue is a short text (at most 60 characters) that is recorded in the libreta
once its conditions are met.

| Field | Meaning |
| --- | --- |
| `id` | Unique within the legend. The full id is `<legend>.<clue>`. |
| `text` | Text shown as "Pista: ..." |
| `map`, `zone`, `time`, `near`, `when` | Triggers. Every field present must match (AND). `time` is `"day"` or `"night"`; `near = { x, y, r }` is in world px (`r` defaults to 24). |

Rules:

- A clue fires once. Its entry is kept in the libreta after that.
- Clues are evaluated in every town scene, even without the story's sound.
- Clues are shown one at a time, each for 4 seconds under the toast. The display
  queue holds 4 clues. If it is full, the clue is still saved in the libreta but
  its text is not shown.
- Clues are not evaluated while the dialogue, the overlay, the F3 overlay, a door
  transition or a fade is on screen, so a clue whose conditions are met then is
  checked again once the screen is clear.

## Libreta store

`scripts/libreta.lua` stores the clues in `world_state` flags:

| Flag | Meaning |
| --- | --- |
| `libreta.clue.<id>` | `true` while the clue is in the libreta. |
| `libreta.clue_n.<id>` | Order number. It is kept if the flag is turned off and on again. |
| `libreta.clue_id.<n>` | Id of the n-th clue. |
| `libreta.clue_text.<id>` | Text of the clue. |
| `libreta.clue_src.<id>` | Id of the story that gave the clue. |
| `libreta.clue_count` | Number of clues ever recorded. |

Word-of-mouth leads (issue #69) use a parallel set, one per legend (API: `add_lead`,
`has_lead`, `leads`, `lead_count`):

| Flag | Meaning |
| --- | --- |
| `libreta.lead.<id>` | `true` while the lead is in the libreta. |
| `libreta.lead_n.<id>` | Order number. |
| `libreta.lead_id.<n>` | Id of the n-th lead. |
| `libreta.lead_text.<id>` | Lead line. |
| `libreta.lead_person.<id>` | Person the lead points to. |
| `libreta.lead_src.<id>` | Legend that gave the lead. |
| `libreta.lead_count` | Number of leads ever recorded. |

API: `add_clue(id, text, source)` (returns `true` if new), `has_clue(id)`,
`clues()` (list of `{ n, id, text, source }`), `clue_count()`.

The libreta screen ([libreta.md](libreta.md), Tab / L) shows them. To test a clue again, turn its
`libreta.clue.<story>.<clue>` flag off in the F3 overlay.

## Controls

| Key | Action |
| --- | --- |
| Space | Pause and resume. |
| Backspace or Q | Stop. The recording fades out over 150 ms, or stops at once while paused. |

Escape is not used: it quits the engine and is never delivered to scripts (see
[lua-api.md](../../../engine/docs/lua-api.md#input)).

Pause needs the engine functions `pause_sound` and `resume_sound`. Without them
the pause key does nothing and the hint on the overlay does not show it.

## Audio

- The recording plays on the `voice` bus, which ducks ambience and music to 0.35
  while it plays (see [audio.md](audio.md)).
- A paused voice keeps the ducking active, so the ambience stays low until the
  story is resumed or stopped.

## Limits

- No subtitles and no sync with the recording. The whole recording plays.
- Scene loads stop every sound. If the scene reloads while a story plays, the
  session is saved (progress and "heard" if reached) and the overlay closes.
- Only one story plays at a time.
- `next` is handled by `leads.lua`, see [leads.md](leads.md).
