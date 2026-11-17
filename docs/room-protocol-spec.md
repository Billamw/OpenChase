# OpenChase Room Protocol Spec — v0.1 draft

Replacement for the Nostr-relay transport with a self-hosted WebSocket room server
(homelab). Design goals, in order:

1. **Thin client seam** — game code keeps speaking plain `Map` payloads; only the
   transport classes change (~360 lines of `lib/utils/nostr/*` replaced).
2. **1:1 local→prod parity** — one `serverUrl` config value; same protocol on
   `ws://localhost:8080` and behind the public tunnel.
3. **Server owns what relays can't** — presence, join/leave truth, late-join state,
   replay protection. Relays gave us none of this and we hacked around it
   (`joined`/`left` broadcast events, 5-minute replay window).

Fixes to today's design that this spec bakes in:

| Current (Nostr) | Problem | Spec |
|---|---|---|
| Room code embeds room **private** key (`NostrHelper` ships a static keypair; `getFormattedRoomInfo` serializes private keys) | anyone with the code can forge any room event | room code is opaque; player gets a per-join **playerToken** |
| `Keychain.generate()` game keypair broadcast in plaintext to the room | pointless crypto theater | game keypair dropped; server-issued `roundId` |
| Subscribe filter `since: now-5min` | every late joiner replays old joins/leaves; dedup by name hack (`addPlayersWithoutDuplicates`) | server sends authoritative snapshot once; `clientMsgId` dedup |
| Player leaves → broadcasts `{"left": name}` | name-based identity collides; WS drops ≠ leave | connection-scoped presence, server-driven `playerLeft` |
| No acks, no error responses | silent failures | `ack`/`error` envelopes, per-message `id` |

---

## 1. Transport

- Single WebSocket per role-state: `wss://<host>/ws` (one connection can be in at
  most one room; game channel is *the same socket*, phase-switched — one socket per
  device, fewer moving parts than the current dual-relay-connection design).
- Messages: JSON text frames, UTF-8. Every message:

```json
{ "t": "<type>", "id": "<8-char client msg id, senders only>", ...payload }
```

- Reconnect: client retries with exponential backoff (1s→30s cap) and sends
  `resume {sessionToken}`. Session token issued on `roomJoined`/`playerJoined`;
  valid 120 s after disconnect so a game can survive a tunnel blip or app switch.
- Rate limit (server-side): 5 location msgs/s per player; excess silently dropped.
- HTTP companion: `GET /health` (uptime/version), `GET /room/<code>` → `{exists,
  phase, playerCount}` so join screens can validate a code *before* connecting.

## 2. Identifiers & lifecycle

| Id | Shape | Lifetime |
|---|---|---|
| `roomCode` | 6 chars, A–Z0–9 minus `OI01` | room closed + 15 min reclaim window |
| `sessionId` | uuid v4 | per connection (resume re-binds to same session) |
| `playerId` | uuid v4 | per player per room; survives reconnect |
| `roundId` | uuid v4 | one host-initiated round |
| `playerToken` | 32-hex random | per player, returned at join, required for `resume` |
| `hostToken` | 32-hex random | per host, returned at create/resume |

Phases: `lobby → playing → finished`. One round at a time; a room can cycle
`finished → lobby` via explicit `endRound`.

## 3. Room creation & join

```
host ──▶ roomCreate  { name }
   ◀── ack { roomCode, hostToken, sessionId }

host ──▶ share code out-of-band (QR/text) — code only, no secrets

player ──▶ roomJoin { code, name }
   ◀── error { code: "no_such_room" | "room_full" | "game_started" }
   ◀── ack { playerId, playerToken, sessionId }

server ──▶ playerJoined { player: {id, name}, playerCount }   to all in room
host  ◀── roomSnapshot { phase, players[], round? }           (host on (re)connect)
```

Max room size: 16 players (config). Duplicate names allowed — identity is `playerId`.

## 4. Presence

- Server presence = live WS sessions bound to a room. No `left` events from clients.
- Graceful `leave { }` from client → `playerLeft { playerId }` to room.
- Socket drop → 60 s grace (player marked gray in `roster`), then `playerLeft`.
- `resume { token }` inside grace → player back to live, roster update broadcast.
- Host drop → same grace; room **closes** if host doesn't resume in 120 s
  (players get `roomClosed { reason: "host_gone" }`).

## 5. Game channel (same socket, phase `playing`)

```
host ──▶ roundStart { area: {center: [lat,lng], radiusM}, items?: [...] }
   ◀── ack { roundId }
server ──▶ roundStarted { roundId, area, startedAt } → whole room

any ──▶ location { lat, lng, accuracyM?, ts }        (ts = client clock ms)
   ◀── ack only on error (acks off for location — 5 Hz would spam)
server ──▶ playerLocation { playerId, lat, lng, accuracyM?, ts, seq } → whole room
```

