import { type Rule } from "./mitm.js";

/**
 * Menu features, expressed as rules the relay already knows how to apply.
 *
 * A feature is not a UI flag: switching it on installs its rules into the live
 * rule array, so the very next request is blocked or rewritten. Switching it
 * off removes exactly those rules — manual rules are never touched, because
 * they carry no `feature` tag.
 *
 * Nothing here pretends to be an in-game overlay. A proxy can drop a request or
 * edit a response body; it cannot draw ESP. Every switch below changes traffic
 * and nothing else.
 */
export interface Feature {
  id: string;
  label: string;
  detail: string;
  /** Shown with a warning: it can break the game's own login/telemetry path. */
  risky?: boolean;
  rules: Rule[];
}

function block(feature: string, hosts: string[], note: string): Rule[] {
  return hosts.map((host) => ({
    host: `.${host}`,
    pathPattern: "^/",
    action: "block",
    feature,
    note,
  }));
}

const TELEMETRY_HOSTS = [
  // Firebase / Crashlytics
  "app-measurement.com",
  "firebaseinstallations.googleapis.com",
  "firebaselogging.googleapis.com",
  "firebaseremoteconfig.googleapis.com",
  "firebase-settings.crashlytics.com",
  // Attribution + product analytics
  "appsflyer.com",
  "adjust.com",
  "amplitude.com",
  "api.mixpanel.com",
  "api.segment.io",
  "branch.io",
  "app-adforce.jp",
  "google-analytics.com",
  "googletagmanager.com",
];

const AD_HOSTS = ["adv.wfpj.freefiremobile.com", "unityads.unity3d.com"];

/**
 * The three hosts the provider's own DNS guide names as report/security
 * channels. Kept behind `risky` because the same request path also carries
 * session validation on some builds — dropping it can look like a failed login.
 */
const SECURITY_HOSTS = [
  "csoversea.stronghold.freefiremobile.com",
  "gamesecurity.sea.freefiremobile.com",
];

/**
 * Delivery through the game's own hotfix channel.
 *
 * `COW.GameVarDef` carries `CodePatchUrl` and `InjectFixBeforeLaunchGame`, and
 * `COW.COWGameEntry.LoadIFix` applies whatever that URL returns. Those two facts
 * change what "injecting" costs: if the relay rewrites the URL in the var table
 * and answers it, the game downloads and installs the patch itself, through its
 * own loader, into its own sandbox, with its own provenance and timestamps.
 *
 * That is the difference from the container route. A second process writing
 * `Assembly-CSharp-patch.bytes` and a `localConfig.json` full of `SilentAim`
 * keys into another app's Documents is an enumerated, stat-able, never-written-by-the-game
 * artifact — the single loudest thing in the container. Here there is no writer
 * to find.
 *
 * The rules are built from the environment rather than hard-coded, because the
 * var table's host and path are only knowable from a real capture. Set
 * `RELAY_PATCH_HOST` to the host the game fetches code patches from, and
 * `RELAY_VARCONFIG_PATH` to a path regex matching the response that carries the
 * var table, then restart the relay. Until both are set this feature installs no
 * rules and says so, rather than guessing at an endpoint and quietly rewriting
 * nothing.
 */
export function buildPatchRules(): Rule[] {
  const host = process.env.RELAY_PATCH_HOST?.trim().toLowerCase();
  const varPath = process.env.RELAY_VARCONFIG_PATH?.trim();
  const patchFile = process.env.RELAY_PATCH_FILE?.trim();
  if (!host || !varPath || !patchFile) return [];

  const servePath = process.env.RELAY_PATCH_PATH?.trim() || "/cdn/patch/Assembly-CSharp-patch.bytes";
  const rules: Rule[] = [
    {
      host,
      pathPattern: varPath,
      action: "json-merge",
      merge: { CodePatchUrl: `https://${host}${servePath}`, InjectFixBeforeLaunchGame: true },
      feature: "codepatch",
      note: "point the game's own IFix loader at the relay",
    },
    {
      host,
      pathPattern: `^${servePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`,
      action: "respond",
      bodyFile: patchFile,
      contentType: "application/octet-stream",
      feature: "codepatch",
      note: "serve the code patch",
    },
  ];

  // The control document, so the patch can read its settings over the same
  // channel instead of a JSON file sitting in the game's Documents.
  const statePath = process.env.RELAY_STATE_PATH?.trim();
  const stateFile = process.env.RELAY_STATE_FILE?.trim();
  if (statePath && stateFile) {
    rules.push({
      host,
      pathPattern: `^${statePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`,
      action: "respond",
      bodyFile: stateFile,
      contentType: "application/json; charset=utf-8",
      feature: "codepatch",
      note: "serve the live control document",
    });
  }
  return rules;
}

export const FEATURES: Feature[] = [
  {
    id: "telemetry",
    label: "Chặn telemetry",
    detail:
      "Firebase, AppsFlyer, Adjust, Amplitude, Mixpanel, Segment, Branch, Google Analytics. "
      + "Không ảnh hưởng đăng nhập hay vào trận.",
    rules: block("telemetry", TELEMETRY_HOSTS, "telemetry blocked"),
  },
  {
    id: "ads",
    label: "Chặn quảng cáo",
    detail: "Host quảng cáo của game và Unity Ads. Tắt nếu phần thưởng trong game không tải được.",
    rules: block("ads", AD_HOSTS, "ad host blocked"),
  },
  {
    id: "security",
    label: "Chặn kênh báo cáo",
    detail:
      "2 host security/report đã biết. Có thể làm game không đăng nhập được — "
      + "bật sau khi đã chơi được một trận bình thường.",
    risky: true,
    rules: block("security", SECURITY_HOSTS, "report channel blocked"),
  },
  {
    id: "codepatch",
    label: "Game tự tải patch (hotfix channel)",
    detail:
      "Rewrite CodePatchUrl trong bảng var để chính LoadIFix của game tải và áp patch, "
      + "không ghi file vào container. Cần RELAY_PATCH_HOST + RELAY_VARCONFIG_PATH + "
      + "RELAY_PATCH_FILE (lấy từ một phiên capture). Chưa set thì feature này không gắn rule nào.",
    risky: true,
    rules: buildPatchRules(),
  },
];


export function featureById(id: string): Feature | undefined {
  return FEATURES.find((feature) => feature.id === id);
}

/** Rules for the features that are switched on, in a stable order. */
export function rulesForFeatures(enabled: Iterable<string>): Rule[] {
  const on = new Set(enabled);
  return FEATURES.filter((feature) => on.has(feature.id)).flatMap((feature) => feature.rules);
}

/** Per-feature hit counts, from the capture lines the relay already writes. */
export function featureHits(
  records: { features?: string[] }[],
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const record of records) {
    for (const id of record.features ?? []) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
}
