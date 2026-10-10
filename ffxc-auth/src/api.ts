import type { IncomingMessage, ServerResponse } from "node:http";
import { config } from "./config.js";
import { signPayload } from "./crypto.js";
import { asNumber, asString, readJson, sendJson } from "./http.js";
import type { DeviceRecord, LicenseRecord, Store } from "./store.js";
import { normalizeKey } from "./store.js";
import type { DeploymentBlock, Envelope, LicensePayload } from "./protocol.js";
import type { KeyObject } from "node:crypto";

const nowSec = (): number => Math.floor(Date.now() / 1000);
const iso = (seconds: number): string => new Date(seconds * 1000).toISOString();

function policyBlock(): Envelope["policy"] {
  // The client decodes this as [String: String]; non-string values would fail
  // the whole envelope decode.
  return {
    protocol_version: String(config.protocolVersion),
    heartbeat_seconds: String(config.heartbeatSeconds),
    max_network_errors: String(config.maxNetworkErrors),
    receipt_timeout_seconds: "10",
    receipt_retention_seconds: String(30 * 24 * 60 * 60),
    patch_open_monitor_ms: "2000",
    secure_transport_required: "true",
  };
}

function deploymentBlock(now: number): DeploymentBlock {
  return {
    status: "ok",
    encoding: "application/json",
    protocolVersion: config.protocolVersion,
    minimumBuild: config.minimumBuild,
    securitySchema: config.securitySchema,
    heartbeatSeconds: config.heartbeatSeconds,
    maxNetworkErrors: config.maxNetworkErrors,
    verifiedAt: iso(now),
    validUntil: iso(now + config.leaseSeconds),
  };
}

export class Api {
  constructor(
    private readonly store: Store,
    private readonly privateKey: KeyObject,
  ) {}

  /**
   * Sign a payload and hand it back in the envelope shape `LicensingClient`
   * decodes. Every verdict rides a 200 — terminal codes travel in `status`, the
   * way the client's `adopt`/`acceptHeartbeat` read them. HTTP status is
   * reserved for malformed requests.
   */
  private sendEnvelope(res: ServerResponse, payload: LicensePayload, mac: string | null, sequence: number): void {
    const json = Buffer.from(JSON.stringify(payload), "utf8");
    const signature = signPayload(this.privateKey, json);
    const envelope: Envelope = {
      data: json.toString("base64"),
      ts: nowSec(),
      sig: signature.toString("base64"),
      sequence,
      leaseSeconds: config.leaseSeconds,
      policy: policyBlock(),
    };
    if (mac) envelope.mac = mac;
    sendJson(res, 200, envelope);
  }

  async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const body = await readJson(req);
    if (!body) {
      sendJson(res, 400, { error: "bad_request" });
      return;
    }
    const product = asString(body.product);
    if (product && product !== config.productId) {
      sendJson(res, 403, { error: "product_mismatch" });
      return;
    }

