# Meshex Bridge API v1

A bridge is a desktop integration. A module can relay mesh text to Telegram or another service, or answer directly in a mesh chat. The protocol is language-independent. See [the Python example](mesh_bot.py) for a bot that replies to `/meshping`.

## Connect a module

Open **Settings → Bridges**. Choose one connection, bind it to a mesh node, then select the channels and direct-message permissions it needs. To test a bot in a channel, select **All messages** for that channel and enable **Allow sending to selected channels**. Save the settings and click **Start**. Use **Stop** to close the connection. Start the bridge explicitly each time Meshex is launched.

| Connection | Settings |
| --- | --- |
| External process | Absolute executable path. Enter each non-empty argument on a separate line without shell quoting. A script uses its absolute interpreter path as the executable and the script path as an argument. Windows accepts executables ending in `.exe`. |
| Local HTTP | A separately started module listens on a loopback address. Enter `http://127.0.0.1:8765` or an explicit IPv6 loopback address such as `http://[::1]:8765`, and a shared token. |

The process method runs a local program with the privileges available to Meshex. Choose code you trust. macOS may restrict which executables a sandboxed build can start. Local HTTP works with an independently started module. Bind the HTTP listener to loopback and use a random token. Keep secrets out of process arguments and logs.

## Common wire format

The contract uses JSON-RPC 2.0 objects in UTF-8. Individual frames are up to 256 KiB. IDs in this profile are strings. Parameters are named objects, and each frame carries one request, response or notification. Module commands must include an RPC `id`. Batch requests, positional parameters and module notifications are outside this profile. Additional fields in results and events may be introduced in API v1.

| Transport | Framing and direction |
| --- | --- |
| Process | Meshex writes to the module's `stdin` and reads its `stdout`. Each JSON frame ends with a newline and must be flushed. Diagnostics go to `stderr`. The module should exit on EOF. |
| Local HTTP | Both directions use `/rpc` on the module. Every request carries `Authorization: Bearer <token>`. Meshex sends its frames using POST, and GETs long-poll for module requests. The module sends the result of initialization as HTTP 200 with a JSON object. For a POST containing a notification or a response to a module request, the module returns HTTP 204. GET returns HTTP 200 with a single request object or HTTP 204 when no command is pending. Return empty polls within 25 seconds. |

With HTTP, the module should keep the head of its command queue until Meshex POSTs the matching result or error. It can return that same command again after a lost connection. Preserve both the JSON-RPC `id` and the `commandId`. The module should accept concurrent HTTP requests, since an incoming mesh event can arrive while a GET is open. Both transports have an eight-second initialization timeout.

## Methods and events

### `bridge.initialize` · Meshex → module request

Meshex sends this first. Wait for initialization before sending module commands.

```json
{"jsonrpc":"2.0","id":"meshex-initialize","method":"bridge.initialize","params":{"apiVersion":1,"maxTextBytes":200}}
{"jsonrpc":"2.0","id":"meshex-initialize","result":{"apiVersion":1}}
```

`apiVersion` and `maxTextBytes` are integers. Respond with the same RPC ID and a result containing the supported `apiVersion`. If the version is incompatible, return an error.

### `mesh.messageReceived` · Meshex → module notification

```json
{"jsonrpc":"2.0","method":"mesh.messageReceived","params":{"nodeId":"!abcd1234","messageId":"!11223344:329021","author":{"id":"!11223344","name":"Alex"},"target":{"id":"channel:opaque-id","kind":"channel","name":"LongFast"},"replyRef":"opaque-reply-ref","text":"/meshping","receivedAt":"2026-11-20T08:00:00.000Z","radio":{"packetId":329021,"destinationId":"!ffffffff","channelIndex":0,"rxRssi":-92,"rxSnr":6.5,"hopStart":3,"hopLimit":1,"hops":2,"viaMqtt":false,"wantAck":false,"pkiEncrypted":false,"xeddsaSigned":false,"portNum":1}}}
```

`target.kind` is `channel` or `direct`. Node identifiers use `!xxxxxxxx`. `messageId` identifies the packet in the scope of `nodeId`. `receivedAt` is an ISO 8601 UTC timestamp. Treat `target.id` and `replyRef` as opaque and keep them with `nodeId`.

