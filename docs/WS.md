# WebSocket Implementation

## Architecture

`Hyperliquid::WS::Client` is a managed WebSocket client backed by three background threads:

```
WS Read Thread ──> Bounded Queue (1024) ──> Dispatch Thread ──> User Callbacks
Ping Thread (every 50s)
```

- **Read thread** (`ws_lite`): receives frames, parses JSON, pushes onto the queue. Never blocks on user code.
- **Dispatch thread** (`hl-ws-dispatch`): pops messages from the queue and invokes matching callbacks in order. If a callback is slow, only this thread blocks.
- **Ping thread** (`hl-ws-ping`): sends `{"method":"ping"}` every 50 seconds to keep the connection alive.

## Message Flow

1. Raw frame arrives on the read thread.
2. Non-JSON messages (e.g. `"Websocket connection established."`) and `pong` responses are discarded.
3. A channel identifier is computed from the message (e.g. `l2Book:eth`).
4. The message is pushed onto the bounded `Queue`. If the queue is full, the message is dropped and a warning is emitted.
5. The dispatch thread pops the message, looks up callbacks by identifier, and calls each one.

## Subscription Routing

Subscriptions are keyed by an identifier string derived from the channel type and its parameters:

| Channel        | Identifier format                  | Example             |
|----------------|------------------------------------|---------------------|
| `allMids`      | `allMids`                          | `allMids`           |
| `l2Book`       | `l2Book:<coin>`                    | `l2Book:eth`        |
| `candle`       | `candle:<coin>:<interval>`         | `candle:eth:1h`     |
| `userEvents`   | `userEvents:<user>`                | `userEvents:0xabc`  |

Multiple callbacks can be registered for the same identifier. The server unsubscribe message is only sent when the last callback for an identifier is removed.

## Queue Overflow

The internal queue is bounded (default 1024 messages). When full, new messages are dropped (oldest retained). Warnings print on the 1st drop and every 100th drop. Monitor via `dropped_message_count`.

## Reconnection

On unexpected disconnect (when `reconnect: true`, the default), the client spawns a thread that retries with exponential backoff: 1s, 2s, 4s, ..., capped at 30s. On reconnect, all active subscriptions are replayed automatically.

## Thread Safety

- `@subscriptions` and `@pending_subscriptions` are protected by a `Mutex` as they are accessed across the three threads.
- Ruby's `Queue` is inherently thread-safe.
- Callbacks are invoked serially on the dispatch thread (never concurrently).
