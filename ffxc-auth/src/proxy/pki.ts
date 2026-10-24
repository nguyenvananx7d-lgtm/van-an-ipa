import forge from "node-forge";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Certificate authority for the relay.
 *
 * The device trusts this certificate once, and every intercepted host gets a
 * leaf issued from it on demand. That is the whole trick behind the proxy
 * approach: the game keeps talking TLS to what it believes is the real server,
 * while we terminate the connection, read the payload and forward it.
 *
 * The CA lives on disk under `data/ca/` and is created on first boot. It is
 * never regenerated silently: a new CA would invalidate every profile already
 * installed on a device.
 */
export interface Authority {
  certPem: string;
  keyPem: string;
  /** DER, base64 — what a `.mobileconfig` root payload wants. */
  derBase64: string;
}

export interface Leaf {
  certPem: string;
  keyPem: string;
}

const leafCache = new Map<string, Leaf>();

function serialNumber(): string {
  return "0x" + forge.util.bytesToHex(forge.random.getBytesSync(16));
}

function subject(commonName: string): forge.pki.CertificateField[] {
  return [
    { name: "commonName", value: commonName },
    { name: "organizationName", value: "Nimbus Relay" },
    { name: "countryName", value: "VN" },
  ];
}

export function caPaths(dir: string): { cert: string; key: string } {
  return { cert: join(dir, "ca.crt.pem"), key: join(dir, "ca.key.pem") };
}

export function loadOrCreateAuthority(dir: string): Authority {
  mkdirSync(dir, { recursive: true });
  const paths = caPaths(dir);

  if (existsSync(paths.cert) && existsSync(paths.key)) {
    const certPem = readFileSync(paths.cert, "utf8");
    const derBase64 = forge.pki
      .certificateToPem(forge.pki.certificateFromPem(certPem))
      .replace(/-----[^-]+-----/g, "")
      .replace(/\s+/g, "");
    return { certPem, keyPem: readFileSync(paths.key, "utf8"), derBase64 };
  }

  const keys = forge.pki.rsa.generateKeyPair(2048);
  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = serialNumber();
  cert.validity.notBefore = new Date(Date.now() - 24 * 60 * 60 * 1000);
  cert.validity.notAfter = new Date(Date.now() + 10 * 365 * 24 * 60 * 60 * 1000);

  const attrs = subject("Nimbus Relay CA");
  cert.setSubject(attrs);
  cert.setIssuer(attrs);
  cert.setExtensions([
    { name: "basicConstraints", cA: true, critical: true },
    {
      name: "keyUsage",
      keyCertSign: true,
      cRLSign: true,
      digitalSignature: true,
      critical: true,
    },
    { name: "subjectKeyIdentifier" },
  ]);
  cert.sign(keys.privateKey, forge.md.sha256.create());

  const certPem = forge.pki.certificateToPem(cert);
  const keyPem = forge.pki.privateKeyToPem(keys.privateKey);
  writeFileSync(paths.cert, certPem);
  writeFileSync(paths.key, keyPem, { mode: 0o600 });

  return {
    certPem,
    keyPem,
    derBase64: certPem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""),
  };
}

/**
 * Issue (and cache) a leaf for one host. RSA keygen is the expensive part, so a
 * host is generated once per process lifetime; a device playing one match talks
 * to a handful of hosts, not hundreds.
 */
export function leafFor(ca: Authority, host: string): Leaf {
  const cached = leafCache.get(host);
  if (cached) return cached;

  const caCert = forge.pki.certificateFromPem(ca.certPem);
  const caKey = forge.pki.privateKeyFromPem(ca.keyPem);
  const keys = forge.pki.rsa.generateKeyPair(2048);

  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = serialNumber();
  cert.validity.notBefore = new Date(Date.now() - 24 * 60 * 60 * 1000);
  cert.validity.notAfter = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);

  const attrs = subject(host);
  cert.setSubject(attrs);
  cert.setIssuer(caCert.subject.attributes);
  const isIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(host);
  cert.setExtensions([
    { name: "basicConstraints", cA: false, critical: true },
    {
      name: "keyUsage",
      digitalSignature: true,
      keyEncipherment: true,
      critical: true,
    },
    { name: "extKeyUsage", serverAuth: true },
    {
      name: "subjectAltName",
      altNames: [isIp ? { type: 7, ip: host } : { type: 2, value: host }],
    },
  ]);
  cert.sign(caKey, forge.md.sha256.create());

  const leaf: Leaf = {
    certPem: forge.pki.certificateToPem(cert),
    keyPem: forge.pki.privateKeyToPem(keys.privateKey),
  };
  leafCache.set(host, leaf);
  return leaf;
}
