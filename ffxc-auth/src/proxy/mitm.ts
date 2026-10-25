import http from "node:http";
import https from "node:https";
import net from "node:net";
import tls from "node:tls";
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
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

export type RuleAction = "block" | "json-merge" | "text-replace" | "respond";

export interface Rule {
  /** Exact host or suffix (`.example.com`). Omitted matches every host. */
  host?: string;
  /** Regular expression source matched against the request path. */
  pathPattern: string;
  action: RuleAction;
  /** For `json-merge`: shallow merge into a JSON response body. */
  merge?: Record<string, unknown>;
  /** For `text-replace`: literal needle and replacement in the response body. */
  find?: string;
  replace?: string;
  /**
   * For `respond`: the body the relay returns itself, without dialing upstream.
   *
   * This is what turns the relay from a rewriting proxy into a delivery point.
   * The game already fetches its IFix code patch over HTTPS (`GameVarDef.CodePatchUrl`,
   * applied by `COWGameEntry.LoadIFix`), so rewriting that field to a relay path
   * makes the game download and install the patch through its own loader — into
   * its own sandbox, under its own provenance, with its own timestamps. Nothing
   * is written into the container by a second process, which is the artifact a
   * container scan looks for.
   */
  body?: string;
  /** File on disk to serve for `respond`, preferred over `body` when both set. */
  bodyFile?: string;
  /** Content type for `respond`. Defaults to `application/json`. */
  contentType?: string;
  /** HTTP status for `respond`. Defaults to 200. */
  status?: number;
  note?: string;
  /**
   * Which menu feature owns this rule. Tagged rules are managed by the feature
   * switch rather than by hand: toggling a feature adds or removes every rule
   * carrying its id, and a manual edit never removes them.
   */
  feature?: string;
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
  /**
   * Host suffixes that are tunneled raw instead of intercepted.
   *
   * A phone's HTTP proxy sees every connection, including ones that are not
   * HTTP: game transports speak their own framed protocol inside TLS, and
   * terminating those breaks the session for no benefit. A raw TCP splice keeps
   * them working, records that they happened, and leaves the interesting HTTP
   * hosts to the mitm path.
   */
  passthrough?: string[];
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

/** Ids of the features that acted on a request, for per-feature counters. */
function appliedFeatures(hits: Rule[]): string[] {
  const ids = new Set<string>();
  for (const rule of hits) if (rule.feature) ids.add(rule.feature);
  return [...ids];
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
      capture({
        ts: new Date().toISOString(),
        host,
        method: req.method,
        path,
        status: 204,
        blocked: true,
        features: appliedFeatures(rulesHit),
      });
      res.writeHead(204).end();
      return;
    }

    // A `respond` rule wins over forwarding: the relay is the origin for this
    // path. Draining the request body first keeps a client that is still
    // writing from seeing an RST on a keep-alive connection.
    const synthetic = rulesHit.find((rule) => rule.action === "respond");
    if (synthetic) {
      const chunks: Buffer[] = [];
      req.on("data", (chunk: Buffer) => chunks.push(chunk));
      req.on("end", () => {
        serveSynthetic(req, res, host, path, synthetic, rulesHit);
      });
      req.on("error", () => res.destroy());
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

  function serveSynthetic(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    host: string,
    path: string,
    rule: Rule,
    rulesHit: Rule[],
  ) {
    let body: Buffer;
    if (rule.bodyFile) {
      try {
        body = readFileSync(rule.bodyFile);
      } catch (error) {
        // A missing payload file must not look like a successful response: the
        // game would cache an empty patch and apply nothing.
        log(`relay: respond bodyFile unreadable (${rule.bodyFile}): ${(error as Error).message}`);
        res.writeHead(503, { "content-type": "text/plain" }).end("relay: payload unavailable");
        return;
      }
    } else {
      body = Buffer.from(rule.body ?? "{}", "utf8");
    }

    const status = rule.status ?? 200;
    res.writeHead(status, {
      "content-type": rule.contentType ?? "application/json; charset=utf-8",
      "content-length": body.length,
      // A patched binary or a control document that a CDN or the game's own
      // HTTP cache holds on to is a patch that never updates.
      "cache-control": "no-store, max-age=0",
      "access-control-allow-origin": "*",
    });
    res.end(body);

    log(`relay: responded ${status} ${body.length}B for ${host}${path}`);
    capture({
      ts: new Date().toISOString(),
      host,
      method: req.method,
      path,
      status,
      contentType: rule.contentType ?? "application/json",
      synthetic: true,
      resBytes: body.length,
      applied: [`respond(${rule.note ?? rule.pathPattern})`],
      features: appliedFeatures(rulesHit),
    });
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
            features: appliedFeatures(rulesHit),
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
    const targetPort = Number(/(\d+)$/.exec(req.url ?? "")?.[1] ?? 443);
    const passthrough = (config.passthrough ?? []).some((suffix) =>
      suffix.startsWith(".") ? target === suffix.slice(1) || target.endsWith(suffix) : target === suffix,
    );

    if (passthrough) {
      // Raw splice: no certificate, no parsing, byte-for-byte both ways.
      clientSocket.write("HTTP/1.1 200 Connection Established\r\nProxy-Agent: nimbus-relay\r\n\r\n");
      let established = false;
      const upstream = net.connect(targetPort, target, () => {
        established = true;
        if (head && head.length > 0) upstream.write(head);
        clientSocket.pipe(upstream);
        upstream.pipe(clientSocket);
      });
      upstream.on("error", (error) => {
        // A mid-session reset is the device or the server hanging up, which is
        // normal. Only a failure to reach the target is worth a log line.
        if (!established) log(`relay: passthrough failed for ${target}: ${error.message}`);
        clientSocket.destroy();
      });
      clientSocket.on("close", () => upstream.destroy());
      log(`relay: passthrough ${target}:${targetPort}`);
      capture({ ts: new Date().toISOString(), host: target, path: "", passthrough: true });
      return;
    }

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
