import path from "node:path";

function str(name: string, fallback: string): string {
  const raw = process.env[name];
  return raw === undefined || raw === "" ? fallback : raw;
}

function num(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

export const config = {
  host: str("HOST", "0.0.0.0"),
  port: num("PORT", 8787),
  adminToken: str("ADMIN_TOKEN", ""),

  privateKeyPath: path.resolve(str("PRIVATE_KEY_PATH", "keys/private.pem")),
  storePath: path.resolve(str("STORE_PATH", "data/store.json")),

  productId: str("PRODUCT_ID", "pkg_40921350d3307e51491f27cb"),
  protocolVersion: num("PROTOCOL_VERSION", 3),

  heartbeatSeconds: num("HEARTBEAT_SECONDS", 90),
  maxNetworkErrors: num("MAX_NETWORK_ERRORS", 3),
  sessionTtl: num("SESSION_TTL_SECONDS", 3600),
  leaseSeconds: num("LEASE_SECONDS", 300),
  minimumBuild: num("MINIMUM_BUILD", 1),
  securitySchema: num("SECURITY_SCHEMA", 1),

  patchDigest: str("PATCH_DIGEST", ""),
  neutralDigest: str("NEUTRAL_DIGEST", ""),

  keyPrefix: str("KEY_PREFIX", "VT"),
} as const;

export function assertReady(): void {
  if (!config.adminToken) {
    throw new Error("ADMIN_TOKEN is empty — set it before exposing the admin surface");
  }
}