The optional `radio` object describes the packet received by the connected node. Existing API v1 modules can ignore it. Treat missing measurements as unknown, and preserve valid zero readings.

| Fields in `radio` | Type and meaning |
| --- | --- |
| `packetId`, `portNum`, `replyId` | Integer packet ID, Meshtastic application port, and original reply packet ID when present. |
| `destinationId`, `channelIndex` | Destination node ID (`!ffffffff` for broadcast) and local channel slot when available. Use the top-level `target.id` or `replyRef` to send. |
| `rxRssi`, `rxSnr`, `rxTime` | RSSI in dBm, SNR in dB, and the receiver's raw Unix timestamp in seconds, when reported. RSSI and SNR describe the receiving node's radio link. With relays, they describe the last RF leg. |
| `hopStart`, `hopLimit`, `hops` | Integer initial and remaining forwarding budgets from the header when reported. `hops` is their difference when the header provides enough information, with an omitted remaining budget treated as zero. A direct reception can have zero hops. |
| `relayNode`, `nextHop` | Integer low bytes of the relay and next-hop mesh node numbers, when reported. The full node IDs cannot be inferred from either byte alone. |
| `transportMechanism`, `priority`, `delayed` | Meshtastic enum names when reported. |
| `viaMqtt`, `wantAck`, `pkiEncrypted`, `xeddsaSigned` | Boolean packet flags for an MQTT leg, acknowledgement requested, PKI encryption, and a valid XEdDSA signature. |
| `bitfield` | Integer flags from the decoded payload header, when present. |

The optional `packet` object carries the complete `MeshPacket` for this event in two forms:

| Field in `packet` | Meaning |
| --- | --- |
| `json` | A Protobuf JSON object with the packet fields known to Meshex, including `decoded` and its payload bytes encoded as Base64. Protobuf field names are camel-cased. |
| `protobufBase64` | The reserialized binary `MeshPacket`, Base64 encoded. This form also preserves fields the Meshex protobuf schema does not recognize. |

The packet comes from the connected node's client API and includes the decoded payload for admitted text events. Use `radio` for normalized measurements and the top-level `target.id` or `replyRef` for replying. Modules on older versions of Meshex may receive events without `packet`.

The module gets live messages covered by the selected channel rules or the receive-direct permission. Meshex omits its own outgoing messages, ignored senders, database history and messages available only through the mirror. Events are best-effort. Meshex can drop events when its outbound queue fills or the module is disconnected.

### `mesh.reactionReceived` and `mesh.stickerReceived` · Meshex → module notifications

Both carry the same message identity, author, destination, time, `radio` and `packet` fields as a text event. Modules can ignore unfamiliar notifications.

- A reaction carries `emoji` and `radio.replyId`. When the original is already known in the same bridge session and chat, `originalRef` is its `replyRef`. A reaction has no reply reference of its own.
- A sticker carries `sticker` (the validated Meshex sticker envelope with `wire_version`, `source_url`, `pack_sha256` and `sticker_id`) and a `replyRef`. When available, `originalRef` points to the message it answered.
- In channels set to **Mentions**, reactions and stickers are forwarded when they reply to a message from the connected mesh node. **All messages** and receive-direct rules cover both event types.

### `mesh.getStickerMedia` · module → Meshex request

Pass the sticker event's `replyRef` and an optional byte `offset` starting at zero. Each result contains `dataBase64` (up to 128 KiB of decoded WebP bytes), `size` (total bytes) and `animated` (boolean). Advance the offset by the decoded chunk length until it reaches `size`. A stale reference, a missing local pack or a blocked source returns `-32003`. Meshex reads its installed pack library and does not fetch a remote source for the module.

### `mesh.listTargets` · module → Meshex request

Pass an optional non-empty `query` string up to 80 characters. The result contains the `nodeId` string and up to 100 writable `targets` with the same shape as the notification's `target`. The query matches channel names or a node's name, short name or ID. Channel IDs expire when the bridge stops. Direct-message targets come from the node database and need a usable public key.

