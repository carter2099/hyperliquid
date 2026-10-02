# WebSocket Implementation

`Hyperliquid::WS::Client` (`sdk.ws`) manages two independent WebSocket connections:

| Connection | URL (mainnet / testnet) | Used by | Message shape |
|------------|-------------------------|---------|---------------|
| Main API | `wss://api.hyperliquid.xyz/ws` / `wss://api.hyperliquid-testnet.xyz/ws` | `subscribe` | `{ "channel": ..., "data": ... }` envelope |
| Explorer | `wss://rpc.hyperliquid.xyz/ws` / `wss://rpc.hyperliquid-testnet.xyz/ws` | `subscribe_explorer_block`, `subscribe_explorer_txs` | bare JSON array, no envelope |

Each connection has its own read, dispatch and ping threads, bounded queue and subscription table. Subscription ids come from one counter shared by both connections, so an id returned by `subscribe` or `subscribe_explorer_*` identifies exactly one subscription for `unsubscribe`. A message from one connection never reaches a callback registered on the other. Each connects on its first subscription; `connect` opens only the main connection; `close` closes both.

## Architecture

Per connection:

```
WS Read Thread ──> Bounded Queue (1024) ──> Dispatch Thread ──> User Callbacks
Ping Thread (every 50s)
```

- **Read thread** (`ws_lite`): receives frames, parses JSON, pushes onto the queue. Never blocks on user code.
- **Dispatch thread**: pops messages and calls the matching callbacks in order. A slow callback only blocks this thread. An exception raised by a callback is caught and printed as a warning; dispatch continues.
- **Ping thread**: sends `{"method":"ping"}` every 50 seconds to keep the connection alive.

## Message Flow

1. A raw frame arrives on the read thread.
2. Non-JSON frames (e.g. `"Websocket connection established."`) and `pong` replies are discarded.
3. A routing identifier is computed: from the `channel` and `data` of a main-API envelope (e.g. `l2Book:eth`), or, for an explorer array, from the fields of its first element (`blockTime`, `hash`, `height`, `numTxs`, `proposer` → `explorerBlock`; `action`, `block`, `error`, `hash`, `time`, `user` → `explorerTxs`). Messages without an identifier are dropped.
4. The message is pushed onto the connection's bounded queue. If the queue is full, the message is dropped and a warning is printed.
5. The dispatch thread pops the message, looks up callbacks by identifier, and calls each one with the message's `data` (main API) or the whole array (explorer).

## Subscription Routing

Subscriptions are keyed by an identifier string derived from the channel type and its parameters:

| Channel | Identifier format | Example |
|---------|-------------------|---------|
| `allMids` | `allMids` | `allMids` |
| `l2Book` | `l2Book:<coin>` | `l2Book:eth` |
| `trades` | `trades:<coin>` | `trades:eth` |
| `bbo` | `bbo:<coin>` | `bbo:eth` |
| `candle` | `candle:<coin>:<interval>` | `candle:eth:1h` |
| `orderUpdates` | `orderUpdates` | `orderUpdates` |
| `userEvents` | `userEvents:<user>` | `userEvents:0xabc` |
| `userFills` | `userFills:<user>` | `userFills:0xabc` |
| `userFundings` | `userFundings:<user>` | `userFundings:0xabc` |
| `explorerBlock` | `explorerBlock` | `explorerBlock` |
| `explorerTxs` | `explorerTxs` | `explorerTxs` |

Coins and users are lowercased. `orderUpdates` messages carry no user, so every `orderUpdates` callback receives every `orderUpdates` message on the connection. `subscribe` raises `Hyperliquid::WebSocketError` for a channel not in this table; `subscribe_explorer_*` raise `Hyperliquid::ConfigurationError` when the client has no explorer URL.

Multiple callbacks can be registered for the same identifier. The server unsubscribe message is only sent when the last callback for an identifier is removed.

## Queue Overflow

Each connection's queue is bounded (`max_queue_size:`, default 1024 messages). When full, new messages are dropped (queued ones are kept). Warnings print on the 1st drop and every 100th drop. Monitor via `dropped_message_count` (main) and `explorer_dropped_message_count` (explorer).

## Reconnection

On unexpected disconnect (when `reconnect: true`, the default), each connection reconnects on its own thread with exponential backoff: 1s, 2s, 4s, ..., capped at 30s. On reconnect, that connection's active subscriptions are replayed automatically.

## Lifecycle Hooks

`on(:open)`, `on(:close)` and `on(:error)` fire for the main API connection only. The explorer connection has no hooks; its errors are printed as warnings. Each event holds one callback; registering another replaces it. `on(:open)` also fires after every successful reconnect.

## Thread Safety

- Subscription tables, pending-subscription lists and drop counters are protected by one `Mutex` shared by both connections' threads.
- Ruby's `Queue` is inherently thread-safe.
- Callbacks for one connection are invoked serially on its dispatch thread. Main-API and explorer callbacks run on different threads and can run concurrently.
