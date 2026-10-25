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
| `src/proxy/mitm.ts` | CONNECT handling, TLS termination, forwarding, rules, capture, raw passthrough |
| `src/proxy/profile.ts` | `.mobileconfig` builder: root CA + L2TP/IPsec or IKEv2 tunnel + proxy + web clip |
| `src/proxy/server.ts` | entry point: proxy listener + admin (profile, dashboard, menu, capture viewer) |
| `src/proxy/menu.ts` | the phone-sized control panel the profile's web clip opens |
| `deploy/l2tp/setup.sh` | strongswan + xl2tpd endpoint the profile points at |
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
| `RELAY_PASSTHROUGH` | — | comma-separated hosts spliced as raw TCP instead of intercepted |
| `RELAY_FEATURES` | `data/features.json` | which feature switches are on |
| `RELAY_PUBLIC_HOST` | `127.0.0.1` | host printed in the profile/dashboard |
| `RELAY_WIFI_SSID` | — | when set, the profile also configures that network's HTTP proxy |
| `RELAY_VPN_SERVER` | — | public address of the tunnel endpoint; absent = Wi-Fi-only relay |
| `RELAY_VPN_MODE` | `l2tp` | `l2tp` (shared secret) or `ikev2` (username/password) |
| `RELAY_L2TP_USER` / `_PASSWORD` / `RELAY_IPSEC_SECRET` | — | L2TP credentials; all three required |
| `RELAY_VPN_USER` / `_PASSWORD` / `_REMOTE_ID` | — | IKEv2 credentials |
| `RELAY_PROXY_IN_VPN` | `1` | put `Proxies` inside the VPN payload instead of teaching a manual entry |
| `RELAY_MENU_URL` / `RELAY_MENU_LABEL` | — | web clip URL + label; also enables `/menu` |
| `RELAY_CONSENT` | auto | overrides the install text iOS shows |
| `AUTH_URL` | `http://127.0.0.1:8787/api` | where `/menu/login` forwards the key |
| `AUTH_ADMIN_URL` / `AUTH_ADMIN_TOKEN` | `http://127.0.0.1:8787` / — | session liveness check + rule-write gate; empty token = open relay |

Admin endpoints: `/` dashboard, `/menu`, `/profile.mobileconfig`, `/ca.cer`,
`/captures?limit=200`.

## Why the profile looks like this

One file carries four payloads, in this order, and the order is the install
order a person actually follows:

| Payload | Why it exists |
| --- | --- |
| `com.apple.security.root` | The relay terminates TLS per host; without this certificate trusted, every intercepted connection fails the handshake. |
| `com.apple.vpn.managed` | A route to the relay that does not depend on which Wi-Fi the phone is on. Cellular matters: a match started on 4G would otherwise bypass the relay entirely. |
| `Proxies` (inside the VPN payload) | This is the part that is easy to get wrong. A proxy set on the Wi-Fi interface dies the moment the device leaves that network. A proxy **inside the VPN payload** lives exactly as long as the tunnel, on every interface, with no manual entry. |
| `com.apple.webClip.managed` | A control surface on the home screen without shipping, signing or sideloading an app. It is a bookmarked page, not a binary, so there is nothing to install over. |

The root certificate is the only thing the device has to be told to trust, and
that toggle is the one step no profile can perform.

## Device setup

1. Open `http(s)://<relay>/profile.mobileconfig` in Safari → Allow → the
   profile lands in Settings.
2. Settings → General → VPN & Device Management → install it.
3. Settings → General → About → **Certificate Trust Settings** → enable full
   trust for the relay CA. **This step cannot be automated**; without it every
   intercepted connection fails the TLS handshake.
4. Settings → VPN → connect the relay tunnel. The proxy is already inside it.
5. Launch the game. If the home-screen web clip was in the profile, it now
   opens the relay menu.

## Tunnel endpoint

`deploy/l2tp/setup.sh` installs and configures strongswan + xl2tpd on the relay
host, enables forwarding, NATs the client pool out of the default interface,
and opens only UDP 500/4500/1701 plus the proxy port **for the pool**:

```bash
VPN_USER=... VPN_PASSWORD='...' IPSEC_PSK='...' RELAY_PORT=1299 \
  bash deploy/l2tp/setup.sh
```

The same three values go into `.env` as `RELAY_L2TP_USER`,
`RELAY_L2TP_PASSWORD`, `RELAY_IPSEC_SECRET`. `RELAY_VPN_SERVER` is the box's
public IP or hostname.

If a page or the game refuses to connect after this, that is a certificate-pin
failure and it is the one thing that kills this approach for a given host — the
capture shows it as an upstream error, not as silence.

