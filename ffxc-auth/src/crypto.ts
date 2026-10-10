import {
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  sign as ed25519Sign,
  type KeyObject,
} from "node:crypto";
import fs from "node:fs";

export function loadPrivateKey(file: string): KeyObject {
  if (!fs.existsSync(file)) {
    throw new Error(`signing key not found at ${file} — run \`npm run mint\` first`);
  }
  return createPrivateKey(fs.readFileSync(file));
}

/** Detached Ed25519 signature over the raw payload bytes. */
export function signPayload(privateKey: KeyObject, payload: Buffer): Buffer {
  return ed25519Sign(null, payload, privateKey);
}

/** The raw 32-byte public key CryptoKit's `rawRepresentation` expects. */
export function rawPublicKey(privateKey: KeyObject): Buffer {
  const publicKey = createPublicKey(privateKey);
  const jwk = publicKey.export({ format: "jwk" }) as { x?: string };
  if (!jwk.x) throw new Error("Ed25519 public key has no x component");
  return Buffer.from(jwk.x, "base64url");
}

export interface MintedKeyPair {
  privateKeyPem: string;
  rawPublic: Buffer;
}

export function generateKeyPair(): MintedKeyPair {
  const { privateKey } = generateKeyPairSync("ed25519");
  const pem = privateKey.export({ format: "pem", type: "pkcs8" }) as string;
  return { privateKeyPem: pem, rawPublic: rawPublicKey(privateKey) };
}
