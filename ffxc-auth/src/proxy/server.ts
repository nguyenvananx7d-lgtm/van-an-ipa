import http from "node:http";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadOrCreateAuthority } from "./pki.js";
import { createRelay, type Rule } from "./mitm.js";
import { buildMobileConfig } from "./profile.js";
import { type CaptureRecord, suggestRules } from "./suggest.js";

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

  if (path === "/") {
    res
      .writeHead(200, { "content-type": "text/html; charset=utf-8" })
      .end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px -apple-system;background:#0b0d0e;color:#eef1f0;padding:24px;max-width:760px">
<h1 style="font-size:19px">${profileName}</h1>
<p>Proxy <code>${publicHost}:${proxyPort}</code> · rules live: <b>${rules.length}</b></p>
<p><a style="color:#7dd3c0" href="/profile.mobileconfig">Install profile</a> ·
   <a style="color:#7dd3c0" href="/captures?limit=200">Capture</a> ·
   <a style="color:#7dd3c0" href="/suggest">Suggestions (raw)</a></p>
<p style="color:#8d9693">After installing, enable full trust under
Settings → General → About → Certificate Trust Settings. Then play one match;
suggestions appear below and can be applied without a restart.</p>
<h2 style="font-size:15px;margin-top:22px">Suggested rules</h2>
<div id="state" style="color:#7dd3c0;min-height:20px"></div>
<div id="list" style="color:#8d9693">loading…</div>
<script>
let active = [];
const state = document.getElementById('state');
const list = document.getElementById('list');
fetch('/rules').then(r => r.json()).then(r => { active = Array.isArray(r) ? r : []; }).catch(() => {});
fetch('/suggest').then(r => r.json()).then(data => {
  if (!data.count) {
    list.textContent = 'No candidate yet — play one match first.';
    return;
  }
  list.innerHTML = '';
  for (const s of data.suggestions) {
    const row = document.createElement('div');
    row.style = 'border:1px solid #24302e;border-radius:10px;padding:12px;margin:10px 0;color:#eef1f0';
    const head = document.createElement('div');
    head.innerHTML = '<b>' + s.host + s.path + '</b> <span style="color:#8d9693">score ' +
      s.score + ' · ' + s.calls + ' call(s) · ' + s.action + '</span>';
    const pre = document.createElement('pre');
    pre.style = 'white-space:pre-wrap;color:#9fb3ae;font-size:12px;margin:8px 0';
    pre.textContent = JSON.stringify(s.rule, null, 2);
    const button = document.createElement('button');
    button.textContent = 'Apply';
    button.style = 'background:#7dd3c0;color:#06110f;border:0;border-radius:8px;padding:7px 14px;font-weight:600';
    button.onclick = async () => {
      active = active.filter(x => !(x.host === s.rule.host && x.pathPattern === s.rule.pathPattern));
      active.push(s.rule);
      const response = await fetch('/rules', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(active)
      });
      state.textContent = response.ok
        ? 'Applied — ' + active.length + ' rule(s) live, no restart'
        : 'Apply failed';
    };
    row.append(head, pre, button);
    list.append(row);
  }
}).catch(error => { list.textContent = 'suggest failed: ' + error; });
</script>
<p style="color:#8d9693;margin-top:24px">Reasons, for reference: the client reports
<code>MD5_*</code>, <code>PMS_HOOK</code>, <code>NATIVE_RESULT</code> and
<code>GIN_CHECK_DATA_EMPTY_IOS</code>. A host that only shows up under
<code>app-measurement</code> or an ad domain is not a report channel — leave it alone.</p>
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
