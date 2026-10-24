import http from "node:http";
import https from "node:https";
import tls from "node:tls";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { type Authority, leafFor } from "./pki.js";

/**
 * Transparent TLS relay for the device.
 *
 * The phone installs one root certificate and points its traffic here. For every
 * `CONNECT host:443` the relay answers in plain text, then speaks TLS to the
 * client with a leaf issued for that host — so the game believes it is talking
 * to the real server — and opens its own TLS connection upstream. Requests and
 * responses pass through unmodified unless a rule says otherwise.
 *
 * Two things this buys over a memory patch:
 *   - the client binary is untouched, so no code hash, hook scan or memory check
 *     has anything to find;
 *   - the anti-cheat report is just another body, and a body can be edited.
 *
 * Capture mode (no rules) is the default on purpose: the endpoints and the
 * report format live in native code, so the first session has to record traffic
 * before any rewrite can be written.
 */

export type RuleAction = "block" | "json-merge" | "text-replace";

export interface Rule {
  /** Exact host or suffix (`".example.com"`). Omitted matches every host. */
  host?: string;
  /** Regular expression source matched against the request path. */
  pathPattern: string;
  action: RuleAction;
  /** For `json-merge`: shallow merge into a JSON response body. */
  merge?: Record<string, unknown>;
  /** For `text-replace`: literal needle and replacement in the response body. */
  find?: string;
  replace?: string;
  note?: string;
}

export interface RelayConfig {
  port: number;
  ca: Authority;
  /** JSONL capture file. `""` disables capture. */
  capturePath: string;
  rules?: Rule[];
  /** Bodies above this many bytes are forwarded unmodified and not captured. */
  maxBody?: number;
  /** Preview bytes kept per direction in the capture file. */
  previewBytes?: number;
  /** Upstream verification. Off only for local self-tests. */
  upstreamRejectUnauthorized?: boolean;
  /**
   * Rewrite the address the relay dials, while TLS still uses the original SNI.
   * Used by the self-test (a fake host that only exists on loopback) and by
   * pinning workarounds that need to reach a specific edge node.
   */
  upstreamHostFor?: (host: string) => string;
  log?: (line: string) => void;
}

export interface RelayHandle {
  readonly port: number;
  /** Replace the active rules without dropping connections. */
  setRules: (next: Rule[]) => void;
  close: () => Promise<void>;
}

function hostOnly(value: string | undefined): string {
  if (!value) return "";
  return value.trim().toLowerCase().replace(/:\d+$/, "");
}

/** Split a `Host` header into host and port (default 443). */
function hostAndPort(value: string | undefined, fallback: number): { host: string; port: number } {
  const raw = (value ?? "").trim().toLowerCase();
  const match = /^(.+?):(\d+)$/.exec(raw);
  if (match) return { host: match[1] ?? "", port: Number(match[2] ?? fallback) };
  return { host: raw, port: fallback };
}

function hostMatches(rule: Rule, host: string): boolean {
  if (!rule.host) return true;
  const want = rule.host.toLowerCase();
  if (want.startsWith(".")) return host === want.slice(1) || host.endsWith(want);
  return host === want;
}

function rulesFor(rules: Rule[], host: string, path: string): Rule[] {
  return rules.filter((rule) => {
    if (!hostMatches(rule, host)) return false;
    try {
      return new RegExp(rule.pathPattern).test(path);
    } catch {
      return false;
    }
  });
}

function preview(buffer: Buffer, limit: number): string {
  const slice = buffer.subarray(0, limit);
  const text = slice.toString("utf8");
  // Text travels as text so the capture stays readable; anything that is not
  // valid UTF-8 becomes base64, which keeps binary protocols inspectable.
  return Buffer.from(text, "utf8").equals(slice)
    ? text
    : `base64:${slice.toString("base64")}`;
}

