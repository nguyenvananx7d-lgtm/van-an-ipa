import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import tls from "node:tls";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadOrCreateAuthority, leafFor } from "../src/proxy/pki.js";
import { createRelay } from "../src/proxy/mitm.js";

/**
 * End-to-end check for the relay, with no network and no device:
 *
 *   client --CONNECT--> relay --TLS--> origin
 *
 * The origin is a local HTTPS server holding a leaf from the same CA, so the
 * whole path (interception, leaf issuance, upstream verification, rule
 * application, capture) is exercised exactly as it will be on a phone.
 *
 * Phase two replaces the rule set through `setRules` — the call the dashboard's
 * Apply button makes — and asserts the next request already obeys it. That is
 * the regression for an aliasing bug where the live list was cleared before it
 * was read, so every "Apply" emptied the rules instead of installing them.
 */

function listen(server: http.Server | https.Server, port = 0): Promise<number> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => {
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
  const dir = mkdtempSync(join(tmpdir(), "relay-selftest-"));
  const ca = loadOrCreateAuthority(join(dir, "ca"));
  const capturePath = join(dir, "capture.jsonl");

  const originLeaf = leafFor(ca, "target.test");
  const origin = https.createServer(
    { key: originLeaf.keyPem, cert: originLeaf.certPem },
    (_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, verdict: "flagged", note: "origin" }));
    },
  );
  const originPort = await listen(origin);

  const relay = createRelay({
    port: 0,
    ca,
    capturePath,
    upstreamRejectUnauthorized: false,
    upstreamHostFor: () => "127.0.0.1",
    rules: [
      {
        host: "target.test",
        pathPattern: "^/api/status",
        action: "json-merge",
        merge: { verdict: "clean" },
        note: "selftest",
      },
    ],
    log: (line) => {
      if (process.env.RELAY_SELFTEST_VERBOSE) console.log(line);
    },
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

  const requestThrough = (path: string): Promise<string> =>
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
              response.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
            },
          );
          request.once("error", reject);
          request.end();
        });
      });
      connect.end();
    });

  const first = JSON.parse(await requestThrough("/api/status")) as Record<string, unknown>;

  // Live replacement, exactly as the dashboard applies a suggestion.
  relay.setRules([
    {
      host: "target.test",
      pathPattern: "^/api/status",
      action: "json-merge",
      merge: { verdict: "second" },
      note: "reload",
    },
  ]);
  const second = JSON.parse(await requestThrough("/api/status")) as Record<string, unknown>;

  const captured = readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean);
  const last = JSON.parse(captured[captured.length - 1] ?? "{}") as Record<string, unknown>;

  await relay.close();
  await close(origin);
  rmSync(dir, { recursive: true, force: true });

  const failures: string[] = [];
  if (first.verdict !== "clean") failures.push(`first request not rewritten: ${JSON.stringify(first)}`);
  if (second.verdict !== "second") failures.push(`setRules did not take effect: ${JSON.stringify(second)}`);
  if (last.host !== "target.test") failures.push("capture did not record the host");
  if (!Array.isArray(last.applied) || (last.applied as string[]).length === 0) {
    failures.push("capture did not record the applied rule");
  }

  if (failures.length > 0) {
    console.error("relay selftest: FAIL");
    for (const failure of failures) console.error(" -", failure);
    process.exit(1);
  }

  console.log("relay selftest: PASS");
  console.log(`  phase 1 rewrite: ${JSON.stringify(first)}`);
  console.log(`  phase 2 after setRules: ${JSON.stringify(second)}`);
  console.log(`  capture: ${String(last.host)}${String(last.path)} applied ${(last.applied as string[]).join(", ")}`);
}

main().catch((error) => {
  console.error("relay selftest: ERROR", error);
  process.exit(1);
});