    const key = asString(body.key);
    if (key) {
      this.authorize(res, body, key);
      return;
    }
    const session = asString(body.session);
    if (session) {
      this.heartbeat(res, body, session);
      return;
    }
    sendJson(res, 400, { error: "bad_request" });
  }

  private deny(res: ServerResponse, status: string, message: string, mac: string | null = null): void {
    this.sendEnvelope(res, { status, message }, mac, 0);
  }

  // MARK: - authorize

  private authorize(res: ServerResponse, body: Record<string, unknown>, rawKey: string): void {
    const key = normalizeKey(rawKey);
    const now = nowSec();
    const license = this.store.getLicense(key);

    if (!license) return this.deny(res, "invalid", "License key not recognized.");
    if (license.status === "deleted") return this.deny(res, "deleted", "This key was deleted.");
    if (license.status === "revoked") return this.deny(res, "revoked", "This key has been revoked.");
    if (license.expiresAt !== null && license.expiresAt < now) {
      return this.deny(res, "expired", `This key expired on ${iso(license.expiresAt)}.`);
    }

    const hwid = this.deviceHandle(body);
    if (!hwid) return this.deny(res, "invalid", "Device could not be identified.");

    const existing = license.devices[hwid];
    if (!existing && Object.keys(license.devices).length >= license.maxDevices) {
      const other = Object.values(license.devices)[0];
      const where = other?.deviceName || other?.model || "another device";
      return this.deny(res, "deviceMismatch", `This key is already bound to ${where}.`, asString(body.mac) || null);
    }

    const session = this.store.issueSession(license.key, hwid, config.sessionTtl, config.leaseSeconds);
    const device = this.bindDevice(license, hwid, body, now);

    this.sendEnvelope(
      res,
      {
        status: "valid",
        plan: license.plan,
        licenseLabel: license.key,
        session: session.token,
        sessionTtl: config.sessionTtl,
        sessionExpiresAt: iso(session.expiresAt),
        ...(license.expiresAt !== null ? { expiresAt: iso(license.expiresAt) } : {}),
        ...this.digestMetadata(),
        deployment: deploymentBlock(now),
      },
      device.mac || null,
      session.sequence,
    );
  }

  private deviceHandle(body: Record<string, unknown>): string {
    return (
      asString(body.hwid) ||
      asString(body.device_credential_id) ||
      asString(body.mac)
    );
  }

  private bindDevice(
    license: LicenseRecord,
    hwid: string,
    body: Record<string, unknown>,
    now: number,
  ): DeviceRecord {
    const existing = license.devices[hwid];
    const record: DeviceRecord = existing ?? {
      hwid,
      mac: "",
      credentialId: "",
      publicKey: "",
      deviceName: "",
      iosVersion: "",
      model: "",
      firstSeen: now,
      lastSeen: now,
    };
    record.mac = asString(body.mac) || record.mac;
    record.credentialId = asString(body.device_credential_id) || record.credentialId;
    record.publicKey = asString(body.device_public_key) || record.publicKey;
    record.deviceName = asString(body.device_name) || record.deviceName;
    record.iosVersion = asString(body.ios_version) || record.iosVersion;
    record.model = asString(body.model) || record.model;
    record.lastSeen = now;
    license.devices[hwid] = record;
    void this.store.saveLicense(license);
    return record;
  }

  /** Only pin digests when the operator sets both; otherwise the app keeps its bundle pins. */
  private digestMetadata(): Pick<LicensePayload, "metadata"> {
    if (!config.patchDigest || !config.neutralDigest) return {};
    return { metadata: { digests: { patch: config.patchDigest, neutral: config.neutralDigest } } };
  }

  // MARK: - heartbeat

  private heartbeat(res: ServerResponse, body: Record<string, unknown>, token: string): void {
    const now = nowSec();
    const mac = asString(body.mac) || null;
    const session = this.store.getSession(token);

    if (!session || session.expiresAt < now) {
      if (session) void this.store.removeSession(token);
      return this.deny(res, "sessionInvalid", "Session expired; sign in again.", mac);
    }

    const sequence = asNumber(body.sequence, -1);
    if (sequence <= session.sequence) {
      return this.deny(res, "replayDetected", "Stale heartbeat sequence.", mac);
    }

    const license = this.store.getLicense(session.key);
    if (!license || license.status !== "active") {
      void this.store.removeSession(token);
      const status = license?.status === "deleted" ? "deleted" : "revoked";
      return this.deny(res, status, "This key is no longer active.", mac);
    }
    if (license.expiresAt !== null && license.expiresAt < now) {
      return this.deny(res, "expired", `This key expired on ${iso(license.expiresAt)}.`, mac);
    }

    this.store.touchSession(session, sequence, config.sessionTtl);
    const device = license.devices[session.hwid];

    this.sendEnvelope(
      res,
      {
        status: "valid",
        plan: license.plan,
        licenseLabel: license.key,
        session: session.token,
        sessionTtl: config.sessionTtl,
        sessionExpiresAt: iso(session.expiresAt),
        ...(license.expiresAt !== null ? { expiresAt: iso(license.expiresAt) } : {}),
        deployment: deploymentBlock(now),
      },
      device?.mac || mac,
      sequence,
    );
  }
}
