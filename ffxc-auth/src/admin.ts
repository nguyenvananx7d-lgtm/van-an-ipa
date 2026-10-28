import type { IncomingMessage, ServerResponse } from "node:http";
import { randomBytes } from "node:crypto";
import { config } from "./config.js";
import { asNumber, asString, readJson, sendHtml, sendJson } from "./http.js";
import {
  hashPassword,
  MAX_DEVICE_RESETS_PER_DAY,
  resetsUsedToday,
  utcDay,
  type LicenseRecord,
  type Store,
} from "./store.js";

const nowSec = (): number => Math.floor(Date.now() / 1000);

/** 12 characters from an alphabet without look-alikes, easy to read aloud. */
function generatePassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const bytes = randomBytes(12);
  let out = "";
  for (let i = 0; i < bytes.length; i += 1) out += alphabet[bytes[i]! % alphabet.length];
  return out;
}

interface LicenseView {
  key: string;
  plan: string;
  status: string;
  expiresAt: number | null;
  expiresAtISO: string | null;
  expired: boolean;
  maxDevices: number;
  deviceCount: number;
  note: string;
  createdAt: number;
  hasPassword: boolean;
  resetsToday: number;
  devices: Array<{
    hwid: string;
    mac: string;
    deviceName: string;
    model: string;
    iosVersion: string;
    firstSeen: number;
    lastSeen: number;
    online: boolean;
  }>;
}

function view(license: LicenseRecord, activeHwids: Set<string>): LicenseView {
  const devices = Object.values(license.devices).map((d) => ({
    hwid: d.hwid,
    mac: d.mac,
    deviceName: d.deviceName,
    model: d.model,
    iosVersion: d.iosVersion,
    firstSeen: d.firstSeen,
    lastSeen: d.lastSeen,
    online: activeHwids.has(d.hwid),
  }));
  return {
    key: license.key,
    plan: license.plan,
    status: license.status,
    expiresAt: license.expiresAt,
    expiresAtISO: license.expiresAt === null ? null : new Date(license.expiresAt * 1000).toISOString(),
    expired: license.expiresAt !== null && license.expiresAt < nowSec(),
    maxDevices: license.maxDevices,
    deviceCount: devices.length,
    note: license.note,
    createdAt: license.createdAt,
    hasPassword: Boolean(license.passwordHash),
    resetsToday: resetsUsedToday(license),
    devices,
  };
}

export class Admin {
  constructor(private readonly store: Store) {}

  private authorized(req: IncomingMessage, url: URL): boolean {
    const header = asString(req.headers["x-admin-token"]);
    const query = url.searchParams.get("token") ?? "";
    const supplied = header || query;
    return config.adminToken.length > 0 && supplied === config.adminToken;
  }

  async handle(req: IncomingMessage, res: ServerResponse, url: URL): Promise<void> {
    // The console page itself carries no secrets: serve it unauthenticated so the
    // built-in token gate can prompt for a token. Only /admin/api/* is token-gated.
    if (req.method === "GET" && (url.pathname === "/admin" || url.pathname === "/admin/")) {
      sendHtml(res, ADMIN_HTML);
      return;
    }
    if (!this.authorized(req, url)) {
      sendJson(res, 401, { error: "unauthorized" });
      return;
    }
    await this.api(req, res, url);
  }

  private activeHwids(): Set<string> {
    const now = nowSec();
    const set = new Set<string>();
    for (const session of this.store.allSessions()) {
      if (session.expiresAt >= now) set.add(session.hwid);
    }
    return set;
  }

  private async api(req: IncomingMessage, res: ServerResponse, url: URL): Promise<void> {
    const parts = url.pathname.split("/").filter(Boolean); // ["admin","api",...]
    const method = req.method ?? "GET";

    if (parts[2] === "sessions") {
      if (method === "GET" && parts.length === 3) {
        const now = nowSec();
        sendJson(res, 200, {
          sessions: this.store.allSessions().map((s) => {
            const license = this.store.getLicense(s.key);
            return {
              token: s.token,
              key: s.key,
              hwid: s.hwid,
              sequence: s.sequence,
              lastSeenAt: s.lastSeenAt,
              expiresAt: s.expiresAt,
              expired: s.expiresAt < now,
              // Read-only facts the relay's menu panel paints after a boot
              // session. Kept additive so older admin clients ignore them.
              plan: license?.plan ?? null,
              expiresAtISO: license?.expiresAt
                ? new Date(license.expiresAt * 1000).toISOString()
                : null,
              resetRemaining: license
                ? Math.max(0, MAX_DEVICE_RESETS_PER_DAY - resetsUsedToday(license))
                : 0,
            };
          }),
        });
        return;
      }
      if (method === "DELETE" && parts.length === 4) {
        await this.store.removeSession(parts[3]!);
        sendJson(res, 200, { ok: true });
        return;
      }
    }

    if (parts[2] !== "keys") {
      sendJson(res, 404, { error: "not_found" });
      return;
    }

    // /admin/api/keys
    if (parts.length === 3) {
      if (method === "GET") {
        const active = this.activeHwids();
        sendJson(res, 200, { keys: this.store.allLicenses().map((l) => view(l, active)) });
        return;
      }
      if (method === "POST") {
        const body = (await readJson(req)) ?? {};
        const customKeys = Array.isArray(body.keys)
          ? body.keys.filter((k): k is string => typeof k === "string" && k.trim().length > 0)
          : [];
        const count = Math.min(500, Math.max(1, asNumber(body.count, 1)));
        const days = asNumber(body.expiresInDays, 0);
        const maxDevices = Math.max(1, asNumber(body.maxDevices, 1));
        const requestedPassword = asString(body.password);
        if (requestedPassword && (requestedPassword.length < 8 || requestedPassword.length > 128)) {
          sendJson(res, 400, { error: "invalid_password" });
          return;
        }
        const password = requestedPassword || generatePassword();
        try {
          const made = this.store.createLicenses({
            plan: asString(body.plan) || "pro",
            expiresAt: days > 0 ? nowSec() + Math.round(days * 86_400) : null,
            maxDevices,
            note: asString(body.note),
            count,
            keys: customKeys,
            password,
          });
          sendJson(res, 201, { keys: made.map((l) => view(l, new Set())), password });
        } catch (err) {
          const message = err instanceof Error ? err.message : "error";
          const cut = message.indexOf(":");
          const code = cut === -1 ? message : message.slice(0, cut);
          const key = cut === -1 ? "" : message.slice(cut + 1);
          if (code === "key_exists") {
            sendJson(res, 409, { error: "key_exists", key });
          } else {
            sendJson(res, 400, { error: "invalid_key", key });
          }
        }
        return;
      }
    }

    // /admin/api/keys/:key
    const key = parts[3] ? decodeURIComponent(parts[3]) : "";
    const license = key ? this.store.getLicense(key) : undefined;
    if (!license) {
      sendJson(res, 404, { error: "not_found" });
      return;
    }

    if (parts.length === 4) {
      if (method === "GET") {
        sendJson(res, 200, view(license, this.activeHwids()));
        return;
      }
      if (method === "DELETE") {
        await this.store.removeLicense(license.key);
        sendJson(res, 200, { ok: true });
        return;
      }
    }

    if (parts.length === 5) {
      const action = parts[4];
      if (method === "POST" && action === "revoke") {
        license.status = "revoked";
        await this.store.saveLicense(license);
        sendJson(res, 200, view(license, this.activeHwids()));
        return;
      }
      if (method === "POST" && action === "restore") {
        license.status = "active";
        await this.store.saveLicense(license);
        sendJson(res, 200, view(license, this.activeHwids()));
        return;
      }
      if (method === "POST" && action === "reset-devices") {
        for (const s of this.store.allSessions()) {
          if (s.key === license.key) await this.store.removeSession(s.token);
        }
        license.devices = {};
        license.resetDay = utcDay();
        license.resetCount = 0;
        await this.store.saveLicense(license);
        sendJson(res, 200, view(license, new Set()));
        return;
      }
      if (method === "POST" && action === "password") {
        const body = (await readJson(req)) ?? {};
        const password = asString(body.password);
        if (password.length < 8 || password.length > 128) {
          sendJson(res, 400, { error: "invalid_password" });
          return;
        }
        const credential = hashPassword(password);
        license.passwordHash = credential.hash;
        license.passwordSalt = credential.salt;
        await this.store.saveLicense(license);
        sendJson(res, 200, { ok: true, hasPassword: true });
        return;
      }
    }

    if (method === "DELETE" && parts.length === 6 && parts[4] === "devices") {
      const hwid = decodeURIComponent(parts[5]!);
      await this.store.removeDevice(license.key, hwid);
      sendJson(res, 200, view(license, this.activeHwids()));
      return;
    }

    sendJson(res, 404, { error: "not_found" });
  }
}