## The menu

`/menu` is the page the web clip opens, and it is three screens in one document:

| Screen | What it shows | Where the values come from |
| --- | --- | --- |
| Login | key input | `POST /menu/login` → relay → auth backend `/api` |
| Panel | session key, device key, iOS, rule count, ping | `payload.session`, a per-browser id, `navigator.userAgent`, `/state` round-trip |
| Web menu | rule switches + suggestions | the relay's live rule array |

The panel is the "proof of life" card: the session key is the token the auth
backend issued, and the three right-hand values are measured in the browser, so
a broken relay shows as a red ping rather than a green badge.

**Session validation never uses the heartbeat endpoint.** Reusing it would push
the app's sequence forward and the next app poll would come back
`replayDetected`. The relay instead asks `/admin/api/sessions` with the admin
token and checks the token is present and unexpired — a read with no side
effects.

Gating:

- `AUTH_ADMIN_TOKEN` empty → login screen is skipped, `/rules` is open. Correct
  for a laptop-and-one-phone setup.
- `AUTH_ADMIN_TOKEN` set → `/rules` requires either `x-menu-session` (a live
  licence session from the menu) or `x-admin-token`. Open the dashboard once as
  `/?token=<ADMIN_TOKEN>`; it keeps the token in `sessionStorage` and sends it
  on every write.

The device key is a random 128-bit id in `localStorage`, not the phone's UDID —
a web page cannot read the hardware identifier, and pretending otherwise would
make the card lie. It is the handle the auth backend binds the licence to, so
clearing Safari data means a new binding (`reset-devices` on the console).

## Passthrough hosts

A phone's HTTP proxy sees **every** connection, not only HTTP. Game transports
that speak their own framed protocol inside TLS break the moment they are
terminated, and rewriting them buys nothing. `RELAY_PASSTHROUGH` lists hosts
that are spliced byte-for-byte instead:

```bash
RELAY_PASSTHROUGH=voice.example.tld,.media.example.tld
```

A leading dot is a suffix match. The capture records `passthrough: true` for
these, so the log still shows the session happened.

## Features (the menu's switches)

A feature is a named bundle of rules, not a UI flag. Switching it on installs
those rules into the live array; the next request is already blocked. Switching
it off removes exactly those rules — manual rules carry no `feature` tag, so
they survive untouched.

| Id | What it does | Risk |
| --- | --- | --- |
| `telemetry` | blocks Firebase, AppsFlyer, Adjust, Amplitude, Mixpanel, Segment, Branch, Google Analytics (14 hosts) | none observed |
| `ads` | blocks the game's ad host and Unity Ads | in-game rewards may not load |
| `security` | blocks the two known security/report hosts | can break login — that path also validates the session on some builds |

State lives in `data/features.json` (`RELAY_FEATURES` to move it) and is
re-applied to the rule file on boot, so a restart keeps the switches where they
were. Every capture line records which features acted (`features: ["telemetry"]`),
and the menu's counter is just the number of those lines.

Proof that a switch changes traffic, not just a boolean:

```bash
npm run relay:feature-test
# feature selftest: PASS
#   off=200 on=204 off-again=200
#   capture: blocked=true features=["telemetry"]
```

The test drives a real CONNECT → TLS → request through the relay with the
feature off, on, and off again, and reads the capture line the counter uses.

## Workflow: capture, then one click

The game's anti-cheat endpoints and the shape of `check_info` live in native
code; the C# dump exposes the *reasons* it reports (`HackerPoolCdt`: `MD5_*`,
`PMS_HOOK`, `NATIVE_RESULT`, `GIN_CHECK_DATA_EMPTY_IOS`, …) but not a single URL
— verified by scanning all 1.15M dump lines. So:

1. Run with no rules (`data/rules.json` absent). Play one match.
2. Open the dashboard (`http://<relay>:8080/`). It reads the capture, scores
   every host+path on path and body evidence, and lists candidates with the
   rule it would apply already filled in — report-shaped JSON fields
   (`check_info`, `md5`, …) pre-set to their neutral value.
3. Press **Apply**. The rule goes live immediately: the relay reads its rule
   list per request, so there is no restart and the current tunnel survives.

Nothing is applied silently: every capture line records `applied: [...]`, and
`/rules` returns the live set. `POST /rules` with a JSON array replaces it; the
file is rewritten at the same time, so a restart keeps the rules.

If the dashboard shows nothing, the session did not reach a report channel —
usually the tunnel was not up, or the profile's certificate was installed but
not trusted.

### Rules file (what the dashboard writes)

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
