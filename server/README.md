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
| `--radius`, `--cx`, `--cy` | Circle radius (default 300) and center (default 23150, 20000: the player spawn in `scenes/solar_system.lua`), in world pixels. |
| `--fire-interval <sec>` | Seconds between shots (default 1.5). |
| `--duration <sec>` | Exit automatically after this many seconds. |

The bot logic lives in `tools/botLogic.ts` (pure, tested in `test/bot.test.ts`).