```json
{"jsonrpc":"2.0","id":"rpc-1","method":"mesh.listTargets","params":{"query":"LongFast"}}
{"jsonrpc":"2.0","id":"rpc-1","result":{"nodeId":"!abcd1234","targets":[{"id":"channel:opaque-id","kind":"channel","name":"LongFast"}]}}
```

### `mesh.sendMessage` · module → Meshex request

| Field | Type | Meaning |
| --- | --- | --- |
| `commandId` | String, 1–128 characters | Stable identifier for this send attempt. Generate a new one for a new message. |
| `nodeId` | String | The node ID returned with the target or event. |
| `text` | Non-blank string | Text to send, up to 200 UTF-8 bytes. |
| `targetId` | String | Destination ID from `mesh.listTargets` or an event. Supply for a new message. |
| `replyRef` | String | Reference from `mesh.messageReceived`. Supply for a reply. The last 512 references are kept for the running session. |
| `mentionAuthor` | Optional boolean | With a channel reply, `true` prepends the original author's mesh node ID. The prefix counts toward 200 bytes. |
| `reaction` | Optional boolean | With a reply, `true` sends a mesh reaction and `text` contains one emoji. Omit `mentionAuthor` for a reaction. |

Supply exactly one of `targetId` and `replyRef`. Meshex derives the reply destination from the reference, verifies its permissions and rechecks that the selected local channel still matches its saved configuration. A private reply goes to the original sender. A channel reply goes to the original channel and includes the original packet ID.

```json
{"jsonrpc":"2.0","id":"rpc-2","method":"mesh.sendMessage","params":{"commandId":"fcfa1215","nodeId":"!abcd1234","replyRef":"opaque-reply-ref","text":"Pong"}}
{"jsonrpc":"2.0","id":"rpc-2","result":{"status":"queued","packetId":349015040}}
```

The immediate result has status `queued` and an integer `packetId`. It may also return `{"status":"unknown"}` for a replay of a command that was claimed before Meshex could record its outcome. A duplicate with identical inputs within 24 hours does not send again for the same saved connection. Meshex can record up to 2,048 commands during that period. A reused command ID with modified input is rejected. If an outcome is unknown, check whether the original message appeared before sending it with a new command ID.

### `mesh.deliveryChanged` · Meshex → module notification

```json
{"jsonrpc":"2.0","method":"mesh.deliveryChanged","params":{"nodeId":"!abcd1234","commandId":"fcfa1215","packetId":349015040,"status":"acked","accepted":true}}
```

`nodeId` and `commandId` are strings. `packetId` is an integer and is omitted for an `unknown` event. The optional `accepted` boolean is present when acceptance by the local radio is known. Status values are `acked`, `failed`, `rejected`, `timeout`, `disconnected` and `unknown`. Optional `error` and `ackProof` strings carry firmware details. An `acked` channel message can be confirmed by a relay. Correlate by `commandId`, since the event can arrive before the RPC response.

### Errors

Branch on `error.code`. The message is human-readable.

| Code | Meaning |
| --- | --- |
| `-32600` | Invalid request |
| `-32601` | Unknown method |
| `-32602` | Invalid parameters |
| `-32603` | Internal error |
| `-32000` | Bridge initialization or version error |
| `-32001` | The bridge's mesh node is unavailable or the request names a different node |
| `-32002` | Destination is unavailable or outside the permissions |
| `-32003` | Reply reference has expired |
| `-32004` | Text exceeds the UTF-8 byte limit |
| `-32005` | Meshex failed to queue the send |
| `-32006` | Command ID was reused with different parameters |
| `-32007` | Command budget exhausted |

## Run the example

For a process bridge set the executable to your absolute `python3` path and add the absolute path to `mesh_bot.py` as the sole argument. For HTTP, choose a shared token and run the following on macOS or Linux. On Windows, set `MESHEX_BRIDGE_TOKEN` in your shell before running the script.

```sh
MESHEX_BRIDGE_TOKEN='your-random-token' python3 examples/bridges/mesh_bot.py --http 8765
```

Connect Meshex to `http://127.0.0.1:8765` with that token. From another mesh node send `/meshping` to the configured channel. The example replies in the same channel and includes the hop count, RSSI and SNR when available.

The [Telegram adapters](telegram/README.md) use the same public API and handle their own bot token and account pairing.
