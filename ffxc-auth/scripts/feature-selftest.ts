import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import tls from "node:tls";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadOrCreateAuthority, leafFor } from "../src/proxy/pki.js";
import { createRelay, type Rule } from "../src/proxy/mitm.js";
import { FEATURES, rulesForFeatures } from "../src/proxy/features.js";

/**
 * Proves a menu switch is not decoration.
 *
 * The relay is built exactly as the server builds it — manual rules first,
 * feature rules appended — and the same request is made three times: with the
 * feature off, on, and off again. What the phone would see is asserted each
 * time, along with the capture line the counter is computed from.
 *
 * The test host is local; the feature's real host list is asserted separately,
 * because that part is data, not mechanism.
 */

function listen(server: http.Server | https.Server): Promise<number> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (typeof address === "object" && address) resolve(address.port);
      else reject(new Error("no address"));
    });
  });
}

function close(server: http.Server | https.Server): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

async function main(): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), "feature-selftest-"));
  const ca = loadOrCreateAuthority(join(dir, "ca"));
  const capturePath = join(dir, "capture.jsonl");

  const originLeaf = leafFor(ca, "target.test");
  const origin = https.createServer(
    { key: originLeaf.keyPem, cert: originLeaf.certPem },
    (_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, from: "origin" }));
    },
  );
  const originPort = await listen(origin);

  // A feature rule aimed at the local origin: same shape and tag as the real
  // ones, so the mechanism is exercised end to end.
  const testRule: Rule = {
    host: "target.test",
    pathPattern: "^/track",
    action: "block",
    feature: "telemetry",
    note: "feature-selftest",
  };

  const manual: Rule[] = [];
  const relay = createRelay({
    port: 0,
    ca,
    capturePath,
    upstreamRejectUnauthorized: false,
    upstreamHostFor: () => "127.0.0.1",
    rules: [...manual],
  });

  const relayPort = await new Promise<number>((resolve, reject) => {
    const deadline = Date.now() + 5000;
    const poll = () => {
      if (relay.port > 0) return resolve(relay.port);
      if (Date.now() > deadline) return reject(new Error("relay did not start"));
      setTimeout(poll, 20);
    };
    poll();
  });

  const requestThrough = (path: string): Promise<{ status: number; body: string }> =>
    new Promise((resolve, reject) => {
      const connect = http.request({
        host: "127.0.0.1",
        port: relayPort,
        method: "CONNECT",
        path: `target.test:${originPort}`,
        headers: { host: `target.test:${originPort}` },
      });
      connect.once("error", reject);
      connect.on("connect", (res, socket) => {
        if (res.statusCode !== 200) {
          reject(new Error(`CONNECT refused: ${res.statusCode}`));
          return;
        }
        const secure = tls.connect({ socket, servername: "target.test", ca: ca.certPem });
        secure.once("error", reject);
        secure.once("secureConnect", () => {
          const request = http.request(
            {
              host: `target.test:${originPort}`,
              path,
              method: "GET",
              headers: { host: `target.test:${originPort}` },
              createConnection: () => secure,
            },
            (response) => {
              const chunks: Buffer[] = [];
              response.on("data", (chunk: Buffer) => chunks.push(chunk));
              response.on("end", () =>
                resolve({ status: response.statusCode ?? 0, body: Buffer.concat(chunks).toString("utf8") }),
              );
            },
          );
          request.once("error", reject);
          request.end();
        });
      });
      connect.end();
    });

  const off = await requestThrough("/track/ping");

  // The exact composition the server performs when a switch is turned on.
  relay.setRules([...manual, testRule]);
  const on = await requestThrough("/track/ping");

  relay.setRules([...manual]);
  const offAgain = await requestThrough("/track/ping");

  const lines = readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean);
  const blockedLine = lines
    .map((line) => JSON.parse(line) as Record<string, unknown>)
    .find((record) => record.blocked === true);

  await relay.close();
  await close(origin);
  rmSync(dir, { recursive: true, force: true });

  const security = rulesForFeatures(["security"]);
  const telemetry = rulesForFeatures(["telemetry"]);

  const failures: string[] = [];
  if (off.status !== 200) failures.push(`feature off: expected 200, got ${off.status}`);
  if (on.status !== 204) failures.push(`feature on: expected 204 (blocked), got ${on.status} ${on.body}`);
  if (offAgain.status !== 200) failures.push(`feature off again: expected 200, got ${offAgain.status}`);
  if (!blockedLine) failures.push("capture did not record a blocked request");
  else {
    const features = blockedLine.features as string[] | undefined;
    if (!features?.includes("telemetry")) {
      failures.push(`capture did not tag the feature: ${JSON.stringify(features)}`);
    }
  }
  if (security.length !== 2) failures.push(`security feature should own 2 rules, has ${security.length}`);
  if (telemetry.length < 10) failures.push(`telemetry feature should own its host list, has ${telemetry.length}`);
  if (FEATURES.some((feature) => feature.rules.some((rule) => rule.feature !== feature.id))) {
    failures.push("a feature rule is tagged with the wrong feature id");
  }

  if (failures.length > 0) {
    console.error("feature selftest: FAIL");
    for (const failure of failures) console.error(" -", failure);
    process.exit(1);
  }

  console.log("feature selftest: PASS");
  console.log(`  off=${off.status} on=${on.status} off-again=${offAgain.status}`);
  console.log(`  capture: blocked=${String(blockedLine?.blocked)} features=${JSON.stringify(blockedLine?.features)}`);
  console.log(`  rule counts: telemetry=${telemetry.length} security=${security.length}`);
}

main().catch((error) => {
  console.error("feature selftest: ERROR", error);
  process.exit(1);
});
