import http from "node:http";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { extname, join } from "node:path";
import { loadOrCreateAuthority } from "./pki.js";
import { createRelay, type Rule } from "./mitm.js";
import { buildMobileConfig } from "./profile.js";
import { type CaptureRecord, suggestRules, suggestPatchRules } from "./suggest.js";
import { renderDashboard } from "./dashboard.js";
import { renderMenu } from "./menu.js";
import { type VpnPayload } from "./profile.js";
import { FEATURES, featureById, featureHits, rulesForFeatures } from "./features.js";

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

/**
 * Static copy of the in-app control panel, served at /panel so a profile's web
 * clip can open the same UI the app bundles. Kept separate from /menu: the
 * relay's own menu keeps working while this surface is evaluated.
 * Sync with `scripts/sync-panel.sh`.
 */
const panelDir = process.env.RELAY_PANEL_DIR ?? join(process.cwd(), "public", "menu");
const panelTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".woff2": "font/woff2",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};
const rulesPath = process.env.RELAY_RULES ?? join(dataDir, "rules.json");
const publicHost = process.env.RELAY_PUBLIC_HOST ?? "127.0.0.1";
const profileName = process.env.RELAY_PROFILE_NAME ?? "Nimbus Relay";

/**
 * The licence backend, used by the menu's login screen.
 *
 * Two URLs on purpose: `/api` authorises a key, while `/admin/api/sessions`
 * answers "is this token still live" without touching the heartbeat sequence
 * the app is already driving. Reusing the heartbeat from here would move the
 * client's sequence forward and register as a replay on its next poll.
 */
const authApiUrl = process.env.AUTH_URL ?? "http://127.0.0.1:8787/api";
const authAdminUrl = process.env.AUTH_ADMIN_URL ?? "http://127.0.0.1:8787";
const authAdminToken = process.env.AUTH_ADMIN_TOKEN ?? process.env.ADMIN_TOKEN ?? "";

const version = (() => {
  try {
    const pkg = JSON.parse(readFileSync("package.json", "utf8")) as { version?: string };
    return pkg.version ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
})();

function readBody(req: http.IncomingMessage, limit = 8 * 1024): Promise<string | null> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        resolve(null);
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", () => resolve(null));
  });
}

/**
 * `fetch` is present at runtime (Node 18+) but this project compiles against
 * ES2022 without the DOM lib, so its return type is not in scope. One narrow
 * interface keeps the two call sites honest without pulling in lib.dom.
 */
interface FetchResult {
  ok: boolean;
  status: number;
  text(): Promise<string>;
  json(): Promise<unknown>;
}

async function httpFetch(
  url: string,
  init?: { method?: string; headers?: Record<string, string>; body?: string },
): Promise<FetchResult> {
  return (await fetch(url, init)) as unknown as FetchResult;
}

async function sessionIsValid(token: string): Promise<boolean> {
  if (!token || !authAdminToken) return false;
  try {
    const response = await httpFetch(`${authAdminUrl}/admin/api/sessions`, {
      headers: { "x-admin-token": authAdminToken },
    });
    if (!response.ok) return false;
    const body = (await response.json()) as {
      sessions?: { token?: string; expired?: boolean }[];
    };
    return (body.sessions ?? []).some((entry) => entry.token === token && entry.expired === false);
  } catch {
    return false;
  }
}

/**
 * Who may change rules. With no admin token configured the relay stays open,
 * which is right for a laptop-and-one-phone setup; as soon as a token exists,
 * a rule write needs either that token (the dashboard) or a live licence
 * session (the phone menu).
 */
async function controlAllowed(req: http.IncomingMessage): Promise<boolean> {
  if (!authAdminToken) return true;
  if (req.headers["x-admin-token"] === authAdminToken) return true;
  const token = req.headers["x-menu-session"];
  return typeof token === "string" && (await sessionIsValid(token));
}

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

const featuresPath = process.env.RELAY_FEATURES ?? join(dataDir, "features.json");

function loadEnabledFeatures(): Set<string> {
  if (!existsSync(featuresPath)) return new Set();
  try {
    const parsed = JSON.parse(readFileSync(featuresPath, "utf8")) as unknown;
    const list = Array.isArray(parsed)
      ? parsed
      : ((parsed as { enabled?: unknown[] }).enabled ?? []);
    return new Set(
      list.filter((id): id is string => typeof id === "string" && Boolean(featureById(id))),
    );
  } catch {
    return new Set();
  }
}

