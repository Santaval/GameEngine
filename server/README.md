# Relay server

Dumb WebSocket relay for the multiplayer protocol: one global room, playerId
assignment, host election, routing and hardening. It never interprets gameplay
payloads. Protocol: [`docs/multiplayer-protocol.md`](../docs/multiplayer-protocol.md).

```
npm install
npm run dev     # tsx watch src/index.ts
npm run build   # tsc -> dist/
npm start       # node dist/index.js
npm test        # vitest
npm run typecheck  # tsc over src, test and tools
npm run bot     # scripted fake player (see below)
```

Environment variables: `PORT` (default 7777), `HOST` (default 0.0.0.0),
`RATE_LIMIT_PER_SEC` (120), `RATE_LIMIT_BURST` (240), `HEARTBEAT_INTERVAL_MS` (5000).

`GET /health` returns `200 ok` (for container health checks); any other plain
HTTP request gets `426 Upgrade Required`.

## Docker / Coolify

```
docker build -t relay-server .
docker run --rm -p 7777:7777 relay-server
```

To deploy on Coolify, create an application from this repo with:

- **Build pack:** Dockerfile, **Base directory:** `/server`
- **Ports exposes:** `7777`
- **Health check:** path `/health`, port `7777` (the image also has its own
  `HEALTHCHECK`)

The engine's WebSocket client is built without TLS, so it can only use
`ws://`, not `wss://`. Pick one:

- Map the port directly (**Ports mappings** `7777:7777`, open it in the
  firewall) and connect with `--server ws://<server-ip>:7777`.
- Or give the app an `http://` domain (not `https://`) so Coolify's proxy
  serves it on port 80 and connect with `--server ws://<domain>`.

## Server bots

The relay can host bots that play the Aval Cup for real (hunt, flee, collect
death orbs, score in the ranking). They are in-process virtual clients: they
join the room like any player (`peer_joined`, `spawn`, `state`, ...) but use
no socket, heartbeat or rate limit, and their messages go through the same
validation and routing as real ones. They are never host (the host must
simulate the map), so with no humans there are no bots.

| Variable | Default | Meaning |
| --- | --- | --- |
| `BOTS` | `0` | Fill the room up to this many ships: humans + bots = `BOTS`. `0` = no bots. |
| `BOT_BRAIN` | `auto` | `auto` (Jev if `AI_GATEWAY_API_KEY` is set, else heuristic), `jev` or `heuristic`. |
| `BOT_MODEL` | `typesafe-ai/jev` | Vercel AI Gateway decision model id. |
| `BOT_DECISION_MS` | `1500` | Brain interval per bot (with +-20 % jitter). |
| `BOT_SKILL` | `0.35` | Bot difficulty, `0` (easy) to `1` (sharp): aim error, fire rate, dodging, attack range and reaction time. Bots below `0.5` never start a fight (they only retaliate). |
| `BOT_DEBUG` | off | Log every bot decision and key event. |
| `AI_GATEWAY_API_KEY` | - | Read by the AI SDK itself. Never commit it. |

Fill-up: `BOTS=8` with 3 humans connected runs 5 bots; a human joining removes
the newest bot, a human leaving adds one, and when the last human leaves all
bots go. Bots are added or removed one at a time (250 ms apart).

Two layers. The brain (slow, async) turns an observation (own hp, score, rank,
nearest enemies and loot, incoming bullets) into a decision
`{mode, targetId, aggression}` with `mode` one of `attack`, `hunt_leader`,
`flee`, `collect`, `farm`, `mine`, `roam`. The controller (10 Hz, pure) carries it out:
steering, lead aim, firing (only while pvp is on), orb pickup, plus reflexes
that always run (dodge bullets, stay out of the storm band). Bots earn score
by mining planets, shooting asteroids and picking up the orbs, send `rank_score`, drop their minerals on death
(`death_drop`) and get a spawn shield, like the game client.

- **Heuristic brain:** simple rules (flee when hurt, collect nearby loot,
  retaliate when shot, then mine a planet or farm rocks; sharp bots (`BOT_SKILL` >= 0.5) also attack weaker enemies and hunt the leader). No network. Rocks and planets come from the host through `bot_scan` (see `docs/aval-cup.md`).
- **Jev brain:** one `experimental_decide` request per decision with the
  observation as `state`. It is skipped (bot roams) when nothing is near. On
  an error or after 1.2 s it falls back to the heuristic; after 3 failures in
  a row it stays on the heuristic for 60 s. Cost scales with
  `BOTS / BOT_DECISION_MS`, so raise `BOT_DECISION_MS` to save money.

Railway: set `BOTS` (and `AI_GATEWAY_API_KEY` for Jev) in the service
variables. Without a key the bots keep playing with the heuristic.

The code lives in `src/bots/` (`botLogic.ts` controller, `brain.ts`,
`manager.ts`), so the Docker image includes it.

## Fake-client bot

`npm run bot` connects a scripted player to the relay so a single game
instance can be tested alone. It sends `spawn` (script
`player/remote_player.lua`), `state` at 10 Hz and plays the same way as a
server bot (same controller as above). It only ever reports its own HP
(`damage` / `death`).
It also echoes `custom` messages: a `custom{type:"ping", data}` from another
player is answered with a direct `custom{type:"pong", data}` carrying the same
data, which gives a single-instance round-trip check for `net_send` / `net_on`.

```
npm run bot -- --host --pvp --duration 30
```

| Flag | Meaning |
| --- | --- |
| `--url <ws url>` | Relay address (default `$GAME_SERVER` or `ws://localhost:7777`). |
| `--name <name>` | Name in the spawn state (default `bot-<4 hex>`). |
| `--host` | Answer host-only requests (`snapshot_request` with a `snapshot`) while it is the host. Warns if it is not. A bot that is not answering as host still re-sends its ship `spawn` directly to the requester. |
| `--pvp` | Broadcast `room_settings{pvp:true}` while it is the host, and take damage from player bullets. |
| `--brain jev\|heuristic` | Strategy brain (default `heuristic`). `jev` needs `AI_GATEWAY_API_KEY`; `--model` overrides the model id. |
| `--skill <0..1>` | Difficulty (default `0.35`). |
| `--duration <sec>` | Exit automatically after this many seconds. |

The bot logic lives in `src/bots/botLogic.ts` (pure, tested in `test/bot.test.ts`).