- `seq`: per-player monotonic counter assigned by server — clients use it to drop
  out-of-order fan-out (reconnect races).
- Server keeps `positionHistory` per player (last N=600, ~2 min at 5 Hz) so
  late joiners and reconnects get `rosterSnapshot { players[], positions{}, round }`.
- Reveal mechanic (maps to existing `Player.revealPosition/trailVisible` fields).
  Event shape is authority-agnostic — who enforces the cost is a swappable
  decision (§9.3):

```
any ──▶ revealRequest { playerId }
  [server-authority]  server validates cost, then:
server ──▶ revealed { playerId, positions: [[lat,lng,ts],...] } → whole room
  [host-authority]    host validates cost, then relays the same event via:
host  ──▶ revealed { playerId, positions: [...] }   (server fan-out only)
```

- Items (`Item` model community): host places at setup (`roundStart.items`),
  runtime interactions later (`itemHit { itemId }` → validated proximity ≤
  30 m before `itemCollected`; validator = host or server, same authority axis as
  reveals). v0.1: host-trusted, proximity check v0.2.

```
host ──▶ roundEnd
server ──▶ roundEnded { roundId, stats }  → phase back to lobby
```

## 6. Security (v0.1 honest minimum)

- WSS only in production (tunnel terminates TLS).
- No secrets in room codes. `playerToken`/`hostToken` are the only credentials;
  leak of a playerToken = someone can spoof that player until it expires
  (acceptable v0.1; v0.2: per-message HMAC or short-lived tokens).
- Server validates: token↔room↔role binding, message size ≤ 2 KB, type whitelist
  per phase, rate limits.
- No end-to-end encryption (relays never gave us that either; trust the server you
  host). If commercializing later: E2E with per-round key agreed in `roundStart`.

## 7. Client seam (Flutter)

Keep today's inheritance shape — game screens don't change:

```
lib/utils/room/
  base_room.dart     # BaseRoom: WebSocketChannel + connect/close/resume  (was BaseNostr)
  room_client.dart   # RoomClient: roomCreate|roomJoin, roster, presence  (was HostRoomNostr+PlayerRoomNostr+InitialNostr)
  game_client.dart   # GameClient: roundStart, location, reveal, items    (was GameNostr)
```

- `onMessageReceived(Map)` callback signature **unchanged** — event `t` + payload
  flatten into the same maps `map.dart` already switches on (`playerLocation`
  carries `user` alias for the current `{user, lat, lng}` handler).
- `GameManager`: replace keypair fields with `roomCode, playerToken, hostToken,
  playerId, roundId`; keep `players` list (now `List<Player>` with ids — fixes the
  name-identity bug).
- `NostrHelper`, `nostr:` pub dependency, `webrtc_signaling.dart`: deleted.

## 8. Server (homelab)

- One small stateful process. Options: Dart `shelf` + `shelf_web_socket` (shares
  models with the app, fits your docker-compose homelab), or Rust. State in memory;
  optional append-only JSONL per room for post-game review (nice for v0.2 stats).
- Deployment: docker-compose on Proxmox (backend + website as services) exposed via
  **Tailscale Funnel** — one public HTTPS origin `https://<machine>.<tailnet>.ts.net`
  serving: static PWA files (`flutter build web` output), `/ws` WebSocket upgrade to
  the room server, `/health`. Funnel terminates TLS with its own auto-renewed cert →
  the backend never manages certificates. Native/sideloaded apps connect to the same
  origin (`--dart-define=SERVER_URL=wss://<funnel-host>/ws`).
- Funnel caveats baked into the client design: idle-timeout proxy → protocol
  requires WS ping/pong keepalive (≤30 s); free-tier bandwidth cap (~1 GiB/day) is
  fine for location JSON but keep assets small; native Flutter WS handshakes behind
  some TLS terminators can be flaky — if seen, fall back to Cloudflare Tunnel.
- Invariants: rooms auto-GC when phase idle > 15 min or host gone; single round at
  a time; every broadcast idempotent via `seq`.

## 9. Open decisions (need your call)

1. **Server language**: Dart (model sharing, one ecosystem) vs Rust?
2. **Spectator role**: same socket with `role: spectator`, read-only fan-out — cheap
   to add now, annoying to retrofit. Include?
3. **Authority placement for game rules** (reveals, items): server-validates vs
   host-validates-with-relay. Protocol event shapes identical either way — decide
   per rule, can mix. Friends game → host-authority is fine and keeps the server
   at ~200 lines. Public/competitive later → move rules server-side. Plus the
   open game-design question: what does a reveal *cost*?
4. **Round model**: today there's no timer/win state at all — does v0.1 need
   `roundEnded` *stats*, or keep it minimal (start/end only)?
