import fs from "node:fs";
import path from "node:path";
import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import { config } from "./config.js";

export type LicenseStatus = "active" | "revoked" | "deleted";

export interface DeviceRecord {
  hwid: string;
  mac: string;
  credentialId: string;
  publicKey: string;
  deviceName: string;
  iosVersion: string;
  model: string;
  firstSeen: number;
  lastSeen: number;
}

export interface LicenseRecord {
  key: string;
  plan: string;
  status: LicenseStatus;
  expiresAt: number | null;
  maxDevices: number;
  note: string;
  createdAt: number;
  devices: Record<string, DeviceRecord>;
  /** scrypt hash + salt for the second factor the portal asks for. */
  passwordHash?: string;
  passwordSalt?: string;
  /** UTC day (`YYYY-MM-DD`) and count for the two-resets-per-day rule. */
  resetDay?: string;
  resetCount?: number;
}

/** The reference portal allows two device resets per calendar day. */
export const MAX_DEVICE_RESETS_PER_DAY = 2;

export function utcDay(now: number = Date.now()): string {
  return new Date(now).toISOString().slice(0, 10);
}

/** Hash a portal password with a fresh 16-byte salt. */
export function hashPassword(password: string): { hash: string; salt: string } {
  const salt = randomBytes(16).toString("hex");
  return { hash: scryptSync(password, salt, 32).toString("hex"), salt };
}

/**
 * Verify the password sent with an activation or reset.
 *
 * Keys minted before the password column existed have no hash. They keep
 * working without a second factor, so an existing deployment is not locked
 * out by upgrading the backend.
 */
