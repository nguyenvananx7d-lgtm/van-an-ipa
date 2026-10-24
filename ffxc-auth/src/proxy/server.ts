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

  if (path === "/") {
    res
      .writeHead(200, { "content-type": "text/html; charset=utf-8" })
      .end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px -apple-system;background:#0b0d0e;color:#eef1f0;padding:22px;max-width:820px;line-height:1.55">
<h1 style="font-size:20px;margin:0 0 6px">${profileName}</h1>
<p style="color:#9fb3ae;margin:0 0 16px">Đây là <b>bảng điều khiển relay</b>, không phải chỗ bật cheat.
Cheat vẫn nằm trong app trên điện thoại. Relay chỉ đứng giữa game và server game để
sửa báo cáo anti-cheat trên đường truyền — nên game không thấy code nào bị sửa.</p>

<div style="background:#14181a;border:1px solid #24302e;border-radius:12px;padding:14px 16px;margin:0 0 18px">
  <div>Proxy: <code style="color:#7dd3c0">${publicHost}:${proxyPort}</code></div>
  <div>Rule đang sống: <b>${rules.length}</b> · Capture: <b>${countCaptures()}</b> dòng</div>
</div>

<h2 style="font-size:15px;margin:18px 0 8px">4 bước</h2>
<ol style="margin:0 0 18px;padding-left:20px;color:#cfe0db">
  <li>Bấm <a style="color:#7dd3c0" href="/profile.mobileconfig">Install profile</a> bằng Safari trên điện thoại.</li>
  <li>Settings → General → About → Certificate Trust Settings → bật full trust cho CA của relay.</li>
  <li>Chơi <b>một trận bình thường</b> (chưa sửa gì) rồi quay lại đây.</li>
  <li>Bấm <b>Apply</b> ở rule được gợi ý bên dưới. Rule sống ngay, không cần restart.</li>
</ol>

<h2 style="font-size:15px;margin:18px 0 8px">Rule gợi ý</h2>
<div id="state" style="color:#7dd3c0;min-height:20px;margin-bottom:6px"></div>
<div id="list" style="color:#8d9693">đang tải…</div>
<p style="color:#8d9693;margin-top:18px;font-size:13px">
Nếu danh sách trống: chưa có traffic đi qua relay. Kiểm tra tunnel/proxy đã bật,
cert đã trust, rồi chơi thêm một trận. Xem thô ở
<a style="color:#7dd3c0" href="/captures?limit=200">/captures</a>.
</p>
<script>
let active = [];
const state = document.getElementById('state');
const list = document.getElementById('list');
fetch('/rules').then(r => r.json()).then(r => { active = Array.isArray(r) ? r : []; }).catch(() => {});
fetch('/suggest').then(r => r.json()).then(data => {
  if (!data.count) {
    list.textContent = 'Chưa có ứng viên nào — chơi một trận trước.';
    return;
  }
  list.innerHTML = '';
  for (const s of data.suggestions) {
    const row = document.createElement('div');
    row.style = 'border:1px solid #24302e;border-radius:12px;padding:14px;margin:10px 0;color:#eef1f0';
    const head = document.createElement('div');
    head.innerHTML = '<b>' + s.host + s.path + '</b><br><span style="color:#8d9693">score ' +
      s.score + ' · ' + s.calls + ' lần gọi · ' + s.action + '</span>';
    const pre = document.createElement('pre');
    pre.style = 'white-space:pre-wrap;color:#9fb3ae;font-size:12px;margin:10px 0;background:#14181a;padding:10px;border-radius:8px';
    pre.textContent = JSON.stringify(s.rule, null, 2);
    const button = document.createElement('button');
    button.textContent = 'Apply';
    button.style = 'background:#7dd3c0;color:#06110f;border:0;border-radius:9px;padding:9px 16px;font-weight:700';
    button.onclick = async () => {
      active = active.filter(x => !(x.host === s.rule.host && x.pathPattern === s.rule.pathPattern));
      active.push(s.rule);
      const response = await fetch('/rules', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(active)
      });
      state.textContent = response.ok
        ? 'Đã áp — ' + active.length + ' rule đang sống, không cần restart'
        : 'Áp thất bại';
    };
    row.append(head, pre, button);
    list.append(row);
  }
}).catch(error => { list.textContent = 'suggest lỗi: ' + error; });
</script>
<p style="color:#8d9693;margin-top:22px;font-size:13px">
Vì sao phải sửa: client gửi lên các mã <code>MD5_*</code>, <code>PMS_HOOK</code>,
<code>NATIVE_RESULT</code>, <code>GIN_CHECK_DATA_EMPTY_IOS</code>. Host nào chỉ hiện
dưới <code>app-measurement</code> hay domain quảng cáo thì <b>không phải</b> kênh báo cáo — để yên.
</p>
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
