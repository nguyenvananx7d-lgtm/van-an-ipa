# Relay — the proxy approach

The client used to cheat by writing an IFix patch into the game's container and
letting the game load it. That works, and it is also exactly what the game
checks: the patch replaces a method body, so the code the anti-cheat hashes,
scans for hooks and reports on is no longer the code it shipped.

This directory implements the other approach, the one the reference video shows:
**do not touch the client at all.** Intercept its traffic, and edit the report
instead of the program.

```
 iPhone                          relay (VPS)                     game backend
┌──────────┐   TLS to relay   ┌──────────────────┐   TLS upstream  ┌──────────┐
│ Free Fire│ ───────────────▶ │ 1299  MITM proxy │ ──────────────▶ │  servers │
│          │                  │  leaf per host   │                 │          │
│ trusted  │ ◀─────────────── │ rules + capture  │ ◀────────────── │          │
│ relay CA │                  │ 8080  admin      │                 │          │
└──────────┘                  └──────────────────┘                 └──────────┘
```

Because nothing runs inside the game process, there is no modified method, no
injected image and no foreign file in the container. The only thing the device
trusts is a certificate.

## What is here

| File | Role |
| --- | --- |
| `src/proxy/pki.ts` | CA on disk + on-demand leaf certificates per host |
| `src/proxy/mitm.ts` | CONNECT handling, TLS termination, forwarding, rules, capture |
| `src/proxy/profile.ts` | `.mobileconfig` builder: root CA + optional Wi-Fi proxy + IKEv2 tunnel |
| `src/proxy/server.ts` | entry point: proxy listener + admin (profile, capture viewer) |
| `scripts/proxy-selftest.ts` | end-to-end check with a local origin — no network, no device |

## Run it

```bash
cd ffxc-auth
npm install                      # node-forge
npm run relay:selftest           # must print PASS
npm run relay                    # proxy :1299, admin :8080
```

Environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `RELAY_PORT` | `1299` | proxy port the device points at |
| `RELAY_ADMIN_PORT` | `8080` | profile + capture endpoints |
| `RELAY_DATA_DIR` | `data` | CA and capture live here |
| `RELAY_CAPTURE` | `data/capture.jsonl` | capture log |
| `RELAY_RULES` | `data/rules.json` | rewrite rules; absent means capture-only |
| `RELAY_PUBLIC_HOST` | `127.0.0.1` | host printed in the profile/dashboard |
| `RELAY_WIFI_SSID` | — | when set, the profile also configures that network's HTTP proxy |
| `RELAY_VPN_SERVER` / `_REMOTE_ID` / `_USER` / `_PASSWORD` | — | when set, the profile carries an IKEv2 tunnel (needed on cellular) |

Admin endpoints: `/` dashboard, `/profile.mobileconfig`, `/ca.cer`,
`/captures?limit=200`.

## Device setup

1. Open `http://<relay>:8080/profile.mobileconfig` in Safari → Allow → the
   profile lands in Settings.
2. Settings → General → VPN & Device Management → install it.
3. Settings → General → About → **Certificate Trust Settings** → enable full
   trust for the relay CA. **This step cannot be automated**; without it every
   intercepted connection fails the TLS handshake.
4. Start the tunnel (or join the configured Wi-Fi) and launch the game.

If a page or the game refuses to connect after this, that is a certificate-pin
failure and it is the one thing that kills this approach for a given host — the
capture shows it as an upstream error, not as silence.

## Workflow: capture first, rewrite second

The game's anti-cheat endpoints and the shape of `check_info` live in native
code; the C# dump exposes the *reasons* it reports (`HackerPoolCdt`: `MD5_*`,
`PMS_HOOK`, `NATIVE_RESULT`, `GIN_CHECK_DATA_EMPTY_IOS`, …) but not a single URL
— verified by scanning all 1.15M dump lines. So:

1. Run with no rules (`data/rules.json` absent). Play one match.
2. `curl http://<relay>:8080/captures?limit=500` (or open it in a browser).
   Look for hosts that carry `check_info`, `gin`, `md5`, `anti`.
3. Write rules for exactly those requests, and only for those.

### Rules file

```json
[
  {
    "host": "example.anticheat.tld",
    "pathPattern": "^/report$",
    "action": "json-merge",
    "merge": { "check_info": "", "percent": 100 },
    "note": "force a clean report"
  },
  {
    "host": ".game.tld",
    "pathPattern": "^/track/",
    "action": "text-replace",
    "find": "\"flagged\":true",
    "replace": "\"flagged\":false"
  },
  { "host": "ads.example", "pathPattern": "^/", "action": "block" }
]
```

- `host` is exact, or a suffix when it starts with `.`; omitted matches all.
- `pathPattern` is a regular expression against the request path.
- `json-merge` merges top-level keys into a JSON **response**; `text-replace`
  does a literal substitution; `block` answers `204` locally.
- Every applied rule is recorded in the capture line as `applied: [...]`, so a
  rewrite is never silent.

Binary bodies (protobuf over TLS) are captured as `base64:` previews and
forwarded untouched — writing a field-level editor for them needs the schema,
which is the next step once the capture shows the framing.

## Limits, stated plainly

- **Certificate pinning** on any host defeats interpolation for that host. The
  relay reports it as an upstream TLS error; there is no silent fallback.
- **The trust toggle is manual.** A profile can install the CA; only the user
  can mark it trusted.
- **Cellular needs the tunnel.** A Wi-Fi proxy payload applies to one network;
  without IKEv2 configured the relay only sees traffic on that Wi-Fi.
- **Capture files are sensitive.** They contain game traffic, session tokens and
  identifiers. `data/` is git-ignored; never paste a capture into a chat or an
  issue.
- **This does not make a client-side cheat invisible.** It removes the code
  patch as the evidence. If a host pins, or if the report is signed with a key
  the client holds, the report cannot be rewritten and the approach fails for
  that host.
