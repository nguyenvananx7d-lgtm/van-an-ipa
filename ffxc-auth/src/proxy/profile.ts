import { createHash } from "node:crypto";
import { type Authority } from "./pki.js";

/**
 * The one file a device has to install.
 *
 * Four payloads matter, and they only work as a set:
 *   - the root certificate, so TLS terminated by the relay is trusted;
 *   - the VPN, so the device has a route to the relay from anywhere, including
 *     cellular;
 *   - the proxy, carried *inside* the VPN payload, so iOS applies it for the
 *     lifetime of the tunnel instead of per-Wi-Fi;
 *   - the web clip, so the operator has a control surface on the home screen
 *     without shipping an app.
 *
 * The certificate only becomes trusted after the user enables it under
 * Settings → General → About → Certificate Trust Settings — that second step
 * cannot be automated from an app, which is why the dashboard prints it and
 * the profile's ConsentText repeats it.
 */

export interface ProxySettings {
  host: string;
  port: number;
  /** Hosts that bypass the proxy. iOS defaults to loopback only. */
  exceptions?: string[];
}

export interface IkeV2Payload {
  type: "ikev2";
  server: string;
  remoteIdentifier: string;
  username: string;
  password: string;
}

/**
 * L2TP over IPsec, authenticated with a shared secret and MSCHAPv2.
 *
 * Chosen over IKEv2 when the server is a stock Linux box: `strongswan` +
 * `xl2tpd` is a two-package install, while IKEv2 EAP needs certificates or a
 * radius backend. iOS still ships the client.
 */
export interface L2tpPayload {
  type: "l2tp";
  server: string;
  username: string;
  password: string;
  /** IPsec pre-shared key. Written into the profile as base64 <data>. */
  sharedSecret: string;
}

export type VpnPayload = IkeV2Payload | L2tpPayload;

export interface WebClipPayload {
  /** Absolute https URL. Safari-based web clip, not an installed app. */
  url: string;
  label: string;
}

export interface ProfileOptions {
  ca: Authority;
  displayName?: string;
  organization?: string;
  /** Shown by iOS before the install prompt. Plain text, newlines preserved. */
  consent?: string;
  /** Manual HTTP proxy applied to one Wi-Fi network (no-VPN deployments). */
  wifi?: { ssid: string; proxyHost: string; proxyPort: number };
  /**
   * Proxy the user has to enter by hand when no VPN and no Wi-Fi payload is
   * generated. Baking the values into the description means the instruction
   * cannot drift from the relay.
   */
  manualProxy?: { host: string; port: number };
  vpn?: VpnPayload;
  /** Proxy applied for the lifetime of the tunnel. Only emitted with a VPN. */
  proxies?: ProxySettings;
  webclip?: WebClipPayload;
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

function proxyPayload(proxy: ProxySettings, indent: string): string {
  const exceptions = proxy.exceptions ?? ["localhost", "127.0.0.1", "*.local"];
  const exceptionXml = exceptions
    .map((host) => `${indent}    <string>${xmlEscape(host)}</string>`)
    .join("\n");
  return `${indent}<key>Proxies</key>
${indent}<dict>
${indent}  <key>HTTPEnable</key><integer>1</integer>
${indent}  <key>HTTPProxy</key><string>${xmlEscape(proxy.host)}</string>
${indent}  <key>HTTPPort</key><integer>${proxy.port}</integer>
${indent}  <key>HTTPSEnable</key><integer>1</integer>
${indent}  <key>HTTPSProxy</key><string>${xmlEscape(proxy.host)}</string>
${indent}  <key>HTTPSPort</key><integer>${proxy.port}</integer>
${indent}  <key>ProxyAutoConfigEnable</key><integer>0</integer>
${indent}  <key>ExceptionsList</key>
${indent}  <array>
${exceptionXml}
${indent}  </array>
${indent}</dict>`;
}

function ikev2Body(vpn: IkeV2Payload, name: string, proxies: ProxySettings | undefined): string {
  const proxyXml = proxies ? `\n${proxyPayload(proxies, "      ")}` : "";
  return `      <key>UserDefinedName</key><string>${xmlEscape(name)}</string>
      <key>VPNType</key><string>IKEv2</string>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key><integer>1</integer>
      </dict>${proxyXml}
      <key>IKEv2</key>
      <dict>
        <key>RemoteAddress</key><string>${xmlEscape(vpn.server)}</string>
        <key>RemoteIdentifier</key><string>${xmlEscape(vpn.remoteIdentifier)}</string>
        <key>LocalIdentifier</key><string>${xmlEscape(vpn.username)}</string>
        <key>AuthenticationMethod</key><string>None</string>
        <key>ExtendedAuthEnabled</key><integer>1</integer>
        <key>AuthName</key><string>${xmlEscape(vpn.username)}</string>
        <key>AuthPassword</key><string>${xmlEscape(vpn.password)}</string>
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
      </dict>`;
}

function l2tpBody(vpn: L2tpPayload, name: string, proxies: ProxySettings | undefined): string {
  const secretBase64 = Buffer.from(vpn.sharedSecret, "utf8").toString("base64");
  const proxyXml = proxies ? `\n${proxyPayload(proxies, "      ")}` : "";
  return `      <key>UserDefinedName</key><string>${xmlEscape(name)}</string>
      <key>VPNType</key><string>L2TP</string>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key><integer>1</integer>
      </dict>
      <key>PPP</key>
      <dict>
        <key>AuthName</key><string>${xmlEscape(vpn.username)}</string>
        <key>AuthPassword</key><string>${xmlEscape(vpn.password)}</string>
        <key>AuthProtocol</key>
        <array>
          <string>MSCHAP2</string>
        </array>
        <key>CommRemoteAddress</key><string>${xmlEscape(vpn.server)}</string>
      </dict>
      <key>IPSec</key>
      <dict>
        <key>AuthenticationMethod</key><string>SharedSecret</string>
        <key>SharedSecret</key>
        <data>${secretBase64}</data>
      </dict>${proxyXml}
      <key>OnDemandEnabled</key><integer>0</integer>`;
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
      <key>PayloadOrganization</key><string>${xmlEscape(organization)}</string>
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
    const body =
      options.vpn.type === "l2tp"
        ? l2tpBody(options.vpn, name, options.proxies)
        : ikev2Body(options.vpn, name, options.proxies);
    payloads.push(`    <dict>
      <key>PayloadType</key><string>com.apple.vpn.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.nimbus.relay.vpn</string>
      <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-vpn-" + options.vpn.server)}</string>
      <key>PayloadDisplayName</key><string>${xmlEscape(name)} VPN</string>
      <key>PayloadOrganization</key><string>${xmlEscape(organization)}</string>
${body}
    </dict>`);
  }

