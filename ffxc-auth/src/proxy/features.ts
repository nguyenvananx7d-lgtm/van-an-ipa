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

/**
 * Layer zero — no patch in the game at all.
 *
 * The 1.132.1 dump shows the game already ships every behaviour a cheat panel
 * sells, gated by values it receives from its own live-ops server:
 *
 *   COW.GameVarDef.EnableShowPlayerOutline      player outline through walls
 *   COW.GameVarDef.ShowPlayerOutline*           range, alpha, width
 *   COW.GameVarDef.EnableStropAimAssist         native aim assist while sliding
 *   COW.GameVarDef.EnableBeAimAssistWhenStropDash
 *   COW.EAimAssist { AllOn=0, OffOnSighting=1, AllOff=2 }
 *
 * The client renders and aims with its own code. We only answer the config
 * request with a document the game could have received from its operator. No
 * code, no file, no hook, no iOS version dependency — and nothing to find in a
 * memory scan because the only "anomaly" is a field value.
 *
 * The rule is deliberately host-agnostic and uses the `**.Key` form: the var
 * table's host and nesting change between releases, the field names do not.
 * `json-set` only touches objects that already carry the key, so a JSON body
 * that merely contains the word is not rewritten.
 */
const OUTLINE_OPS = [
  { path: "**.EnableShowPlayerOutline", value: true },
  { path: "**.EnableOutlineFuncInScript", value: true },
  { path: "**.OutlineVisibleJudgeInUpDate", value: true },
  { path: "**.ShowPlayerOutlineMinDistance", value: 0 },
  { path: "**.ShowPlayerOutlineMaxDistance", value: 400 },
  { path: "**.ShowPlayerOutlineMinAlpha", value: 0.35 },
  { path: "**.ShowPlayerOutlineMaxAlpha", value: 1 },
  { path: "**.ShowPlayerOutlineWidth", value: 2 },
  { path: "**.ShowPlayerOutlineMinWidth", value: 1 },
  { path: "**.ShowPlayerOutlineMaxWidth", value: 4 },
];

const ASSIST_OPS = [
  { path: "**.EnableStropAimAssist", value: true },
  { path: "**.EnableBeAimAssistWhenStropDash", value: true },
];

export function buildNativeEspRules(): Rule[] {
  return [{
    pathPattern: "^/",
    action: "json-set",
    jsonOps: OUTLINE_OPS,
    feature: "native-esp",
    note: "native player outline through the game's own var table",
  }];
}

export function buildAssistRules(): Rule[] {
  const rules: Rule[] = [{
    pathPattern: "^/",
    action: "json-set",
    jsonOps: ASSIST_OPS,
    feature: "native-assist",
    note: "native aim-assist switches through the game's own var table",
  }];

  // Settings sync: `CSPlayerSettingsRes.settings` is a byte array holding
  // `COW.SettingDetail`, whose `aim_assist` is the EAimAssist ordinal. The
  // field number is only knowable from a capture, so this half is opt-in.
  // `RELAY_ASSIST_PROTO=**.16` patches field 16 in every submessage; the
  // operator confirms the number from one capture first.
  const host = process.env.RELAY_ASSIST_HOST?.trim().toLowerCase();
  const pathPattern = process.env.RELAY_ASSIST_PATH?.trim();
  const fieldPath = process.env.RELAY_ASSIST_PROTO?.trim();
  if (host && pathPattern && fieldPath) {
    rules.push({
      host,
      pathPattern,
      action: "proto-set",
      protoOps: [{ path: fieldPath, value: 0, wire: "varint" }],
      feature: "native-assist",
      note: "force EAimAssist.AllOn in the settings blob",
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
  {
    id: "native-esp",
    label: "ESP gốc của game (layer zero)",
    detail:
      "Bật EnableShowPlayerOutline và các tham số outline trong bảng var của chính game. "
      + "Không patch, không file, không hook: game tự vẽ outline bằng code của nó. "
      + "Chỉ sửa response, không đụng client. Không phụ thuộc iOS.",
    rules: buildNativeEspRules(),
  },
  {
    id: "native-assist",
    label: "Trợ thủ gốc của game (layer zero)",
    detail:
      "Bật các cờ aim assist có sẵn trong bảng var (EnableStropAimAssist, "
      + "EnableBeAimAssistWhenStropDash). Tuỳ chọn: đặt RELAY_ASSIST_HOST/PATH/PROTO "
      + "để ép aim_assist=AllOn trong blob settings sau khi đã xác nhận số field "
      + "bằng một phiên capture.",
    rules: buildAssistRules(),
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