export function verifyPassword(license: LicenseRecord, password: string): boolean {
  if (!license.passwordHash || !license.passwordSalt) return true;
  const expected = Buffer.from(license.passwordHash, "hex");
  const actual = scryptSync(password, license.passwordSalt, expected.length);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/** Resets already spent today, ignoring a counter left over from yesterday. */
export function resetsUsedToday(license: LicenseRecord, now: number = Date.now()): number {
  return license.resetDay === utcDay(now) ? (license.resetCount ?? 0) : 0;
}

export interface SessionRecord {
  token: string;
  key: string;
  hwid: string;
  sequence: number;
  leaseSeconds: number;
  createdAt: number;
  lastSeenAt: number;
  expiresAt: number;
}

interface Database {
  licenses: Record<string, LicenseRecord>;
  sessions: Record<string, SessionRecord>;
}

const KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function randomGroup(len: number): string {
  const bytes = randomBytes(len);
  let out = "";
  for (let i = 0; i < len; i += 1) out += KEY_ALPHABET[bytes[i]! % KEY_ALPHABET.length];
  return out;
}

export function normalizeKey(input: string): string {
  return input.trim().toUpperCase().replace(/\s+/g, "");
}

export class Store {
  private db: Database;
  private queue: Promise<void> = Promise.resolve();

  constructor(private readonly file: string) {
    this.db = this.load();
  }

  private load(): Database {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.file, "utf8")) as Partial<Database>;
      return { licenses: parsed.licenses ?? {}, sessions: parsed.sessions ?? {} };
    } catch {
      return { licenses: {}, sessions: {} };
    }
  }

  /** Serialized, atomic persist so a crash cannot leave a half-written file. */
  private persist(): Promise<void> {
    this.queue = this.queue.then(async () => {
      const dir = path.dirname(this.file);
      await fs.promises.mkdir(dir, { recursive: true });
      const tmp = `${this.file}.${process.pid}.tmp`;
      await fs.promises.writeFile(tmp, JSON.stringify(this.db, null, 2), "utf8");
      await fs.promises.rename(tmp, this.file);
    });
    return this.queue;
  }

  flush(): Promise<void> {
    return this.queue;
  }

  // MARK: licenses

  allLicenses(): LicenseRecord[] {
    return Object.values(this.db.licenses).sort((a, b) => b.createdAt - a.createdAt);
  }

  getLicense(key: string): LicenseRecord | undefined {
    return this.db.licenses[normalizeKey(key)];
  }

  /** A key that never collides with one already stored (or minted earlier in this batch). */
  private freshKey(): string {
    for (let attempt = 0; attempt < 2000; attempt += 1) {
      const groups = attempt < 1000 ? 2 : 3;
      const parts: string[] = [];
      for (let g = 0; g < groups; g += 1) parts.push(randomGroup(4));
      const key = `${config.keyPrefix}-${parts.join("-")}`;
      if (!this.db.licenses[key]) return key;
    }
    // Practically unreachable; keep minting unique instead of looping forever.
    return `${config.keyPrefix}-${Date.now().toString(36).toUpperCase()}-${randomGroup(4)}`;
  }

  /** A hand-typed key: uppercase, spaces become dashes, and the VT- prefix is enforced. */
  private customKey(raw: string): string {
    const cleaned = raw
      .trim()
      .toUpperCase()
      .replace(/\s+/g, "-")
      .replace(/[^A-Z0-9-]/g, "")
      .replace(/-+/g, "-")
      .replace(/^-+|-+$/g, "");
    if (!cleaned) return "";
    const prefix = `${config.keyPrefix}-`;
    return cleaned.startsWith(prefix) ? cleaned : `${prefix}${cleaned}`;
  }

  createLicenses(opts: {
    plan: string;
    expiresAt: number | null;
    maxDevices: number;
    note: string;
    count: number;
    keys?: string[];
    password?: string;
  }): LicenseRecord[] {
    const made: LicenseRecord[] = [];
    const build = (key: string): LicenseRecord => {
      const credential = opts.password ? hashPassword(opts.password) : undefined;
      return {
        key,
        plan: opts.plan,
        status: "active",
        expiresAt: opts.expiresAt,
        maxDevices: opts.maxDevices,
        note: opts.note,
        createdAt: Math.floor(Date.now() / 1000),
        devices: {},
        ...(credential
          ? { passwordHash: credential.hash, passwordSalt: credential.salt }
          : {}),
      };
    };

    // Admin-supplied keys take priority over random ones.
    const wanted = (opts.keys ?? []).map((k) => this.customKey(k)).filter(Boolean);
    if (wanted.length > 0) {
      const seen = new Set<string>();
      for (const key of wanted) {
        if (key.length < 4) throw new Error(`invalid_key:${key}`);
        if (seen.has(key) || this.db.licenses[key]) throw new Error(`key_exists:${key}`);
        seen.add(key);
      }
      for (const key of wanted) {
        const record = build(key);
        this.db.licenses[key] = record;
        made.push(record);
      }
      void this.persist();
      return made;
    }

    const count = Math.min(500, Math.max(1, opts.count));
    for (let i = 0; i < count; i += 1) {
      const key = this.freshKey();
      const record = build(key);
      this.db.licenses[key] = record;
      made.push(record);
    }
    void this.persist();
    return made;
  }

  saveLicense(license: LicenseRecord): Promise<void> {
    this.db.licenses[license.key] = license;
    return this.persist();
  }

  removeLicense(key: string): Promise<void> {
    const normalized = normalizeKey(key);
    delete this.db.licenses[normalized];
    for (const [token, session] of Object.entries(this.db.sessions)) {
      if (session.key === normalized) delete this.db.sessions[token];
    }
    return this.persist();
  }

  removeDevice(licenseKey: string, hwid: string): Promise<void> {
    const license = this.db.licenses[normalizeKey(licenseKey)];
    if (license) delete license.devices[hwid];
    return this.persist();
  }

  // MARK: sessions

  issueSession(key: string, hwid: string, ttl: number, leaseSeconds: number): SessionRecord {
    const now = Math.floor(Date.now() / 1000);
    const token = randomBytes(24).toString("hex");
    const session: SessionRecord = {
      token,
      key: normalizeKey(key),
      hwid,
      sequence: -1,
      leaseSeconds,
      createdAt: now,
      lastSeenAt: now,
      expiresAt: now + ttl,
    };
    this.db.sessions[token] = session;
    void this.persist();
    return session;
  }

  getSession(token: string): SessionRecord | undefined {
    return this.db.sessions[token];
  }

  allSessions(): SessionRecord[] {
    return Object.values(this.db.sessions).sort((a, b) => b.lastSeenAt - a.lastSeenAt);
  }

  touchSession(session: SessionRecord, sequence: number, ttl: number): Promise<void> {
    session.sequence = sequence;
    session.lastSeenAt = Math.floor(Date.now() / 1000);
    session.expiresAt = session.lastSeenAt + ttl;
    return this.persist();
  }

  removeSession(token: string): Promise<void> {
    delete this.db.sessions[token];
    return this.persist();
  }

  purgeSessions(now: number): number {
    let removed = 0;
    for (const [token, session] of Object.entries(this.db.sessions)) {
      if (session.expiresAt < now) {
        delete this.db.sessions[token];
        removed += 1;
      }
    }
    if (removed) void this.persist();
    return removed;
  }
}