const ADMIN_HTML = `<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%233699ff'/%3E%3Ctext x='16' y='23' font-size='19' font-family='Arial' font-weight='bold' fill='white' text-anchor='middle'%3EV%3C/text%3E%3C/svg%3E">
<title>Vortex Arena — License Panel</title>
<style>
  :root{
    --bg:#151521; --side:#1e1e2d; --card:#1e1e2d; --head:#1a1a29; --well:#151521;
    --line:#2b2b40; --line2:#35354d;
    --title:#ffffff; --text:#a2a3b7; --faint:#6b6c86;
    --accent:#3699ff; --accent-d:#187de4;
    --good:#1bc5bd; --warn:#ffa800; --bad:#f64e60; --purple:#8950fc;
    --r:12px;
    --shadow:0 2px 8px rgba(0,0,0,.35);
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{min-height:100vh;background:var(--bg);color:var(--text);
    font:13.5px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    -webkit-font-smoothing:antialiased}
  a{color:var(--accent);text-decoration:none}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  .spacer{flex:1}
  .dim{color:var(--faint)}
  ::selection{background:rgba(54,153,255,.35)}

  .btn{appearance:none;cursor:pointer;font:inherit;font-size:12.5px;font-weight:600;
    border:1px solid var(--line2);background:#23233a;color:#c5c8d8;padding:8px 13px;border-radius:8px;
    transition:.15s;display:inline-flex;align-items:center;justify-content:center;gap:7px;white-space:nowrap}
  .btn:hover{border-color:var(--accent);color:#fff}
  .btn:active{transform:translateY(1px)}
  .btn.primary{background:var(--accent);border-color:var(--accent);color:#fff;box-shadow:0 6px 16px -8px rgba(54,153,255,.9)}
  .btn.primary:hover{background:var(--accent-d);border-color:var(--accent-d)}
  .btn.danger{color:var(--bad)}
  .btn.danger:hover{border-color:var(--bad);background:rgba(246,78,96,.1)}
  .btn.sm{padding:5px 9px;font-size:11.5px;border-radius:7px}
  .btn.icon{background:transparent;border-color:transparent;color:var(--text);padding:7px}
  .btn.icon:hover{color:#fff;background:#23233a}
  .btn.copied{border-color:var(--good);color:var(--good)}
  .btn.spin svg{animation:spin .7s linear infinite}
  @keyframes spin{to{transform:rotate(360deg)}}

  input,select{font:inherit;color:#dfe1ee;background:var(--well);border:1px solid var(--line2);
    border-radius:8px;padding:9px 11px;width:100%;transition:.15s}
  input::placeholder{color:#5f6079}
  input:focus,select:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(54,153,255,.18)}
  label.f{display:block;font-size:11.5px;color:var(--text);margin:0 0 6px;font-weight:600}
  .field-hint{font-size:11px;color:var(--faint);margin-top:5px}

  .layout{display:flex;min-height:100vh}
  .sidebar{width:236px;flex:none;background:var(--side);border-right:1px solid var(--line);
    display:flex;flex-direction:column;position:fixed;top:0;bottom:0;left:0;z-index:40;transition:transform .2s ease}
  .side-brand{display:flex;align-items:center;gap:11px;padding:16px 18px;border-bottom:1px solid var(--line)}
  .logo{width:34px;height:34px;border-radius:9px;flex:none;display:grid;place-items:center;
    background:linear-gradient(135deg,var(--accent),var(--purple));color:#fff;font-weight:800;font-size:15px;
    box-shadow:0 6px 16px -8px rgba(54,153,255,.9)}
  .side-brand b{display:block;color:var(--title);font-size:13.5px;line-height:1.2}
  .side-brand small{color:var(--faint);font-size:10px;letter-spacing:.12em;text-transform:uppercase}
  nav{padding:12px 10px;display:flex;flex-direction:column;gap:3px;flex:1;overflow:auto}
  .nav-cap{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:var(--faint);padding:14px 10px 6px}
  .nav-item{display:flex;align-items:center;gap:11px;padding:10px 12px;border-radius:8px;cursor:pointer;
    color:var(--text);font-size:13px;font-weight:500;transition:.12s;position:relative}
  .nav-item svg{opacity:.8;transition:.12s}
  .nav-item:hover{background:#23233a;color:#fff}
  .nav-item:hover svg{opacity:1}
  .nav-item.active{background:var(--accent);color:#fff;box-shadow:0 8px 20px -12px rgba(54,153,255,1)}
  .nav-item.active svg{opacity:1}
  .nav-badge{margin-left:auto;background:rgba(255,255,255,.18);color:#fff;border-radius:99px;
    font-size:10.5px;font-weight:700;padding:1px 7px}
  .side-foot{padding:14px 16px;border-top:1px solid var(--line);display:flex;flex-direction:column;gap:9px}
  .side-user{display:flex;align-items:center;gap:10px;font-size:11.5px;color:var(--faint)}
  .side-user .av{width:28px;height:28px;border-radius:8px;background:#23233a;display:grid;place-items:center;color:var(--text)}
  .conn{display:inline-flex;align-items:center;gap:8px;font-size:12px;color:var(--text);
    border:1px solid var(--line2);border-radius:999px;padding:5px 11px;background:var(--well)}
  .dot{width:7px;height:7px;border-radius:50%;background:currentColor;flex:none}
  .pulse{animation:pulse 1.8s ease-in-out infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}

  .main{flex:1;min-width:0;margin-left:236px;display:flex;flex-direction:column}
  .topbar{position:sticky;top:0;z-index:30;display:flex;align-items:center;gap:10px;padding:12px 22px;
    background:rgba(26,26,41,.92);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
  .topbar h1{font-size:16px;color:var(--title);margin:0;font-weight:600;white-space:nowrap}
  .updated{font-size:11px;color:var(--faint);white-space:nowrap}
  .burger{display:none}
  .search{max-width:250px}
  .content{padding:22px;max-width:1240px;width:100%}
  .backdrop{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:35}
  .section{animation:fade .2s ease}
  @keyframes fade{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}

  .stats{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px}
  .stat{background:var(--card);border:1px solid var(--line);border-radius:var(--r);
    padding:18px;display:flex;align-items:center;gap:14px;transition:.18s;box-shadow:var(--shadow)}
  .stat:hover{border-color:var(--line2);transform:translateY(-2px)}
  .stat-main{flex:1;min-width:0}
  .stat-label{font-size:11.5px;color:var(--text);font-weight:500}
  .stat-value{font-size:25px;color:var(--title);font-weight:700;margin-top:4px;letter-spacing:-.02em}
  .stat-sub{font-size:10.5px;color:var(--faint);margin-top:2px}
  .stat-ic{width:44px;height:44px;border-radius:11px;display:grid;place-items:center;flex:none}
  .ic-blue{background:rgba(54,153,255,.12);color:var(--accent)}
  .ic-green{background:rgba(27,197,189,.12);color:var(--good)}
  .ic-yellow{background:rgba(255,168,0,.12);color:var(--warn)}
  .ic-purple{background:rgba(137,80,252,.14);color:var(--purple)}

  .cols{display:grid;grid-template-columns:1.7fr 1fr;gap:20px;align-items:start}
  .card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);margin-bottom:20px;
    box-shadow:var(--shadow);overflow:hidden}
  .cols .card{margin-bottom:0}
  .card-h{display:flex;align-items:center;gap:10px;padding:15px 18px;border-bottom:1px solid var(--line);flex-wrap:wrap}
  .card-h h2{margin:0;font-size:14.5px;font-weight:600;color:var(--title)}
  .card-h .sub{font-size:11.5px;color:var(--faint)}
  .card-b{padding:0}
  .card-pad{padding:18px}

  table{width:100%;border-collapse:collapse}
  th,td{text-align:left;padding:12px 16px;border-bottom:1px solid var(--line);vertical-align:middle}
  th{color:var(--faint);font-weight:600;font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;
    background:var(--head);white-space:nowrap;position:sticky;top:0}
  tbody tr:hover{background:rgba(255,255,255,.022)}
  tbody tr:last-child td{border-bottom:none}
  td.keycell{white-space:nowrap}
  .row-actions{display:flex;gap:6px;justify-content:flex-end;flex-wrap:nowrap}
  .chev{display:inline-block;transition:.15s;margin-left:2px}
  .chev.open{transform:rotate(180deg)}
  .devrow td{background:#171725;padding:0}
  .devwrap{padding:14px 16px}
  .devwrap h4{margin:0 0 10px;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--faint)}

  .badge{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:600;
    padding:4px 9px;border-radius:6px;white-space:nowrap}
  .badge.active{background:rgba(27,197,189,.14);color:var(--good)}
  .badge.revoked{background:rgba(246,78,96,.14);color:var(--bad)}
  .badge.expired{background:rgba(255,168,0,.14);color:var(--warn)}
  .badge.deleted{background:rgba(107,108,134,.18);color:var(--text)}
  .badge.plain{background:rgba(107,108,134,.18);color:var(--text)}

  .tabs{display:flex;gap:6px;padding:12px 18px;border-bottom:1px solid var(--line);flex-wrap:wrap}
  .tab{cursor:pointer;font-size:12px;font-weight:600;color:var(--text);padding:6px 12px;border-radius:7px;border:1px solid transparent;transition:.15s}
  .tab:hover{background:#23233a;color:#fff}
  .tab.active{background:rgba(54,153,255,.14);color:var(--accent);border-color:rgba(54,153,255,.35)}
  .tab .n{opacity:.7;font-weight:500;margin-left:4px}

  .seg{display:grid;grid-template-columns:1fr 1fr;gap:10px}
  .seg-btn{appearance:none;cursor:pointer;font:inherit;text-align:left;color:var(--text);background:var(--well);
    border:1px solid var(--line2);border-radius:10px;padding:11px 13px;transition:.15s}
  .seg-btn:hover{border-color:var(--accent);color:#fff}
  .seg-btn.active{border-color:var(--accent);background:rgba(54,153,255,.12);color:#fff}
  .seg-btn b{display:block;font-size:13.5px;font-weight:700;color:var(--title)}
  .seg-btn small{display:block;font-size:11px;color:var(--faint);margin-top:2px}
  .pbadge{display:inline-flex;align-items:center;font-size:11px;font-weight:700;letter-spacing:.02em;
    padding:4px 9px;border-radius:6px;text-transform:capitalize}
  .pbadge.lite{background:rgba(54,153,255,.14);color:#5aa9ff}
  .pbadge.pro{background:rgba(137,80,252,.16);color:#a98bff}
  .pbadge.other{background:rgba(107,108,134,.18);color:var(--text)}
  .plan-filter{width:auto;max-width:150px}
  .keyrow{display:flex;align-items:stretch}
  .keyrow .pfx{display:flex;align-items:center;padding:0 11px;font-weight:700;color:var(--accent);
    background:rgba(54,153,255,.10);border:1px solid var(--line2);border-right:0;border-radius:8px 0 0 8px;
    font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  .keyrow input{border-radius:0 8px 8px 0}

  .empty{padding:40px 16px;text-align:center;color:var(--faint)}
  .empty-ic{width:46px;height:46px;border-radius:13px;background:rgba(107,108,134,.14);display:grid;
    place-items:center;margin:0 auto 12px;color:var(--faint)}

  .plans{padding:16px 18px;display:flex;flex-direction:column;gap:14px}
  .plan{display:flex;flex-direction:column;gap:7px}
  .plan-top{display:flex;justify-content:space-between;font-size:12px;color:var(--text)}
  .plan-top b{color:var(--title)}
  .bar{height:7px;border-radius:99px;background:#23233a;overflow:hidden}
  .bar span{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,var(--accent),var(--purple))}

  .gate{position:fixed;inset:0;z-index:50;display:none;align-items:center;justify-content:center;padding:20px;
    background:radial-gradient(900px 500px at 50% -10%, rgba(54,153,255,.18), transparent 60%), var(--bg)}
  .gate-card{width:100%;max-width:400px;background:var(--card);border:1px solid var(--line);border-radius:14px;
    padding:28px;box-shadow:0 30px 70px -30px #000}
  .gate-card .ic{width:50px;height:50px;border-radius:13px;display:grid;place-items:center;margin:0 auto 16px;
    background:rgba(54,153,255,.14);color:var(--accent)}
  .gate-card h1{font-size:18px;color:var(--title);margin:0 0 6px;text-align:center}
  .gate-card p.sub{margin:0 0 20px;text-align:center;color:var(--text);font-size:12.5px}
  .hint{margin:14px 0 0;font-size:11.5px;color:var(--faint);text-align:center}
  .err{color:var(--bad);font-size:12px;margin-top:10px;min-height:16px;text-align:center}

  .overlay{position:fixed;inset:0;background:rgba(8,8,16,.72);z-index:70;display:none;
    align-items:flex-start;justify-content:center;padding:60px 20px 20px;overflow:auto}
  .overlay.on{display:flex}
  .modal{width:100%;max-width:460px;background:var(--card);border:1px solid var(--line2);border-radius:14px;
    box-shadow:0 30px 70px -30px #000;animation:fade .16s ease}
  .modal.sm{max-width:390px}
  .modal-h{display:flex;align-items:center;padding:16px 18px;border-bottom:1px solid var(--line)}
  .modal-h h3{margin:0;font-size:14.5px;color:var(--title);font-weight:600}
  .modal-b{padding:18px}
  .modal-f{display:flex;justify-content:flex-end;gap:10px;padding:15px 18px;border-top:1px solid var(--line)}
  .grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
  .grid2 .full{grid-column:1/-1}

  .toasts{position:fixed;right:16px;top:16px;display:flex;flex-direction:column;gap:10px;z-index:90}
  .toast{min-width:220px;max-width:340px;padding:12px 14px;border-radius:10px;border:1px solid var(--line2);
    background:#23233a;color:#dfe1ee;box-shadow:0 18px 40px -22px #000;font-size:12.5px;animation:in .18s ease}
  .toast.ok{border-left:3px solid var(--good)}
  .toast.err{border-left:3px solid var(--bad)}
  @keyframes in{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:none}}

  @media(max-width:1120px){.cols{grid-template-columns:1fr}}
  @media(max-width:1024px){.stats{grid-template-columns:repeat(2,1fr)}}
  @media(max-width:860px){
    .sidebar{transform:translateX(-100%)}
    .sidebar.open{transform:none}
    .main{margin-left:0}
    .burger{display:inline-flex}
    .backdrop.on{display:block}
    .updated{display:none}
  }
  @media(max-width:560px){
    .content{padding:16px}
    .grid2{grid-template-columns:1fr}
    .stats{grid-template-columns:1fr}
    .search{display:none}
    .topbar{padding:10px 14px}
  }
</style>
</head>
<body>

<div class="layout">
  <aside class="sidebar" id="sidebar">
    <div class="side-brand">
      <div class="logo">V</div>
      <div><b>Vortex Arena</b><small>License Panel</small></div>
    </div>
    <nav>
      <div class="nav-cap">Quản lý</div>
      <div class="nav-item active" data-action="view" data-view="dashboard">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="9"/><rect x="14" y="3" width="7" height="5"/><rect x="14" y="12" width="7" height="9"/><rect x="3" y="16" width="7" height="5"/></svg>
        Tổng quan
      </div>
      <div class="nav-item" data-action="view" data-view="keys">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3 21 2"/><path d="M16 3l3 3"/></svg>
        Key bản quyền <span class="nav-badge" id="navKeys">0</span>
      </div>
      <div class="nav-item" data-action="view" data-view="sessions">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l3 8 4-16 3 8h4"/></svg>
        Phiên hoạt động <span class="nav-badge" id="navSessions">0</span>
      </div>
    </nav>
    <div class="side-foot">
      <div class="side-user">
        <span class="av"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg></span>
        <span>Quản trị viên</span>
      </div>
      <span class="conn" id="conn"><span class="dot" style="background:var(--faint)"></span> Chưa đăng nhập</span>
    </div>
  </aside>

  <div class="main">
    <header class="topbar">
      <button class="btn icon burger" data-action="burger" title="Menu">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h18M3 12h18M3 18h18"/></svg>
      </button>
      <h1 id="pageTitle">Tổng quan</h1>
      <span class="updated" id="updated"></span>
      <div class="spacer"></div>
      <input id="search" class="search" placeholder="Tìm key / ghi chú / thiết bị">
      <button class="btn icon" id="refreshBtn" data-action="refresh" title="Tải lại dữ liệu">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v5h-5"/></svg>
      </button>
      <button class="btn primary" data-action="open-mint">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>
        Tạo key
      </button>
      <button class="btn icon" data-action="logout" title="Đăng xuất">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/></svg>
      </button>
    </header>

    <div class="content">
      <section id="view-dashboard" class="section">
        <div class="stats">
          <div class="stat"><div class="stat-main"><div class="stat-label">Tổng số key</div><div class="stat-value" id="sTotal">0</div><div class="stat-sub" id="sTotalSub">chưa có key nào</div></div>
            <div class="stat-ic ic-blue"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3 21 2"/><path d="M16 3l3 3"/></svg></div></div>
          <div class="stat"><div class="stat-main"><div class="stat-label">Key đang hoạt động</div><div class="stat-value" id="sActive">0</div><div class="stat-sub">có thể kích hoạt</div></div>
            <div class="stat-ic ic-green"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg></div></div>
          <div class="stat"><div class="stat-main"><div class="stat-label">Phiên trực tuyến</div><div class="stat-value" id="sLive">0</div><div class="stat-sub">đang hoạt động</div></div>
            <div class="stat-ic ic-yellow"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l3 8 4-16 3 8h4"/></svg></div></div>
          <div class="stat"><div class="stat-main"><div class="stat-label">Thiết bị đã gắn</div><div class="stat-value" id="sDev">0</div><div class="stat-sub">trên toàn hệ thống</div></div>
            <div class="stat-ic ic-purple"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2"/><path d="M11 18h2"/></svg></div></div>
        </div>

        <div class="cols">
          <div class="card">
            <div class="card-h"><h2>Key mới nhất</h2><div class="spacer"></div>
              <button class="btn sm" data-action="view" data-view="keys">Xem tất cả</button></div>
            <div class="card-b">
              <table><thead><tr><th>Key</th><th>Gói</th><th>Trạng thái</th><th>Hết hạn</th><th>Thiết bị</th></tr></thead>
                <tbody id="recentBody"></tbody></table>
            </div>
          </div>

          <div class="card">
            <div class="card-h"><h2>Phân bố theo gói</h2></div>
            <div class="plans" id="plans"></div>
          </div>
        </div>
      </section>

      <section id="view-keys" class="section" style="display:none">
        <div class="card">
          <div class="card-h">
            <h2>Danh sách key</h2>
            <span class="sub" id="keysCount"></span>
            <div class="spacer"></div>
            <select id="planFilter" class="plan-filter" title="Lọc theo loại key">
              <option value="">Tất cả loại</option>
              <option value="lite">Lite</option>
              <option value="pro">Pro</option>
            </select>
            <button class="btn sm" data-action="open-mint" data-plan="lite">+ Lite</button>
            <button class="btn sm" data-action="open-mint" data-plan="pro">+ Pro</button>
            <button class="btn primary sm" data-action="open-mint">+ Tạo key</button>
          </div>
          <div class="tabs" id="filterTabs">
            <button class="tab active" data-action="filter" data-filter="all">Tất cả <span class="n" id="tabAll">0</span></button>
            <button class="tab" data-action="filter" data-filter="active">Hoạt động <span class="n" id="tabActive">0</span></button>
            <button class="tab" data-action="filter" data-filter="revoked">Đã thu hồi <span class="n" id="tabRevoked">0</span></button>
            <button class="tab" data-action="filter" data-filter="expired">Hết hạn <span class="n" id="tabExpired">0</span></button>
          </div>
          <div class="card-b">
            <table>
              <thead><tr><th>Key</th><th>Gói</th><th>Trạng thái</th><th>Hết hạn</th><th>Thiết bị</th><th>Ghi chú</th><th style="text-align:right">Thao tác</th></tr></thead>
              <tbody id="keysBody"></tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="view-sessions" class="section" style="display:none">
        <div class="card">
          <div class="card-h"><h2>Phiên đang hoạt động</h2><span class="sub" id="sessionsCount"></span></div>
          <div class="card-b">
            <table>
              <thead><tr><th>Key</th><th>Token</th><th>Thiết bị</th><th>Bước</th><th>Lần cuối</th><th>Trạng thái</th><th style="text-align:right">Thao tác</th></tr></thead>
              <tbody id="sessionsBody"></tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
  </div>
</div>

<div class="backdrop" id="backdrop" data-action="close-side"></div>

<div class="gate" id="gate">
  <div class="gate-card">
    <div class="ic">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="10" width="16" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>
    </div>
    <h1>Cần mã quản trị</h1>
    <p class="sub">Nhập Admin Token để mở bảng điều khiển.</p>
    <label class="f" for="token">Admin Token</label>
    <input id="token" type="password" placeholder="Dán token tại đây..." autocomplete="off">
    <div class="err" id="gateErr"></div>
    <button class="btn primary" data-action="unlock" style="width:100%;margin-top:6px">Mở khoá</button>
    <p class="hint">Token nằm trong file <span class="mono">.env</span> (dòng <span class="mono">ADMIN_TOKEN</span>).</p>
  </div>
</div>

<div class="overlay" id="mintOverlay">
  <div class="modal">
    <div class="modal-h"><h3>Tạo key mới</h3></div>
    <div class="modal-b">
      <div class="grid2">
        <div class="full">
          <label class="f">Loại key</label>
          <div class="seg" id="planSeg">
            <button type="button" class="seg-btn" data-action="pick-plan" data-plan="lite"><b>Lite</b><small>1 thiết bị</small></button>
            <button type="button" class="seg-btn active" data-action="pick-plan" data-plan="pro"><b>Pro</b><small>3 thiết bị</small></button>
          </div>
        </div>
        <div class="full">
          <label class="f">Cách tạo key</label>
          <div class="seg" id="modeSeg">
            <button type="button" class="seg-btn active" data-action="pick-mode" data-mode="auto"><b>Tự động</b><small>random ${config.keyPrefix}-xxxx-xxxx</small></button>
            <button type="button" class="seg-btn" data-action="pick-mode" data-mode="manual"><b>Tự nhập</b><small>admin tự đặt key</small></button>
          </div>
        </div>
        <div class="full" id="customWrap" style="display:none">
          <label class="f" for="customKey">Key tự nhập</label>
          <div class="keyrow">
            <span class="pfx">${config.keyPrefix}-</span>
            <input id="customKey" placeholder="VD: KHACH-A, KHACH-B" spellcheck="false" autocomplete="off">
          </div>
          <div class="field-hint">Tiền tố <b>${config.keyPrefix}-</b> được thêm tự động. Nhập nhiều key, cách nhau bằng dấu phẩy hoặc xuống dòng.</div>
        </div>
        <div id="countWrap"><label class="f" for="count">Số lượng (1–500)</label><input id="count" type="number" value="1" min="1" max="500"></div>
        <div><label class="f" for="days">Số ngày</label><input id="days" type="number" value="30" min="0"><div class="field-hint">0 = vĩnh viễn</div></div>
        <div><label class="f" for="maxDevices">Thiết bị tối đa</label><input id="maxDevices" type="number" value="1" min="1"><div class="field-hint">số máy được phép dùng</div></div>
        <div class="full">
          <label class="f" for="password">Mật khẩu menu</label>
          <input id="password" placeholder="Để trống = tự tạo 12 ký tự" autocomplete="new-password">
          <div class="field-hint">Người dùng nhập cùng key khi kích hoạt (8–128 ký tự). Key cũ chưa có mật khẩu vẫn dùng được.</div>
        </div>
        <div class="full">
          <div class="f" style="display:flex;align-items:center;justify-content:space-between">
            <span>Ghi chú</span>
            <button type="button" class="btn sm" data-action="auto-note" style="padding:2px 9px">Tự động</button>
          </div>
          <input id="note" placeholder="Tự động theo loại key">
          <div class="field-hint" id="noteHint"></div>
        </div>
      </div>
    </div>
    <div class="modal-f">
      <button class="btn" data-action="close-mint">Huỷ</button>
      <button class="btn primary" data-action="mint">Tạo key</button>
    </div>
  </div>
</div>

<div class="overlay" id="askOverlay">
  <div class="modal sm">
    <div class="modal-h"><h3 id="askTitle">Xác nhận</h3></div>
    <div class="modal-b"><p id="askText" style="margin:0;color:var(--text);word-break:break-word"></p></div>
    <div class="modal-f">
      <button class="btn" data-action="ask-no">Huỷ</button>
      <button class="btn danger" data-action="ask-yes">Đồng ý</button>
    </div>
  </div>
</div>

<div class="toasts" id="toasts"></div>

<script>
(function () {
  var TOKEN_KEY = 'ffxc_admin_token';
  var params = new URLSearchParams(location.search);
  var token = params.get('token') || localStorage.getItem(TOKEN_KEY) || '';
  if (params.get('token')) { localStorage.setItem(TOKEN_KEY, params.get('token')); }

  var state = { keys: [], sessions: [], q: '', view: 'dashboard', filter: 'all', planFilter: '', plan: 'pro', noteAuto: true, mode: 'auto' };
  var pending = null;
  var STATUS_VI = { active: 'Hoạt động', revoked: 'Đã thu hồi', deleted: 'Đã xoá', expired: 'Hết hạn' };
  var TITLES = { dashboard: 'Tổng quan', keys: 'Key bản quyền', sessions: 'Phiên hoạt động' };
  var EMPTY_IC = '<div class="empty-ic"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg></div>';

  function el(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function fmt(sec) {
    if (!sec) return '—';
    return new Date(sec * 1000).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
  function dateOnly(sec) {
    if (!sec) return 'Vĩnh viễn';
    return new Date(sec * 1000).toLocaleDateString('vi-VN');
  }
  function url(base, a, b, c) {
    var s = base;
    if (a !== undefined) s += '/' + encodeURIComponent(a);
    if (b !== undefined) s += '/' + encodeURIComponent(b);
    if (c !== undefined) s += '/' + encodeURIComponent(c);
    return s;
  }
  function statusOf(k) { return (k.expired && k.status === 'active') ? 'expired' : k.status; }
  function planClass(p) {
    var c = String(p || '').toLowerCase();
    return c === 'lite' ? 'lite' : (c === 'pro' ? 'pro' : 'other');
  }
  function planBadge(p) {
    return '<span class="pbadge ' + planClass(p) + '">' + esc(p || '—') + '</span>';
  }
  function suggestNote(p) {
    var name = planClass(p) === 'lite' ? 'Lite' : (planClass(p) === 'pro' ? 'Pro' : p);
    var d = new Date();
    var dd = ('0' + d.getDate()).slice(-2);
    var mm = ('0' + (d.getMonth() + 1)).slice(-2);
    return name + ' - ' + dd + '/' + mm + '/' + d.getFullYear();
  }
  function setPlan(p) {
    state.plan = p;
    var btns = document.querySelectorAll('#planSeg .seg-btn');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('active', btns[i].getAttribute('data-plan') === p);
    }
    el('maxDevices').value = p === 'lite' ? '1' : '3';
    if (state.noteAuto) el('note').value = suggestNote(p);
    el('noteHint').textContent = state.noteAuto ? ('Tự động: ' + suggestNote(p)) : 'Ghi chú tùy chỉnh';
  }
  function setMode(m) {
    state.mode = m;
    var btns = document.querySelectorAll('#modeSeg .seg-btn');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('active', btns[i].getAttribute('data-mode') === m);
    }
    el('customWrap').style.display = m === 'manual' ? '' : 'none';
    el('countWrap').style.display = m === 'manual' ? 'none' : '';
  }

  function toast(msg, kind) {
    var t = document.createElement('div');
    t.className = 'toast ' + (kind || '');
    t.textContent = msg;
    el('toasts').appendChild(t);
    window.setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 3200);
  }

  function ask(title, text, onYes) {
    el('askTitle').textContent = title;
    el('askText').textContent = text;
    pending = onYes;
    el('askOverlay').classList.add('on');
  }
  function closeAsk() { el('askOverlay').classList.remove('on'); pending = null; }
  function openMint(plan) {
    if (plan) state.plan = plan;
    state.noteAuto = true;
    el('customKey').value = '';
    el('mintOverlay').classList.add('on');
    el('count').value = '1';
    setPlan(state.plan);
    setMode(state.mode);
  }
  function closeMint() { el('mintOverlay').classList.remove('on'); }
  function setLoading(on) { el('refreshBtn').classList.toggle('spin', !!on); }

  function api(method, u, body) {
    return fetch(u, {
      method: method,
      headers: { 'x-admin-token': token, 'content-type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined
    }).then(function (r) {
      if (r.status === 401) { showGate('Token không đúng hoặc đã hết hiệu lực.'); throw new Error('unauthorized'); }
      if (!r.ok) {
        return r.json().catch(function () { return null; }).then(function (j) {
          var err = new Error((j && (j.key || j.error)) || ('HTTP ' + r.status));
          err.status = r.status;
          err.code = j && j.error;
          err.detail = j && j.key;
          throw err;
        });
      }
      return r.status === 204 ? null : r.json();
    });
  }

  function showGate(msg) {
    el('gate').style.display = 'flex';
    el('gateErr').textContent = msg || '';
    el('token').value = token || '';
    el('conn').innerHTML = '<span class="dot" style="background:var(--faint)"></span> Chưa đăng nhập';
    closeMint();
    closeAsk();
  }
  function showApp() {
    el('gate').style.display = 'none';
    el('conn').innerHTML = '<span class="dot pulse" style="background:var(--good)"></span> Trực tuyến';
  }

  function boot() {
    if (!token) { showGate(''); return; }
    setLoading(true);
    Promise.all([api('GET', '/admin/api/keys'), api('GET', '/admin/api/sessions')])
      .then(function (r) {
        state.keys = (r[0] && r[0].keys) || [];
        state.sessions = (r[1] && r[1].sessions) || [];
        showApp();
        render();
      })
      .catch(function () {})
      .then(function () { setLoading(false); });
  }

  function setView(v) {
    state.view = v;
    el('view-dashboard').style.display = v === 'dashboard' ? 'block' : 'none';
    el('view-keys').style.display = v === 'keys' ? 'block' : 'none';
    el('view-sessions').style.display = v === 'sessions' ? 'block' : 'none';
    el('pageTitle').textContent = TITLES[v] || 'Tổng quan';
    var items = document.querySelectorAll('.nav-item');
    for (var i = 0; i < items.length; i++) {
      items[i].classList.toggle('active', items[i].getAttribute('data-view') === v);
    }
    el('sidebar').classList.remove('open');
    el('backdrop').classList.remove('on');
  }

  function setFilter(f) {
    state.filter = f;
    var tabs = document.querySelectorAll('#filterTabs .tab');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].classList.toggle('active', tabs[i].getAttribute('data-filter') === f);
    }
    renderKeys();
  }

  function render() {
    renderStats();
    renderPlans();
    renderKeys();
    renderRecent();
    renderSessions();
    el('updated').textContent = 'Cập nhật ' + new Date().toLocaleTimeString('vi-VN');
  }

  function renderStats() {
    var live = state.sessions.filter(function (s) { return !s.expired; }).length;
    var active = state.keys.filter(function (k) { return k.status === 'active' && !k.expired; }).length;
    var devs = state.keys.reduce(function (a, k) { return a + k.deviceCount; }, 0);
    el('sTotal').textContent = state.keys.length;
    el('sActive').textContent = active;
    el('sLive').textContent = live;
    el('sDev').textContent = devs;
    el('sTotalSub').textContent = state.keys.length ? (active + ' đang dùng được') : 'chưa có key nào';
    el('navKeys').textContent = state.keys.length;
    el('navSessions').textContent = state.sessions.length;

    var counts = { all: state.keys.length, active: 0, revoked: 0, expired: 0 };
    state.keys.forEach(function (k) {
      var st = statusOf(k);
      if (st === 'active') counts.active++;
      else if (st === 'revoked') counts.revoked++;
      else if (st === 'expired') counts.expired++;
    });
    el('tabAll').textContent = counts.all;
    el('tabActive').textContent = counts.active;
    el('tabRevoked').textContent = counts.revoked;
    el('tabExpired').textContent = counts.expired;
  }

  function renderPlans() {
    var map = {};
    state.keys.forEach(function (k) { map[k.plan] = (map[k.plan] || 0) + 1; });
    var names = Object.keys(map);
    var host = el('plans');
    if (!names.length) {
      host.innerHTML = '<div class="dim" style="text-align:center;padding:6px 0">Chưa có dữ liệu.</div>';
      return;
    }
    var max = Math.max.apply(null, names.map(function (n) { return map[n]; }));
    host.innerHTML = names.sort(function (a, b) { return map[b] - map[a]; }).map(function (n) {
      var pct = Math.round((map[n] / max) * 100);
      return '<div class="plan"><div class="plan-top"><span>' + esc(n) + '</span><b>' + map[n] + ' key</b></div>' +
        '<div class="bar"><span style="width:' + pct + '%"></span></div></div>';
    }).join('');
  }

  function matches(k) {
    if (state.filter !== 'all' && statusOf(k) !== state.filter) return false;
    if (state.planFilter && String(k.plan || '').toLowerCase() !== state.planFilter) return false;
    if (!state.q) return true;
    var q = state.q;
    if (k.key.toLowerCase().indexOf(q) !== -1) return true;
    if ((k.note || '').toLowerCase().indexOf(q) !== -1) return true;
    for (var i = 0; i < k.devices.length; i++) {
      var d = k.devices[i];
      if ((d.hwid || '').toLowerCase().indexOf(q) !== -1) return true;
      if ((d.deviceName || '').toLowerCase().indexOf(q) !== -1) return true;
    }
    return false;
  }

  function badge(st) {
    return '<span class="badge ' + st + '">' + (STATUS_VI[st] || st) + '</span>';
  }

  function deviceTable(k) {
    if (!k.devices.length) return '<div class="devwrap"><h4>Thiết bị</h4><span class="dim">Chưa có thiết bị nào được gắn.</span></div>';
    return '<div class="devwrap"><h4>Thiết bị (' + k.devices.length + ')</h4>' +
      '<table><thead><tr><th>HWID</th><th>Tên máy</th><th>Model</th><th>iOS</th><th>MAC</th><th>Lần cuối</th><th>Trạng thái</th><th></th></tr></thead><tbody>' +
      k.devices.map(function (d) {
        return '<tr>' +
          '<td class="mono">' + esc(d.hwid) + '</td>' +
          '<td>' + esc(d.deviceName || '—') + '</td>' +
          '<td class="dim">' + esc(d.model || '—') + '</td>' +
          '<td class="dim">' + esc(d.iosVersion || '—') + '</td>' +
          '<td class="mono dim">' + esc(d.mac || '—') + '</td>' +
          '<td class="dim">' + fmt(d.lastSeen) + '</td>' +
          '<td>' + (d.online ? '<span class="badge active">Trực tuyến</span>' : '<span class="badge plain">Ngoại tuyến</span>') + '</td>' +
          '<td style="text-align:right"><button class="btn sm danger" data-action="unbind" data-key="' + esc(k.key) + '" data-hwid="' + esc(d.hwid) + '">Gỡ</button></td>' +
          '</tr>';
      }).join('') + '</tbody></table></div>';
  }

  function keyRow(k) {
    var st = statusOf(k);
    return '<tr>' +
        '<td class="keycell mono"><button class="btn sm" data-action="copy" data-copy="' + esc(k.key) + '" title="Bấm để sao chép">' + esc(k.key) + '</button></td>' +
        '<td>' + planBadge(k.plan) + '</td>' +
        '<td>' + badge(st) + '</td>' +
        '<td class="dim">' + dateOnly(k.expiresAt) + '</td>' +
        '<td><button class="btn sm" data-action="toggle" data-key="' + esc(k.key) + '">' + k.deviceCount + '/' + k.maxDevices + '<span class="chev">▾</span></button></td>' +
        '<td class="dim">' + esc(k.note || '—') + '</td>' +
        '<td><div class="row-actions">' +
          (k.status === 'revoked'
            ? '<button class="btn sm" data-action="restore" data-key="' + esc(k.key) + '">Khôi phục</button>'
            : '<button class="btn sm" data-action="revoke" data-key="' + esc(k.key) + '">Thu hồi</button>') +
          '<button class="btn sm" data-action="reset" data-key="' + esc(k.key) + '">Reset</button>' +
          '<button class="btn sm danger" data-action="delete" data-key="' + esc(k.key) + '">Xoá</button>' +
        '</div></td>' +
      '</tr>' +
      '<tr class="devrow" data-dev="' + esc(k.key) + '" style="display:none"><td colspan="7">' + deviceTable(k) + '</td></tr>';
  }

  function renderKeys() {
    var list = state.keys.filter(matches);
    el('keysCount').textContent = '(' + list.length + '/' + state.keys.length + ')';
    var body = el('keysBody');
    if (!list.length) {
      var msg = state.keys.length ? 'Không có key nào khớp bộ lọc hiện tại.' : 'Chưa có key nào. Bấm "Tạo key" để bắt đầu.';
      body.innerHTML = '<tr><td colspan="7" class="empty">' + EMPTY_IC + msg + '</td></tr>';
      return;
    }
    body.innerHTML = list.map(keyRow).join('');
  }

  function renderRecent() {
    var body = el('recentBody');
    var list = state.keys.slice(0, 5);
    if (!list.length) {
      body.innerHTML = '<tr><td colspan="5" class="empty">Chưa có key nào.</td></tr>';
      return;
    }
    body.innerHTML = list.map(function (k) {
      return '<tr>' +
        '<td class="keycell mono">' + esc(k.key) + '</td>' +
        '<td>' + planBadge(k.plan) + '</td>' +
        '<td>' + badge(statusOf(k)) + '</td>' +
        '<td class="dim">' + dateOnly(k.expiresAt) + '</td>' +
        '<td>' + k.deviceCount + '/' + k.maxDevices + '</td>' +
        '</tr>';
    }).join('');
  }

  function renderSessions() {
    el('sessionsCount').textContent = '(' + state.sessions.length + ')';
    var body = el('sessionsBody');
    if (!state.sessions.length) {
      body.innerHTML = '<tr><td colspan="7" class="empty">' + EMPTY_IC + 'Không có phiên nào đang hoạt động.</td></tr>';
      return;
    }
    body.innerHTML = state.sessions.map(function (s) {
      return '<tr>' +
        '<td class="keycell mono">' + esc(s.key) + '</td>' +
        '<td class="mono dim">' + esc(String(s.token).slice(0, 12)) + '…</td>' +
        '<td class="mono dim">' + esc(s.hwid) + '</td>' +
        '<td class="dim">' + s.sequence + '</td>' +
        '<td class="dim">' + fmt(s.lastSeenAt) + '</td>' +
        '<td>' + (s.expired ? '<span class="badge expired">Hết hạn</span>' : '<span class="badge active">Trực tuyến</span>') + '</td>' +
        '<td><div class="row-actions"><button class="btn sm danger" data-action="drop" data-token="' + esc(s.token) + '">Ngắt</button></div></td>' +
        '</tr>';
    }).join('');
  }

  function unlock() {
    token = el('token').value.trim();
    if (!token) { el('gateErr').textContent = 'Vui lòng nhập token.'; return; }
    localStorage.setItem(TOKEN_KEY, token);
    boot();
  }

  function copy(btn, text) {
    if (!(navigator.clipboard && navigator.clipboard.writeText)) { toast('Trình duyệt không hỗ trợ sao chép', 'err'); return; }
    navigator.clipboard.writeText(text).then(function () {
      var old = btn.innerHTML;
      btn.classList.add('copied');
      btn.textContent = '✓ Đã chép';
      window.setTimeout(function () { btn.classList.remove('copied'); btn.innerHTML = old; }, 1000);
      toast('Đã sao chép key', 'ok');
    }, function () { toast('Không sao chép được', 'err'); });
  }

  function mint() {
    var body = {
      plan: state.plan,
      expiresInDays: Number(el('days').value),
      maxDevices: Number(el('maxDevices').value),
      note: el('note').value,
      password: el('password').value
    };
    if (state.mode === 'manual') {
      var pieces = el('customKey').value.split(/[,;]/);
      var keys = [];
      for (var i = 0; i < pieces.length; i++) {
        var lines = pieces[i].split(String.fromCharCode(10));
        for (var j = 0; j < lines.length; j++) {
          var s = lines[j].trim();
          if (s) keys.push(s);
        }
      }
      if (!keys.length) { toast('Nhập ít nhất 1 key.', 'err'); return; }
      body.keys = keys;
    } else {
      body.count = Number(el('count').value);
    }
    api('POST', '/admin/api/keys', body).then(function (r) {
      toast('Đã tạo ' + r.keys.length + ' key', 'ok');
      if (r.password) {
        var list = r.keys.map(function (k) { return k.key; }).join(String.fromCharCode(10));
        window.prompt(
          'Lưu lại key và mật khẩu (dùng chung). Bấm Ctrl/Cmd+C để sao chép:',
          list + String.fromCharCode(10, 10) + 'Mật khẩu: ' + r.password
        );
      }
      el('note').value = '';
      el('customKey').value = '';
      el('password').value = '';
      closeMint();
      boot();
    }).catch(function (e) {
      if (e.message === 'unauthorized') return;
      if (e.code === 'key_exists') toast('Key đã tồn tại: ' + e.detail, 'err');
      else if (e.code === 'invalid_key') toast('Key không hợp lệ', 'err');
      else if (e.code === 'invalid_password') toast('Mật khẩu phải từ 8 đến 128 ký tự', 'err');
      else toast('Lỗi: ' + e.message, 'err');
    });
  }

  function act(method, u) {
    api(method, u).then(function () {
      toast('Đã thực hiện xong', 'ok');
      boot();
    }).catch(function (e) {
      if (e.message !== 'unauthorized') toast('Lỗi: ' + e.message, 'err');
    });
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-action]');
    if (!b) return;
    var a = b.getAttribute('data-action');
    var key = b.getAttribute('data-key');

    if (a === 'unlock') return unlock();
    if (a === 'view') return setView(b.getAttribute('data-view'));
    if (a === 'filter') return setFilter(b.getAttribute('data-filter'));
    if (a === 'burger') { el('sidebar').classList.toggle('open'); el('backdrop').classList.toggle('on'); return; }
    if (a === 'close-side') { el('sidebar').classList.remove('open'); el('backdrop').classList.remove('on'); return; }
    if (a === 'refresh') return boot();
    if (a === 'logout') { localStorage.removeItem(TOKEN_KEY); token = ''; return showGate('Đã đăng xuất.'); }
    if (a === 'open-mint') return openMint(b.getAttribute('data-plan'));
    if (a === 'pick-plan') return setPlan(b.getAttribute('data-plan'));
    if (a === 'pick-mode') return setMode(b.getAttribute('data-mode'));
    if (a === 'auto-note') { state.noteAuto = true; el('note').value = suggestNote(state.plan); el('noteHint').textContent = 'Tự động: ' + suggestNote(state.plan); return; }
    if (a === 'close-mint') return closeMint();
    if (a === 'mint') return mint();
    if (a === 'copy') return copy(b, b.getAttribute('data-copy'));

    if (a === 'toggle') {
      var row = document.querySelector('tr[data-dev="' + key.replace(/"/g, '') + '"]');
      if (row) {
        var open = row.style.display !== 'none';
        row.style.display = open ? 'none' : '';
        var ch = b.querySelector('.chev');
        if (ch) ch.classList.toggle('open', !open);
      }
      return;
    }
    if (a === 'revoke') return ask('Thu hồi key?', 'Key ' + key + ' sẽ bị đánh dấu thu hồi và không dùng được nữa.', function () { act('POST', url('/admin/api/keys', key, 'revoke')); });
    if (a === 'restore') return act('POST', url('/admin/api/keys', key, 'restore'));
    if (a === 'reset') return ask('Reset thiết bị?', 'Toàn bộ thiết bị đã gắn với key ' + key + ' sẽ bị gỡ, phiên liên quan cũng bị xoá.', function () { act('POST', url('/admin/api/keys', key, 'reset-devices')); });
    if (a === 'delete') return ask('Xoá key?', 'Key ' + key + ' sẽ bị xoá vĩnh viễn cùng các phiên của nó. Không thể hoàn tác.', function () { act('DELETE', url('/admin/api/keys', key)); });
    if (a === 'unbind') return ask('Gỡ thiết bị?', 'Thiết bị ' + b.getAttribute('data-hwid') + ' sẽ bị gỡ khỏi key ' + key + '.', function () { act('DELETE', url('/admin/api/keys', key, 'devices', b.getAttribute('data-hwid'))); });
    if (a === 'drop') return ask('Ngắt phiên?', 'Phiên ' + String(b.getAttribute('data-token')).slice(0, 12) + '… sẽ bị xoá ngay lập tức.', function () { act('DELETE', url('/admin/api/sessions', b.getAttribute('data-token'))); });

    if (a === 'ask-yes') { var fn = pending; closeAsk(); if (fn) fn(); return; }
    if (a === 'ask-no') return closeAsk();
  });

  el('search').addEventListener('input', function () {
    state.q = el('search').value.trim().toLowerCase();
    if (state.q && state.view !== 'keys') setView('keys');
    renderKeys();
  });
  el('planFilter').addEventListener('change', function () {
    state.planFilter = el('planFilter').value;
    renderKeys();
  });
  el('note').addEventListener('input', function () {
    var v = el('note').value.trim();
    if (!v) { state.noteAuto = true; el('noteHint').textContent = 'Tự động: ' + suggestNote(state.plan); }
    else { state.noteAuto = false; el('noteHint').textContent = 'Ghi chú tùy chỉnh'; }
  });
  el('token').addEventListener('keydown', function (e) { if (e.key === 'Enter') unlock(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { closeAsk(); closeMint(); }
    if (e.key === '/' && el('gate').style.display !== 'flex') {
      var tag = (e.target.tagName || '').toLowerCase();
      if (tag !== 'input' && tag !== 'select') { e.preventDefault(); el('search').focus(); }
    }
  });

  state.noteAuto = true;
  setPlan(state.plan);
  setMode(state.mode);

  boot();
})();
</script>
</body>
</html>
`;
