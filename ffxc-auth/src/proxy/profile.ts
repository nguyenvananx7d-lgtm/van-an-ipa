import { createHash } from "node:crypto";
import { type Authority } from "./pki.js";

/**
 * The one file a device has to install.
 *
 * Two payloads matter:
 *   - the root certificate, so TLS terminated by the relay is trusted;
 *   - the tunnel or the proxy setting, so traffic actually arrives at the relay.
 *
 * iOS shows this as "Profile Downloaded" in Settings. The certificate only
 * becomes trusted after the user enables it under
 * Settings → General → About → Certificate Trust Settings — that second step
 * cannot be automated from an app, which is why the relay dashboard prints it.
 */
export interface VpnPayload {
  /** Public hostname or IP of the relay's VPN endpoint. */
  server: string;
  remoteIdentifier: string;
  username: string;
  password: string;
}

export interface ProfileOptions {
  ca: Authority;
  displayName?: string;
  organization?: string;
  /** Manual HTTP proxy applied to one Wi-Fi network. */
  wifi?: { ssid: string; proxyHost: string; proxyPort: number };
  /** IKEv2 tunnel, for traffic that is not on that Wi-Fi (cellular). */
  vpn?: VpnPayload;
}

function stableUuid(seed: string): string {
  const hex = createHash("sha1").update(seed).digest("hex").toUpperCase();
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-");
}

function xmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildMobileConfig(options: ProfileOptions): string {
  const name = options.displayName ?? "Nimbus Relay";
  const organization = options.organization ?? "Nimbus Relay";
  const payloads: string[] = [];

  payloads.push(`    <dict>
      <key>PayloadType</key><string>com.apple.security.root</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.nimbus.relay.ca</string>
      <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-ca")}</string>
      <key>PayloadDisplayName</key><string>${xmlEscape(name)} CA</string>
      <key>PayloadCertificateFileName</key><string>nimbus-relay.cer</string>
      <key>PayloadContent</key><data>${options.ca.derBase64}</data>
    </dict>`);

  if (options.wifi) {
    payloads.push(`    <dict>
      <key>PayloadType</key><string>com.apple.wifi.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.nimbus.relay.wifi</string>
      <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-wifi-" + options.wifi.ssid)}</string>
      <key>PayloadDisplayName</key><string>${xmlEscape(name)} proxy</string>
      <key>SSID_STR</key><string>${xmlEscape(options.wifi.ssid)}</string>
      <key>ProxyType</key><string>Manual</string>
      <key>ProxyServer</key><string>${xmlEscape(options.wifi.proxyHost)}</string>
      <key>ProxyServerPort</key><integer>${options.wifi.proxyPort}</integer>
      <key>ProxyServerPortLegacy</key><integer>${options.wifi.proxyPort}</integer>
    </dict>`);
  }

  if (options.vpn) {
    payloads.push(`    <dict>
      <key>PayloadType</key><string>com.apple.vpn.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.nimbus.relay.vpn</string>
      <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-vpn-" + options.vpn.server)}</string>
      <key>PayloadDisplayName</key><string>${xmlEscape(name)} tunnel</string>
      <key>UserDefinedName</key><string>${xmlEscape(name)}</string>
      <key>VPNType</key><string>IKEv2</string>
      <key>IKEv2</key>
      <dict>
        <key>RemoteAddress</key><string>${xmlEscape(options.vpn.server)}</string>
        <key>RemoteIdentifier</key><string>${xmlEscape(options.vpn.remoteIdentifier)}</string>
        <key>LocalIdentifier</key><string>${xmlEscape(options.vpn.username)}</string>
        <key>AuthenticationMethod</key><string>None</string>
        <key>ExtendedAuthEnabled</key><integer>1</integer>
        <key>AuthName</key><string>${xmlEscape(options.vpn.username)}</string>
        <key>AuthPassword</key><string>${xmlEscape(options.vpn.password)}</string>
        <key>DisableMOBIKE</key><integer>0</integer>
        <key>DisableRedirect</key><integer>0</integer>
        <key>EnablePFS</key><integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>14</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>14</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
      </dict>
    </dict>`);
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>com.nimbus.relay.profile</string>
  <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-profile")}</string>
  <key>PayloadDisplayName</key><string>${xmlEscape(name)}</string>
  <key>PayloadOrganization</key><string>${xmlEscape(organization)}</string>
  <key>PayloadDescription</key><string>Routes the game through the ${xmlEscape(name)} relay. Install, then enable full trust for the certificate under Settings → General → About → Certificate Trust Settings.</string>
  <key>PayloadRemovalDisallowed</key><false/>
  <key>PayloadContent</key>
  <array>
${payloads.join("\n")}
  </array>
</dict>
</plist>
`;
}
