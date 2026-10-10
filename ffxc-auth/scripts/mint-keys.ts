import fs from "node:fs";
import path from "node:path";
import { generateKeyPair } from "../src/crypto.js";

const outDir = path.resolve("keys");
fs.mkdirSync(outDir, { recursive: true });

const { privateKeyPem, rawPublic } = generateKeyPair();

const privatePath = path.join(outDir, "private.pem");
fs.writeFileSync(privatePath, privateKeyPem, { mode: 0o600 });

const derPath = path.join(outDir, "client_public_key.der");
fs.writeFileSync(derPath, rawPublic);

const bundlePath = path.resolve("..", "YABAOCHEAT", "Resources", "client_public_key.der");
let copied = false;
if (fs.existsSync(path.dirname(bundlePath))) {
  fs.writeFileSync(bundlePath, rawPublic);
  copied = true;
}

console.log("");
console.log("  Ed25519 keypair minted.");
console.log("");
console.log(`  private key  ${privatePath}`);
console.log(`  public key   ${derPath}  (${rawPublic.length} raw bytes)`);
if (copied) console.log(`  installed -> ${bundlePath}`);
else console.log(`  copy ${derPath} into YABAOCHEAT/Resources/client_public_key.der`);
console.log("");
console.log("  Keep private.pem on the server only. Never commit it.");
console.log("  Rebuild the app so the new bundled public key is pinned.");
console.log("");