function saveEnabledFeatures(): void {
  writeFileSync(featuresPath, JSON.stringify({ enabled: [...enabledFeatures] }, null, 2));
}

const enabledFeatures = loadEnabledFeatures();

/**
 * Self-pin from one capture. `suggestPatchRules` finds the game's real
 * `CodePatchUrl` in the var table; applying that suggestion stores the rule
 * here. Feature-tagged rules cannot live in `rules.json` (they are rebuilt
 * from their feature every apply), which is why the pin needs its own file.
 */
const pinPath = process.env.RELAY_PIN ?? join(dataDir, "pin.json");
const codepatchFeature = FEATURES.find((feature) => feature.id === "codepatch");

interface PinnedPatch {
  host: string;
  pathPattern: string;
  bodyFile: string;
  contentType?: string;
  note?: string;
}

function loadPinnedPatch(): PinnedPatch | null {
  if (!existsSync(pinPath)) return null;
  try {
    const parsed = JSON.parse(readFileSync(pinPath, "utf8")) as Partial<PinnedPatch> | null;
    if (!parsed
      || typeof parsed.host !== "string"
      || typeof parsed.pathPattern !== "string"
      || typeof parsed.bodyFile !== "string") {
      return null;
    }
    new RegExp(parsed.pathPattern);
    if (!existsSync(parsed.bodyFile)) {
      console.warn(`relay: pinned patch file is missing (${parsed.bodyFile}); pin ignored`);
      return null;
    }
    return {
      host: parsed.host,
      pathPattern: parsed.pathPattern,
      bodyFile: parsed.bodyFile,
      contentType: parsed.contentType,
      note: parsed.note,
    };
  } catch {
    return null;
  }
}

function pinnedRule(pin: PinnedPatch): Rule {
  return {
    host: pin.host,
    pathPattern: pin.pathPattern,
    action: "respond",
    bodyFile: pin.bodyFile,
    contentType: pin.contentType ?? "application/octet-stream",
    feature: "codepatch",
    note: pin.note ?? "pinned from capture",
  };
}

const pinnedPatch = loadPinnedPatch();
if (pinnedPatch && codepatchFeature) {
  const rule = pinnedRule(pinnedPatch);
  if (!codepatchFeature.rules.some(
    (existing) => existing.host === rule.host && existing.pathPattern === rule.pathPattern,
  )) {
    codepatchFeature.rules = [...codepatchFeature.rules, rule];
  }
  enabledFeatures.add("codepatch");
}

/** Manual rules keep their order; feature rules are appended and always win. */
function mergedRules(manual: Rule[]): Rule[] {
  return [
    ...manual.filter((rule) => !rule.feature),
    ...rulesForFeatures(enabledFeatures),
  ];
}

function rebuildLiveRules(): void {
  const manual = rules.filter((rule) => !rule.feature);
  const merged = mergedRules(manual);
  rules.length = 0;
  rules.push(...merged);
  writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
  relay.setRules(rules);
}

/**
 * Install one pinned patch rule under the codepatch feature. Persisted in
 * `pin.json`, enabled in `features.json`, and applied live. Shared by the
 * `/pin` endpoint and the autopin loop.
 */
function applyPin(pin: PinnedPatch): boolean {
  if (!codepatchFeature) return false;
  codepatchFeature.rules = [
    ...codepatchFeature.rules.filter((rule) => rule.note !== "pinned from capture"),
    pinnedRule(pin),
  ];
  enabledFeatures.add("codepatch");
  saveEnabledFeatures();
  writeFileSync(pinPath, JSON.stringify(pin, null, 2));
  rebuildLiveRules();
  return true;
}

const ca = loadOrCreateAuthority(join(dataDir, "ca"));
const rules = mergedRules(loadRules());
const passthrough = (process.env.RELAY_PASSTHROUGH ?? "")
  .split(",")
  .map((entry) => entry.trim())
  .filter(Boolean);

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
  const merged = mergedRules(next);
  rules.length = 0;
  rules.push(...merged);
  writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
  relay.setRules(rules);
}

/**
 * Switch a feature on or off. This is the only place the menu's switches reach:
 * it rewrites the live rule array and the file behind it, so a reboot keeps the
 * choice and a running tunnel picks it up on the next request.
 */
