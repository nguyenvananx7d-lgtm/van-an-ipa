import http from "node:http";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadOrCreateAuthority } from "./pki.js";
import { createRelay, type Rule } from "./mitm.js";
import { buildMobileConfig } from "./profile.js";
import { type CaptureRecord, suggestRules } from "./suggest.js";
import { renderDashboard } from "./dashboard.js";

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

function readCaptures(limit: number): CaptureRecord[] {
  if (!existsSync(capturePath)) return [];
  const lines = readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).slice(-limit);
  const records: CaptureRecord[] = [];
  for (const line of lines) {
    try {
      records.push(JSON.parse(line) as CaptureRecord);
    } catch {
      // A torn last line from a crash is expected; skip it.
    }
  }
  return records;
}

function countCaptures(): number {
  if (!existsSync(capturePath)) return 0;
  return readFileSync(capturePath, "utf8").split("\n").filter(Boolean).length;
}

function applyRules(next: Rule[]): void {
  rules.length = 0;
  rules.push(...next);
  writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
  relay.setRules(rules);
}

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

  if (path === "/suggest") {
    const records = readCaptures(4000);
    const suggestions = suggestRules(records);
    res
      .writeHead(200, { "content-type": "application/json" })
      .end(JSON.stringify({ captures: records.length, count: suggestions.length, suggestions }, null, 2));
    return;
  }

  if (path === "/rules") {
    if (req.method === "POST") {
      const chunks: Buffer[] = [];
      req.on("data", (chunk: Buffer) => {
        chunks.push(chunk);
        if (chunks.reduce((total, part) => total + part.length, 0) > 512 * 1024) {
          res.writeHead(413).end("rules body too large");
          req.destroy();
        }
      });
      req.on("end", () => {
        try {
          const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
          const next = Array.isArray(parsed)
            ? (parsed as Rule[])
            : ((parsed as { rules?: Rule[] }).rules ?? []);
          if (!Array.isArray(next) || next.some((rule) => typeof rule.pathPattern !== "string")) {
            res.writeHead(400, { "content-type": "application/json" }).end('{"error":"invalid rules"}');
            return;
          }
          applyRules(next);
          res
            .writeHead(200, { "content-type": "application/json" })
            .end(JSON.stringify({ applied: next.length }));
        } catch (error) {
          res.writeHead(400, { "content-type": "application/json" }).end(
            JSON.stringify({ error: String(error) }),
          );
        }
      });
      return;
    }
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(rules, null, 2));
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

  // One endpoint for everything the page renders, so the client does not have to
  // orchestrate four requests and get the order wrong.
  if (path === "/state") {
    const records = readCaptures(4000);
    const view = {
      name: profileName,
      publicHost,
      proxyPort,
      adminPort,
      rules,
      captures: { total: countCaptures(), recent: records.slice(-15).reverse() },
      suggestions: suggestRules(records),
    };
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(view));
    return;
  }

  if (path === "/captures/clear" && req.method === "POST") {
    writeFileSync(capturePath, "");
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ cleared: true }));
    return;
  }

  if (path === "/") {
    const records = readCaptures(4000);
    res
      .writeHead(200, { "content-type": "text/html; charset=utf-8" })
      .end(
        renderDashboard({
          name: profileName,
          publicHost,
          proxyPort,
          adminPort,
          rules,
          captures: { total: countCaptures(), recent: records.slice(-15).reverse() },
          suggestions: suggestRules(records),
        }),
      );
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
