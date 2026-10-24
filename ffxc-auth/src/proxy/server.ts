import http from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadOrCreateAuthority } from "./pki.js";
import { createRelay, type Rule } from "./mitm.js";
import { buildMobileConfig } from "./profile.js";

/**
 * Relay entry point.
 *
 * Two listeners, deliberately separate:
 *   - the proxy port, which the device's tunnel or Wi-Fi proxy points at;
 *   - the admin port, which serves the installable profile and the capture
 *     log. It is meant to sit behind the VPS reverse proxy / Caddy, not to be
 *     exposed directly.
 *
 * Nothing here decides what to rewrite. The relay runs in capture mode until a
 * rules file exists — the anti-cheat report format is only knowable from a
 * recorded session, so guessing rules before that would be building blind.
 */

const proxyPort = Number(process.env.RELAY_PORT ?? 1299);
const adminPort = Number(process.env.RELAY_ADMIN_PORT ?? 8080);
const dataDir = process.env.RELAY_DATA_DIR ?? "data";
const capturePath = process.env.RELAY_CAPTURE ?? join(dataDir, "capture.jsonl");
const rulesPath = process.env.RELAY_RULES ?? join(dataDir, "rules.json");
const publicHost = process.env.RELAY_PUBLIC_HOST ?? "127.0.0.1";
const profileName = process.env.RELAY_PROFILE_NAME ?? "Nimbus Relay";

function loadRules(): Rule[] {
  if (!existsSync(rulesPath)) return [];
  try {
    const parsed = JSON.parse(readFileSync(rulesPath, "utf8")) as Rule[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.error(`relay: rules file is not valid JSON — running in capture mode (${String(error)})`);
    return [];
  }
}

const ca = loadOrCreateAuthority(join(dataDir, "ca"));
const rules = loadRules();

const relay = createRelay({
  port: proxyPort,
  ca,
  capturePath,
  rules,
  log: (line) => console.log(line),
});

const profile = buildMobileConfig({
  ca,
  displayName: profileName,
  wifi: process.env.RELAY_WIFI_SSID
    ? {
        ssid: process.env.RELAY_WIFI_SSID,
        proxyHost: process.env.RELAY_WIFI_PROXY ?? publicHost,
        proxyPort,
      }
    : undefined,
  vpn:
    process.env.RELAY_VPN_SERVER && process.env.RELAY_VPN_USER && process.env.RELAY_VPN_PASSWORD
      ? {
          server: process.env.RELAY_VPN_SERVER,
          remoteIdentifier: process.env.RELAY_VPN_REMOTE_ID ?? process.env.RELAY_VPN_SERVER,
          username: process.env.RELAY_VPN_USER,
          password: process.env.RELAY_VPN_PASSWORD,
        }
      : undefined,
});

const admin = http.createServer((req, res) => {
  const path = (req.url ?? "/").split("?")[0];

  if (path === "/profile.mobileconfig") {
    res
      .writeHead(200, {
        "content-type": "application/x-apple-aspen-config",
        "content-disposition": 'attachment; filename="nimbus-relay.mobileconfig"',
      })
      .end(profile);
    return;
  }

  if (path === "/ca.cer") {
    const der = Buffer.from(ca.derBase64, "base64");
    res.writeHead(200, { "content-type": "application/x-x509-ca-cert" }).end(der);
    return;
  }

  if (path === "/captures") {
    const limit = Number(new URL(req.url ?? "/", "http://x").searchParams.get("limit") ?? 100);
    const lines = existsSync(capturePath)
      ? readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).slice(-limit)
      : [];
    const records = lines.map((line) => {
      try {
        return JSON.parse(line) as unknown;
      } catch {
        return { raw: line };
      }
    });
    res
      .writeHead(200, { "content-type": "application/json" })
      .end(JSON.stringify({ count: records.length, records }, null, 2));
    return;
  }

  if (path === "/") {
    res
      .writeHead(200, { "content-type": "text/html; charset=utf-8" })
      .end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px -apple-system;background:#0b0d0e;color:#eef1f0;padding:24px">
<h1 style="font-size:19px">${profileName}</h1>
<p>Proxy: <code>${publicHost}:${proxyPort}</code></p>
<p>Capture: <a style="color:#7dd3c0" href="/captures?limit=200">/captures</a></p>
<p>Install: <a style="color:#7dd3c0" href="/profile.mobileconfig">profile.mobileconfig</a></p>
<p style="color:#8d9693">After installing, enable full trust for the certificate under
Settings → General → About → Certificate Trust Settings.</p>
<h2 style="font-size:15px;margin-top:24px">Rules</h2>
<pre style="background:#14181a;padding:12px;border-radius:8px;overflow:auto">${JSON.stringify(rules, null, 2)}</pre>
</body>`);
    return;
  }

  res.writeHead(404, { "content-type": "text/plain" }).end("not found");
});

admin.listen(adminPort, () => {
  console.log(`relay: admin on ${adminPort}, proxy on ${proxyPort}, rules ${rules.length}`);
});

const shutdown = async () => {
  await relay.close();
  admin.close();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