function setFeature(id: string, on: boolean): boolean {
  if (!featureById(id)) return false;
  if (on) enabledFeatures.add(id);
  else enabledFeatures.delete(id);
  saveEnabledFeatures();
  const manual = rules.filter((rule) => !rule.feature);
  const merged = mergedRules(manual);
  rules.length = 0;
  rules.push(...merged);
  writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
  relay.setRules(rules);
  return true;
}

function featureState(records: CaptureRecord[]) {
  const hits = featureHits(records);
  return FEATURES.map((feature) => ({
    id: feature.id,
    label: feature.label,
    detail: feature.detail,
    risky: Boolean(feature.risky),
    enabled: enabledFeatures.has(feature.id),
    rules: feature.rules.length,
    hits: hits[feature.id] ?? 0,
  }));
}

const relay = createRelay({
  port: proxyPort,
  ca,
  capturePath,
  rules,
  passthrough,
  // A var table can carry CodePatchUrl late in the body; the autopin scan reads
  // this preview, so give it enough room to see the field.
  previewBytes: Number(process.env.RELAY_PREVIEW_BYTES ?? 2048),
  log: (line) => console.log(line),
});

/**
 * Autopin (`RELAY_AUTOPIN=1`): the first capture that carries the game's own
 * `CodePatchUrl` installs the respond rule without an operator click. One
 * session records; the next launch already gets our bytes. Only a single
 * candidate is applied, and only when it is a respond rule with a real file.
 */
if (process.env.RELAY_AUTOPIN === "1" && !pinnedPatch) {
  const timer = setInterval(() => {
    if (codepatchFeature?.rules.some((rule) => rule.note === "pinned from capture")) {
      clearInterval(timer);
      return;
    }
    try {
      const candidate = suggestPatchRules(readCaptures(4000))
        .find((suggestion) => suggestion.rule.action === "respond" && suggestion.rule.bodyFile);
      const bodyFile = candidate?.rule.bodyFile;
      if (!candidate || !bodyFile) return;
      const pin: PinnedPatch = {
        host: candidate.rule.host ?? candidate.host,
        pathPattern: candidate.rule.pathPattern,
        bodyFile,
        contentType: candidate.rule.contentType ?? "application/octet-stream",
        note: "pinned from capture",
      };
      if (applyPin(pin)) {
        console.log(`relay: autopin ${pin.host}${pin.pathPattern} -> ${pin.bodyFile}`);
        clearInterval(timer);
      }
    } catch (error) {
      console.warn(`relay: autopin check failed: ${String(error)}`);
    }
  }, 5000);
  timer.unref();
}

/**
 * The profile is the whole delivery vehicle: certificate, tunnel, proxy and
 * menu in one tap. A missing variable drops that one payload rather than
 * failing the boot — a Wi-Fi-only deployment is still a valid relay.
 */
function readVpn(): VpnPayload | undefined {
  const server = process.env.RELAY_VPN_SERVER;
  if (!server) return undefined;
  const mode = process.env.RELAY_VPN_MODE ?? "l2tp";

  if (mode === "ikev2") {
    const username = process.env.RELAY_VPN_USER;
    const password = process.env.RELAY_VPN_PASSWORD;
    if (!username || !password) return undefined;
    return {
      type: "ikev2",
      server,
      remoteIdentifier: process.env.RELAY_VPN_REMOTE_ID ?? server,
      username,
      password,
    };
  }

  const username = process.env.RELAY_L2TP_USER;
  const password = process.env.RELAY_L2TP_PASSWORD;
  const sharedSecret = process.env.RELAY_IPSEC_SECRET;
  if (!username || !password || !sharedSecret) return undefined;
  return { type: "l2tp", server, username, password, sharedSecret };
}

const vpn = readVpn();
const menuUrl = process.env.RELAY_MENU_URL;
const consent =
  process.env.RELAY_CONSENT ??
  (vpn
    ? `${profileName.toUpperCase()}

Sau khi cài profile:
1. Bật tin cậy đầy đủ cho ${profileName} trong Cài đặt tin cậy chứng nhận.
2. Mở Cài đặt > VPN, chọn ${profileName} VPN và Kết nối.
3. Đóng hoàn toàn game và mở lại.`
    : undefined);

// Inside the tunnel: applies on every network, including cellular, for as long
// as the VPN is up. RELAY_PROXY_IN_VPN=0 reverts to the manual entry.
const proxies =
  vpn && process.env.RELAY_PROXY_IN_VPN !== "0"
    ? {
        host: publicHost,
        port: proxyPort,
        exceptions: ["localhost", "127.0.0.1", "*.local"],
      }
    : undefined;

