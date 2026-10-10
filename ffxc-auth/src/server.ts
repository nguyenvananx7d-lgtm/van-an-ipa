import http from "node:http";
import { assertReady, config } from "./config.js";
import { loadPrivateKey } from "./crypto.js";
import { Store } from "./store.js";
import { Api } from "./api.js";
import { Admin } from "./admin.js";
import { sendJson } from "./http.js";

assertReady();

const store = new Store(config.storePath);
const privateKey = loadPrivateKey(config.privateKeyPath);
const api = new Api(store, privateKey);
const admin = new Admin(store);

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  void dispatch(req, res, url);
});

async function dispatch(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  url: URL,
): Promise<void> {
  try {
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, { ok: true, product: config.productId });
      return;
    }
    if (req.method === "GET" && url.pathname === "/") {
      res.writeHead(302, { location: "/admin" });
      res.end();
      return;
    }
    if (url.pathname === "/api") {
      await api.handle(req, res);
      return;
    }
    if (url.pathname === "/admin" || url.pathname.startsWith("/admin/")) {
      await admin.handle(req, res, url);
      return;
    }
    sendJson(res, 404, { error: "not_found" });
  } catch (error) {
    console.error("[auth] unhandled:", error);
    if (!res.headersSent) sendJson(res, 500, { error: "server_error" });
    else res.end();
  }
}

// Expired sessions never resolve a heartbeat and only bloat the store.
setInterval(() => {
  const removed = store.purgeSessions(Math.floor(Date.now() / 1000));
  if (removed) console.log(`[auth] purged ${removed} expired session(s)`);
}, 60_000).unref();

server.listen(config.port, config.host, () => {
  console.log(`[auth] listening on http://${config.host}:${config.port}`);
  console.log(`[auth] product=${config.productId} protocol=v${config.protocolVersion}`);
  console.log(`[auth] admin console at /admin`);
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    server.close(() => {
      void store.flush().finally(() => process.exit(0));
    });
  });
}
