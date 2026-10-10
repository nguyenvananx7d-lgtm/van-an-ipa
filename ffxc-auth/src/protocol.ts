/**
 * Wire types. Field names are the ones `LicenseResponse.swift` decodes with the
 * synthesized `Codable` keys, so they must stay camelCase. The request fields
 * are the ones `LicensingClient.swift` posts.
 */

export interface AuthorizationRequest {
  product?: string;
  key?: string;
  device_credential_id?: string;
  device_public_key?: string;
  hwid?: string;
  mac?: string;
  device_name?: string;
  ios_version?: string;
  model?: string;
  protocol_version?: number;
}

export interface HeartbeatRequest {
  product?: string;
  session?: string;
  sequence?: number;
  mac?: string;
  protocol_version?: number;
}

export interface DeploymentBlock {
  status: "ok" | "updated" | "unchanged" | "unknown";
  encoding: "application/json" | "propertyList";
  url?: string;
  protocolVersion: number;
  minimumBuild: number;
  securitySchema: number;
  heartbeatSeconds: number;
  maxNetworkErrors: number;
  verifiedAt?: string;
  validUntil?: string;
}

export interface CredentialBlock {
  keyId: string;
  deviceCredentialId: string;
  signingHandle: string;
  keyExpiresAt: string;
}

export interface LicensePayload {
  status: string;
  message?: string;
  plan?: string;
  expiresAt?: string;
  metadata?: Record<string, Record<string, string>>;
  session?: string;
  sessionTtl?: number;
  sessionExpiresAt?: string;
  catalog?: unknown[];
  deployment?: DeploymentBlock;
  command?: unknown;
  credential?: CredentialBlock;
  licenseLabel?: string;
}

export interface Envelope {
  data: string;
  ts: number;
  sig: string;
  sequence: number;
  aux?: Record<string, string>;
  leaseSeconds: number;
  mac?: string;
  policy: Record<string, string>;
}
