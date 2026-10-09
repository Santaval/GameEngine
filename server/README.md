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

## Fake-client bot

`npm run bot` connects a scripted player to the relay so a single game
instance can be tested alone. It sends `spawn` (script
`player/remote_player.lua`), `state` at 10 Hz while flying in a circle, and a
`fire` every 1.5 s. It only ever reports its own HP (`damage` / `death`).
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
| `--radius`, `--cx`, `--cy` | Circle radius (default 300) and center (default 10000, 10000: the player spawn in `scenes/aval_cup.lua`), in world pixels. |
| `--fire-interval <sec>` | Seconds between shots (default 1.5). |
| `--duration <sec>` | Exit automatically after this many seconds. |

The bot logic lives in `tools/botLogic.ts` (pure, tested in `test/bot.test.ts`).