const profile = buildMobileConfig({
  ca,
  displayName: profileName,
  consent,
  manualProxy: { host: publicHost, port: proxyPort },
  wifi: process.env.RELAY_WIFI_SSID
    ? {
        ssid: process.env.RELAY_WIFI_SSID,
        proxyHost: process.env.RELAY_WIFI_PROXY ?? publicHost,
        proxyPort,
      }
    : undefined,
  vpn,
  proxies,
  webclip: menuUrl
    ? { url: menuUrl, label: process.env.RELAY_MENU_LABEL ?? `${profileName} Control` }
    : undefined,
});

const admin = http.createServer(async (req, res) => {
  const path = (req.url ?? "/").split("?")[0];

  if (path === "/menu/login") {
    if (req.method !== "POST") {
      res.writeHead(405, { "content-type": "application/json" }).end('{"error":"method_not_allowed"}');
      return;
    }
    if (!authAdminToken) {
      res.writeHead(503, { "content-type": "application/json" }).end(
        JSON.stringify({ error: "auth backend not configured (AUTH_ADMIN_TOKEN)" }),
      );
      return;
    }
    const raw = await readBody(req);
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(raw ?? "") as Record<string, unknown>;
    } catch {
      res.writeHead(400, { "content-type": "application/json" }).end('{"error":"bad_request"}');
      return;
    }
    try {
      const upstream = await httpFetch(authApiUrl, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });
      res
        .writeHead(upstream.status, { "content-type": "application/json" })
        .end(await upstream.text());
    } catch (error) {
      res.writeHead(502, { "content-type": "application/json" }).end(
        JSON.stringify({ error: `auth backend unreachable: ${String(error)}` }),
      );
    }
    return;
  }

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
    const suggestions = [...suggestRules(records), ...suggestPatchRules(records)];
    res
      .writeHead(200, { "content-type": "application/json" })
      .end(JSON.stringify({ captures: records.length, count: suggestions.length, suggestions }, null, 2));
    return;
  }

  if (path === "/features" && req.method === "POST") {
    if (!(await controlAllowed(req))) {
      res.writeHead(401, { "content-type": "application/json" }).end(
        '{"error":"unauthorized","hint":"dashboard: ?token=<ADMIN_TOKEN>; menu: sign in"}',
      );
      return;
    }
    const raw = await readBody(req);
    let body: { id?: unknown; enabled?: unknown };
    try {
      body = JSON.parse(raw ?? "") as { id?: unknown; enabled?: unknown };
    } catch {
      res.writeHead(400, { "content-type": "application/json" }).end('{"error":"bad_request"}');
      return;
    }
    if (typeof body.id !== "string") {
      res.writeHead(400, { "content-type": "application/json" }).end('{"error":"missing_id"}');
      return;
    }
    if (!setFeature(body.id, Boolean(body.enabled))) {
      res.writeHead(404, { "content-type": "application/json" }).end('{"error":"unknown_feature"}');
      return;
    }
    res.writeHead(200, { "content-type": "application/json" }).end(
      JSON.stringify({ id: body.id, enabled: Boolean(body.enabled), rules: rules.length }),
    );
    return;
  }

  if (path === "/pin" && req.method === "POST") {
    if (!(await controlAllowed(req))) {
      res.writeHead(401, { "content-type": "application/json" }).end(
        '{"error":"unauthorized","hint":"dashboard: ?token=<ADMIN_TOKEN>; menu: sign in"}',
      );
      return;
    }
    const raw = await readBody(req);
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(raw ?? "") as Record<string, unknown>;
    } catch {
      res.writeHead(400, { "content-type": "application/json" }).end('{"error":"bad_request"}');
      return;
    }
    const host = typeof body.host === "string" ? body.host.trim() : "";
    const pathPattern = typeof body.pathPattern === "string" ? body.pathPattern.trim() : "";
    const bodyFile = typeof body.bodyFile === "string" && body.bodyFile.trim()
      ? body.bodyFile.trim()
      : (process.env.RELAY_PATCH_FILE ?? "");
    if (!host || !pathPattern || !bodyFile) {
      res.writeHead(400, { "content-type": "application/json" }).end(
        '{"error":"missing host/pathPattern/bodyFile"}',
      );
      return;
    }
    try {
      new RegExp(pathPattern);
    } catch (error) {
      res.writeHead(422, { "content-type": "application/json" }).end(
        JSON.stringify({ error: `pathPattern is not a valid regex: ${String(error)}` }),
      );
      return;
    }
    if (!existsSync(bodyFile)) {
      res.writeHead(409, { "content-type": "application/json" }).end(
        JSON.stringify({ error: "patch file is missing", bodyFile }),
      );
      return;
    }
    if (!codepatchFeature) {
      res.writeHead(500, { "content-type": "application/json" }).end('{"error":"codepatch feature missing"}');
      return;
    }
    const pin: PinnedPatch = {
      host,
      pathPattern,
      bodyFile,
      contentType: typeof body.contentType === "string" ? body.contentType : "application/octet-stream",
      note: "pinned from capture",
    };
    if (!applyPin(pin)) {
      res.writeHead(500, { "content-type": "application/json" }).end('{"error":"cannot apply pin"}');
      return;
    }
    console.log(`relay: pinned ${host}${pathPattern} -> ${bodyFile}`);
    res.writeHead(200, { "content-type": "application/json" }).end(
      JSON.stringify({ pinned: pin, enabled: true, rules: rules.length }, null, 2),
    );
    return;
  }

  if (path === "/pin/clear" && req.method === "POST") {
    if (!(await controlAllowed(req))) {
      res.writeHead(401, { "content-type": "application/json" }).end(
        '{"error":"unauthorized","hint":"dashboard: ?token=<ADMIN_TOKEN>; menu: sign in"}',
      );
      return;
    }
    if (codepatchFeature) {
      codepatchFeature.rules = codepatchFeature.rules.filter(
        (rule) => rule.note !== "pinned from capture",
      );
    }
    writeFileSync(pinPath, "null");
    rebuildLiveRules();
    res.writeHead(200, { "content-type": "application/json" }).end(
      JSON.stringify({ cleared: true, rules: rules.length }),
    );
    return;
  }

  if (path === "/rules") {
    if (req.method === "POST") {
      if (!(await controlAllowed(req))) {
        res.writeHead(401, { "content-type": "application/json" }).end(
          '{"error":"unauthorized","hint":"dashboard: ?token=<ADMIN_TOKEN>; menu: sign in"}',
        );
        return;
      }
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
      features: featureState(records),
      captures: { total: countCaptures(), recent: records.slice(-15).reverse() },
      suggestions: [...suggestRules(records), ...suggestPatchRules(records)],
    };
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(view));
    return;
  }

  if (path === "/captures/clear" && req.method === "POST") {
    writeFileSync(capturePath, "");
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ cleared: true }));
    return;
  }

  if (path === "/menu") {
    const deviceKey = new URL(req.url ?? "/", "http://x").searchParams.get("k") ?? "";
    const records = readCaptures(4000);
    res
      .writeHead(200, { "content-type": "text/html; charset=utf-8" })
      .end(
        renderMenu({
          name: profileName,
          publicHost,
          proxyPort,
          deviceKey,
          rules,
          captures: { total: countCaptures(), recent: records.slice(-15).reverse() },
          suggestions: [...suggestRules(records), ...suggestPatchRules(records)],
          loginEnabled: Boolean(authAdminToken),
          version,
          features: featureState(records),
        }),
      );
    return;
  }

  const panelPath = path ?? "/";
  if (panelPath === "/panel" || panelPath.startsWith("/panel/")) {
    const name = panelPath === "/panel" || panelPath === "/panel/"
      ? "index.html"
      : panelPath.slice("/panel/".length);
    if (name.includes("..") || name.startsWith("/")) {
      res.writeHead(400, { "content-type": "text/plain" }).end("bad path");
      return;
    }
    const file = join(panelDir, name);
    if (!existsSync(file)) {
      res.writeHead(404, { "content-type": "text/plain" }).end("panel assets missing");
      return;
    }
    const type = panelTypes[extname(file).toLowerCase()] ?? "application/octet-stream";
    res.writeHead(200, { "content-type": type, "cache-control": "no-cache" }).end(readFileSync(file));
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
          suggestions: [...suggestRules(records), ...suggestPatchRules(records)],
          transport: vpn
            ? { kind: vpn.type, server: vpn.server, proxyInTunnel: Boolean(proxies) }
            : undefined,
          menuUrl,
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