export function createRelay(config: RelayConfig): RelayHandle {
  const maxBody = config.maxBody ?? 4 * 1024 * 1024;
  const previewBytes = config.previewBytes ?? 2048;
  const rules = config.rules ?? [];
  const log = config.log ?? (() => {});
  if (config.capturePath) mkdirSync(dirname(config.capturePath), { recursive: true });

  const capture = (record: Record<string, unknown>) => {
    if (!config.capturePath) return;
    appendFileSync(config.capturePath, JSON.stringify(record) + "\n");
  };

  const fallback = leafFor(config.ca, "relay.invalid");
  const mitm = https.createServer(
    {
      key: fallback.keyPem,
      cert: fallback.certPem,
      SNICallback: (servername, cb) => {
        try {
          const leaf = leafFor(config.ca, servername);
          cb(null, tls.createSecureContext({ key: leaf.keyPem, cert: leaf.certPem }));
        } catch (error) {
          cb(error as Error);
        }
      },
    },
    (req, res) => {
      const target = hostAndPort(req.headers.host, 443);
      handleRequest(req, res, target.host, target.port);
    },
  );

  function handleRequest(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    host: string,
    port: number,
  ) {
    const path = req.url ?? "/";
    const rulesHit = rulesFor(rules, host, path);
    if (rulesHit.some((rule) => rule.action === "block")) {
      log(`relay: blocked ${host}${path} by rule`);
      capture({ ts: new Date().toISOString(), host, method: req.method, path, status: 204, blocked: true });
      res.writeHead(204).end();
      return;
    }

    const chunks: Buffer[] = [];
    let buffered = 0;
    let overflow = false;
    req.on("data", (chunk: Buffer) => {
      if (overflow) return;
      buffered += chunk.length;
      if (buffered > maxBody) {
        overflow = true;
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      const requestBody = overflow ? Buffer.alloc(0) : Buffer.concat(chunks);
      forward(req, res, host, port, path, requestBody, overflow, rulesHit);
    });
    req.on("error", () => res.destroy());
  }

  function forward(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    host: string,
    port: number,
    path: string,
    requestBody: Buffer,
    streaming: boolean,
    rulesHit: Rule[],
  ) {
    const headers: http.OutgoingHttpHeaders = { ...req.headers };
    delete headers["proxy-connection"];
    delete headers["proxy-authorization"];
    delete headers.connection;
    delete headers["transfer-encoding"];
    // Plain bodies only: a gzip stream cannot be inspected or rewritten.
    headers["accept-encoding"] = "identity";
    if (!streaming && requestBody.length > 0) {
      headers["content-length"] = requestBody.length;
    }

    const upstream = https.request(
      {
        host: config.upstreamHostFor?.(host) ?? host,
        port,
        path,
        method: req.method,
        headers,
        servername: host,
        rejectUnauthorized: config.upstreamRejectUnauthorized !== false,
        timeout: 30_000,
      },
      (upstreamRes) => {
        const contentType = String(upstreamRes.headers["content-type"] ?? "");
        const worth = /json|text|javascript|xml/i.test(contentType);
        const chunks: Buffer[] = [];
        let buffered = 0;
        let overflow = !worth;

        upstreamRes.on("data", (chunk: Buffer) => {
          if (!overflow) {
            buffered += chunk.length;
            if (buffered > maxBody) {
              overflow = true;
            } else {
              chunks.push(chunk);
              return;
            }
          }
          // Overflow: stop buffering and flush what we have, then stream.
          if (buffered > 0) {
            res.write(Buffer.concat(chunks));
            chunks.length = 0;
          }
          res.write(chunk);
        });

        upstreamRes.on("end", () => {
          const body = overflow ? Buffer.alloc(0) : Buffer.concat(chunks);
          const applied: string[] = [];
          let out = body;

          for (const rule of rulesHit) {
            if (rule.action === "json-merge" && rule.merge) {
              try {
                const parsed = JSON.parse(body.toString("utf8")) as Record<string, unknown>;
                Object.assign(parsed, rule.merge);
                out = Buffer.from(JSON.stringify(parsed), "utf8");
                applied.push(`json-merge(${rule.note ?? rule.pathPattern})`);
              } catch {
                log(`relay: json-merge skipped for ${host}${path} — body is not JSON`);
              }
            }
            if (rule.action === "text-replace" && rule.find) {
              const text = out.toString("utf8");
              if (text.includes(rule.find)) {
                out = Buffer.from(text.split(rule.find).join(rule.replace ?? ""), "utf8");
                applied.push(`text-replace(${rule.note ?? rule.find})`);
              }
            }
          }

          const responseHeaders: http.OutgoingHttpHeaders = { ...upstreamRes.headers };
          delete responseHeaders["transfer-encoding"];
          delete responseHeaders["content-encoding"];
          if (!overflow && out !== body) {
            responseHeaders["content-length"] = out.length;
            applied.push("length-fixed");
          }

          res.writeHead(upstreamRes.statusCode ?? 502, responseHeaders);
          res.end(overflow ? undefined : out);

          capture({
            ts: new Date().toISOString(),
            host,
            method: req.method,
            path,
            status: upstreamRes.statusCode,
            contentType,
            reqBytes: requestBody.length,
            resBytes: overflow ? buffered : body.length,
            applied,
            reqPreview: requestBody.length ? preview(requestBody, previewBytes) : undefined,
            resPreview: !overflow && body.length ? preview(body, previewBytes) : undefined,
          });
        });

        upstreamRes.on("error", (error) => {
          log(`relay: upstream response error for ${host}${path}: ${error.message}`);
          res.destroy();
        });
      },
    );

    upstream.on("timeout", () => {
      upstream.destroy(new Error("upstream timeout"));
    });
    upstream.on("error", (error) => {
      log(`relay: upstream failed for ${host}${path}: ${error.message}`);
      capture({ ts: new Date().toISOString(), host, path, error: error.message });
      if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
      res.end("relay: upstream failed");
    });

    if (streaming) {
      req.pipe(upstream);
    } else {
      upstream.end(requestBody);
    }
  }

  // The CONNECT side: answer in plain text, then hand the socket to the TLS
  // server so the client's handshake lands on the per-host certificate.
  const proxy = http.createServer((req, res) => {
    res.writeHead(405, { "content-type": "text/plain" }).end("relay: CONNECT only");
  });
  proxy.on("connect", (req, clientSocket, head) => {
    const target = hostOnly(req.url);
    clientSocket.write("HTTP/1.1 200 Connection Established\r\nProxy-Agent: nimbus-relay\r\n\r\n");
    if (head && head.length > 0) clientSocket.unshift(head);
    log(`relay: tunnel ${target}`);
    mitm.emit("connection", clientSocket);
  });
  proxy.on("clientError", (error, socket) => {
    log(`relay: client error ${error.message}`);
    socket.destroy();
  });

  proxy.listen(config.port, () => {
    log(`relay: listening on ${handle.port} (capture: ${config.capturePath || "off"})`);
  });

  const handle: RelayHandle = {
    get port(): number {
      const address = proxy.address();
      return typeof address === "object" && address ? address.port : config.port;
    },
    // Rules are read per request from this array, so replacing its contents is a
    // live update: no restart, no dropped tunnel, no lost match.
    setRules: (next: Rule[]) => {
      // Snapshot first: callers pass the very array this replaces (the server's
      // live list), and clearing it before reading would wipe the update.
      const snapshot = next.slice();
      rules.length = 0;
      rules.push(...snapshot);
      log(`relay: rules updated (${rules.length} active)`);
    },
    close: () =>
      new Promise<void>((resolve) => {
        proxy.close(() => {
          mitm.close(() => resolve());
        });
      }),
  };
  return handle;
}