  if (options.webclip) {
    payloads.push(`    <dict>
      <key>PayloadType</key><string>com.apple.webClip.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>com.nimbus.relay.webclip</string>
      <key>PayloadUUID</key><string>${stableUuid("nimbus-relay-webclip-" + options.webclip.url)}</string>
      <key>PayloadDisplayName</key><string>${xmlEscape(options.webclip.label)}</string>
      <key>Label</key><string>${xmlEscape(options.webclip.label)}</string>
      <key>URL</key><string>${xmlEscape(options.webclip.url)}</string>
      <key>IsRemovable</key><true/>
      <key>FullScreen</key><true/>
      <key>Precomposed</key><true/>
      <key>IgnoreManifestScope</key><true/>
    </dict>`);
  }

  const description = options.vpn
    ? `Chứng chỉ và VPN cho ${name}. Sau khi cài: bật tin cậy chứng chỉ trong `
      + `Cài đặt → Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng chỉ, `
      + `rồi vào Cài đặt → VPN và bật ${name} VPN. Đóng hẳn game và mở lại.`
    : options.manualProxy
      ? `Chứng chỉ cho proxy ${name}. Sau khi cài, bật tin cậy chứng chỉ trong `
        + `Cài đặt iPhone (Cài đặt → Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng chỉ), `
        + `rồi nhập proxy thủ công trong Wi-Fi: server ${options.manualProxy.host}, `
        + `cổng ${options.manualProxy.port}.`
      : `Chứng chỉ cho proxy ${name}. Sau khi cài, bật tin cậy chứng chỉ trong Cài đặt iPhone.`;

  const consent = options.consent
    ? `
  <key>ConsentText</key>
  <dict>
    <key>default</key><string>${xmlEscape(options.consent)}</string>
  </dict>`
    : "";

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
  <key>PayloadDescription</key><string>${xmlEscape(description)}</string>
  <key>PayloadRemovalDisallowed</key><false/>${consent}
  <key>PayloadContent</key>
  <array>
${payloads.join("\n")}
  </array>
</dict>
</plist>
`;
}
