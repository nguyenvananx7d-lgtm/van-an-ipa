# ffxc-auth

Web authentication backend for the **Vortex Arena / YABAOCHEAT** iOS client. A single
`POST /api` endpoint answers the client's authorization and heartbeat requests with an
**Ed25519-signed envelope**, and a token-gated console manages keys, device bindings,
and live sessions.

It is built to the wire contract already present in `YABAOCHEAT/Licensing/*` — no app
protocol changes are required beyond pointing the endpoint and pinning the public key.

```
ffxc-auth/
  src/
    server.ts          entrypoint, routing, /health, session sweep
    config.ts          env parsing + startup guards
    crypto.ts          Ed25519 load / sign / mint
    protocol.ts        wire types (mirror of LicenseResponse.swift)
    store.ts           JSON-backed license + session store (atomic writes)
    http.ts            body reader + response helpers
    api.ts             POST /api  — authorize + heartbeat
    admin.ts           /admin console (HTML) + /admin/api/* (REST)
  scripts/
    mint-keys.ts       generate the signing keypair
  deploy/
    Caddyfile          TLS reverse proxy
  .env.example
  package.json
  tsconfig.json
```

## Requirements

- **Node.js ≥ 20.6** (`--env-file` support; no native modules).
- A TLS terminator (Caddy/nginx) in front — the app targets `https://…/api`.
- TypeScript + `tsx` are the only dev dependencies.

## Install, mint, run

```bash
cd ffxc-auth
npm install

cp .env.example .env
# set ADMIN_TOKEN (openssl rand -hex 32) and review the policy values

npm run mint          # writes keys/private.pem and keys/client_public_key.der
#                     # optionally copies the .der into YABAOCHEAT/Resources/

npm run build
npm start             # node --env-file=.env dist/src/server.js
# dev: npm run dev    # node --watch --import tsx src/server.ts
```

The server refuses to boot without `ADMIN_TOKEN` and without `keys/private.pem`.

### Pin the public key in the app

`mint` writes a raw 32-byte Ed25519 public key. That is exactly what
`Curve25519.Signing.PublicKey(rawRepresentation:)` expects, despite the `.der`
extension. Copy it over the bundled key:

```
ffxc-auth/keys/client_public_key.der  ->  YABAOCHEAT/Resources/client_public_key.der
```

> The file shipped in this repo is **0 bytes** — an empty pin means
> `LicenseVerifier.pinned()` returns a nil key and every server signature fails,
> which is why the build currently short-circuits to the local `submit(key:)`
> bypass. Minting a real key closes that seam.

Rebuild the IPA afterwards so the new key lands in `Copy Bundle Resources`.

## Admin console

Open `https://<host>/admin?token=<ADMIN_TOKEN>`. The token is stored in the browser
and sent as `X-admin-token` on every call. The console can:

- mint 1–500 keys at a time (plan, expiry in days, max devices, note),
- revoke / restore / delete a key,
- unbind a single device or reset all bindings,
- drop live sessions.

REST surface (all under `/admin/api`, all require the token):

| Method | Path | Effect |
|---|---|---|
| `GET` | `/keys` | list keys with bound devices |
| `POST` | `/keys` | mint keys (`count`, `plan`, `expiresInDays`, `maxDevices`, `note`) |
| `GET` | `/keys/:key` | key detail |
| `DELETE` | `/keys/:key` | delete key + its sessions |
| `POST` | `/keys/:key/revoke` \| `/restore` | set status |
| `POST` | `/keys/:key/reset-devices` | drop all device bindings + sessions |
| `DELETE` | `/keys/:key/devices/:hwid` | unbind one device |
| `GET` | `/sessions` | live sessions |
| `DELETE` | `/sessions/:token` | drop a session |

## Wire contract

`POST /api`, `content-type: application/json`. Dispatch is by body shape: a `key`
field is an authorization, a `session` field is a heartbeat.

**Authorization response** — HTTP 200, body:

```json
{
  "data": "<base64 of the signed LicenseResponse JSON>",
  "ts": 1750000000,
  "sig": "<base64 Ed25519 signature over the raw JSON bytes>",
  "sequence": -1,
  "leaseSeconds": 300,
  "mac": "AA:BB:CC:DD:EE:FF",
  "policy": { "protocol_version": 3, "heartbeat_seconds": 90, "max_network_errors": 3,
              "secure_transport_required": true, "patch_open_monitor_ms": 2000, "...": "..." }
}
```

`ts` must stay within `LicenseVerifier.maxClockSkew` (120s) of the device clock or the
client treats the envelope as a replay. `mac` is echoed so the verifier's device bind
passes.

**Verdicts ride `status` inside the signed payload**, not the HTTP status — the client's
`adopt`/`acceptHeartbeat` switch on the string:

| `status` | meaning |
|---|---|
| `valid` | session issued (authorize) or renewed (heartbeat) |
| `invalid` | key unknown |
| `revoked` / `deleted` | operator action |
| `expired` | past `expiresAt` |
| `deviceMismatch` | key already bound to `maxDevices` other devices |
| `sessionInvalid` / `replayDetected` | heartbeat against a dead/stale session |

Only malformed requests (bad JSON, wrong `product`) use HTTP 400/403.

## Configuration that has to match the app

Keep these aligned with `YABAOCHEAT/Licensing/ProtocolConstants.swift`:

- `PRODUCT_ID` — `productId` (`pkg_40921350d3307e51491f27cb`)
- `PROTOCOL_VERSION` — `protocolVersion` (3)
- the endpoint path — the client posts to `<endpoint>`; point `ProtocolConstants.endpoint`
  at your host, ending in `/api`

`PATCH_DIGEST` / `NEUTRAL_DIGEST` are optional. Leave them blank so the app keeps its
bundled payload pins; set both only if you want the server to pin the blob.

## Deploy

```bash
npm run build
node --env-file=.env dist/src/server.js   # behind Caddy, see deploy/Caddyfile
```

Systemd unit:

```ini
[Unit]
Description=ffxc-auth
After=network.target

[Service]
WorkingDirectory=/opt/ffxc-auth
ExecStart=/usr/bin/node --env-file=.env dist/src/server.js
Environment=NODE_ENV=production
Restart=on-failure
User=ffxc

[Install]
WantedBy=multi-user.target
```

State lives in `data/store.json` (atomic writes). Back it up with the keypair; the
store can be swapped for SQLite/Postgres later behind the `Store` interface.

## Notes

- Verify the pinned key is non-empty after mint: `wc -c YABAOCHEAT/Resources/client_public_key.der` → `32`.
- Rotating the keypair invalidates every issued session; clients re-auth on next launch.
- The store is single-process. Run one instance, or move to a real database before scaling out.
