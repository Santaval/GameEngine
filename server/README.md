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
```

Environment variables: `PORT` (default 7777), `HOST` (default 0.0.0.0),
`RATE_LIMIT_PER_SEC` (120), `RATE_LIMIT_BURST` (240), `HEARTBEAT_INTERVAL_MS` (5000).
