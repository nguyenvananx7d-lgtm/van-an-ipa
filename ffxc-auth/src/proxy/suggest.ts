import { type Rule } from "./mitm.js";
import { type JsonPathOp } from "./arsenal.js";

/**
 * Turn a capture into candidate rules.
 *
 * The manual part of the relay used to be: play a match, read a few hundred
 * JSON lines, find the anti-cheat report by eye, hand-write a rule. That is the
 * step people get wrong. This module scores what was captured and emits rules
 * that are ready to apply, so the device side never has to look at the log.
 *
 * Scoring is deliberately conservative: a host is only suggested when the
 * request path *and* the body preview both look like the report channel. A
 * wrong rewrite is worse than none — it changes a body the game can verify.
 */

export interface CaptureRecord {
  ts?: string;
  host?: string;
  method?: string;
  path?: string;
  status?: number;
  contentType?: string;
  reqBytes?: number;
  resBytes?: number;
  applied?: string[];
  reqPreview?: string;
  resPreview?: string;
  error?: string;
  blocked?: boolean;
  /** Feature ids whose rules acted on this request. */
  features?: string[];
  /** Host was spliced as raw TCP instead of intercepted. */
  passthrough?: boolean;
  /** Body format the relay detected after decoding. */
  resFormat?: string;
  /** Top-level JSON keys or protobuf field numbers, whichever the body had. */
  resKeys?: string[];
  resFields?: number[];
  /** Size after content-encoding was removed. */
  decodedBytes?: number;
  encoding?: string;
}

export interface Suggestion {
  host: string;
  path: string;
  action: Rule["action"];
  score: number;
  reasons: string[];
  calls: number;
  rule: Rule;
}

const REPORT_HINTS = [
  "check_info",
  "checkinfo",
  "gin",
  "antihack",
  "anti_hack",
  "antihacker",
  "ffanti",
  "md5",
  "signature",
  "report",
  "verify",
  "attest",
];

const PATH_HINTS = ["report", "check", "verify", "gin", "anti", "md5", "sec", "attest"];

function hits(text: string | undefined, needles: string[]): string[] {
  if (!text) return [];
  const lowered = text.toLowerCase();
  return needles.filter((needle) => lowered.includes(needle));
}

/**
 * Group captures by host+path and score them.
 *
 * `minScore` keeps noise out: one field-name match in a 4 MB binary preview is
 * not evidence, whereas a path that says report *and* a body carrying
 * `check_info` is.
 */
export function suggestRules(
  records: CaptureRecord[],
  options: { minScore?: number } = {},
): Suggestion[] {
  const minScore = options.minScore ?? 3;
  const buckets = new Map<string, { records: CaptureRecord[]; score: number; reasons: Set<string> }>();

  for (const record of records) {
    if (!record.host || !record.path || record.error) continue;
    const pathHits = hits(record.path, PATH_HINTS);
    const bodyHits = [
      ...hits(record.reqPreview, REPORT_HINTS),
      ...hits(record.resPreview, REPORT_HINTS),
    ];
    const score = pathHits.length * 2 + bodyHits.length;
    if (score === 0) continue;

    const key = `${record.host}${record.path}`;
    const bucket = buckets.get(key) ?? { records: [], score: 0, reasons: new Set<string>() };
    bucket.records.push(record);
    bucket.score = Math.max(bucket.score, score);
    for (const hit of pathHits) bucket.reasons.add(`path:${hit}`);
    for (const hit of bodyHits) bucket.reasons.add(`body:${hit}`);
    buckets.set(key, bucket);
  }

  const suggestions: Suggestion[] = [];
  for (const [key, bucket] of buckets) {
    if (bucket.score < minScore) continue;
    const first = bucket.records[0];
    if (!first?.host || !first.path) continue;

    // A report body that is JSON gets a field-level clean-up; anything else is
    // left for a human, because guessing at a protobuf layout corrupts it.
    const jsonBody = (first.resPreview ?? "").trimStart().startsWith("{");
    const rule: Rule = jsonBody
      ? {
          host: first.host,
          pathPattern: `^${escapeRegExp(first.path)}$`,
          action: "json-merge",
          merge: neutralFields(first.resPreview),
          note: `suggested from ${bucket.records.length} capture(s) of ${key}`,
        }
      : {
          host: first.host,
          pathPattern: `^${escapeRegExp(first.path)}$`,
          action: "block",
          note: `suggested from ${bucket.records.length} capture(s) of ${key} (non-JSON: review before applying)`,
        };

    suggestions.push({
      host: first.host,
      path: first.path,
      action: rule.action,
      score: bucket.score,
      reasons: [...bucket.reasons].sort(),
      calls: bucket.records.length,
      rule,
    });
  }

  return suggestions.sort((a, b) => b.score - a.score || b.calls - a.calls);
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Self-pin the hotfix route: find the one captured JSON body that carries
 * `CodePatchUrl` (the game's var table) and emit the exact merge rule that
 * points it at the relay's own patch copy. No one reads capture.jsonl by hand
 * any more — play one match, apply the suggestion, done.
 *
 * Only armed when RELAY_PATCH_HOST is set, so a capture-only relay never
 * proposes a rewrite it cannot serve.
 */
export function suggestPatchRules(
  records: CaptureRecord[],
  env: { patchFile?: string } = {},
): Suggestion[] {
  const patchFile = env.patchFile ?? process.env.RELAY_PATCH_FILE;
  if (!patchFile) return [];

  const out: Suggestion[] = [];
  for (const record of records) {
    if (!record.host || !record.path || record.error) continue;
    const preview = record.resPreview ?? "";
    if (!preview.includes("CodePatchUrl")) continue;

    // The var table carries the game's own patch URL verbatim. Instead of
    // rewriting the table (a tamper the game can verify), answer the game AT
    // that URL with our patch: the request, the host, the path and the file
    // are all the game's own — only the bytes differ.
    const match = /CodePatchUrl["'\s:=]+(https?:\/\/[^"'\s,}]+)/i.exec(preview);
    const rawUrl = match?.[1];
    if (!rawUrl) continue;
    let host = "";
    let path = "/";
    try {
      const url = new URL(rawUrl);
      host = url.hostname;
      path = url.pathname + url.search;
    } catch {
      continue;
    }

    out.push({
      host,
      path,
      action: "respond",
      score: 10,
      reasons: ["the game's own patch URL, taken from the var table"],
      calls: 1,
      rule: {
        host,
        pathPattern: `^${escapeRegExp(path)}$`,
        action: "respond",
        bodyFile: patchFile,
        contentType: "application/octet-stream",
        feature: "codepatch",
        note: "serve the patch at the game's real hotfix URL",
      },
    });
  }
  return out;
}

/**
 * Config-plane rules: find the var table in a capture and turn on the native
 * engine features that already exist in the client.
 *
 * The point is that nothing is injected. The table is the same document the
 * game's own live-ops server sends; `**.Key` only updates objects that already
 * carry the key, so an unrelated JSON body with a similar name is left alone.
 * This is why the miner can propose a rule before the schema is known: it does
 * not need the nesting, only the field name.
 */
const OUTLINE_OPS: JsonPathOp[] = [
  { path: "**.EnableShowPlayerOutline", value: true },
  { path: "**.ShowPlayerOutlineMinDistance", value: 0 },
  { path: "**.ShowPlayerOutlineMaxDistance", value: 400 },
  { path: "**.ShowPlayerOutlineMinAlpha", value: 0.35 },
  { path: "**.ShowPlayerOutlineMaxAlpha", value: 1 },
  { path: "**.ShowPlayerOutlineWidth", value: 2 },
  { path: "**.ShowPlayerOutlineMinWidth", value: 1 },
  { path: "**.ShowPlayerOutlineMaxWidth", value: 4 },
];

const AIM_ASSIST_OPS: JsonPathOp[] = [
  { path: "**.EnableStropAimAssist", value: true },
  { path: "**.EnableBeAimAssistWhenStropDash", value: true },
  { path: "**.EnableShowTeamOutline", value: false },
];

export function suggestArsenalRules(records: CaptureRecord[]): Suggestion[] {
  const out: Suggestion[] = [];
  const seen = new Set<string>();
  for (const record of records) {
    if (!record.host || !record.path || record.error) continue;
    const preview = record.resPreview ?? "";
    if (!preview.includes("{")) continue;

    const outline = OUTLINE_OPS.filter((op) => preview.includes(op.path.slice(3)));
    const assist = AIM_ASSIST_OPS.filter((op) => preview.includes(op.path.slice(3)));
    if (outline.length === 0 && assist.length === 0) continue;

    const key = `${record.host}${record.path}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const ops = [...outline, ...assist];
    const rule: Rule = {
      host: record.host,
      pathPattern: `^${escapeRegExp(record.path)}$`,
      action: "json-set",
      jsonOps: ops,
      note: `native engine config from ${key}`,
    };

    out.push({
      host: record.host,
      path: record.path,
      action: "json-set",
      score: 12 + outline.length,
      reasons: [
        "var table captured",
        ...(outline.length > 0 ? ["native player outline (no injection)"] : []),
        ...(assist.length > 0 ? ["native aim assist switches"] : []),
        `encoded=${record.encoding ?? "none"}`,
      ],
      calls: 1,
      rule,
    });
  }
  return out.sort((a, b) => b.score - a.score);
}

/**
 * Pre-fill a merge that neutralises the report-shaped fields it can see.
 *
 * The preview may be truncated, so a parse failure simply yields no fields:
 * applying an empty merge is harmless, applying a guessed key is not.
 */
function neutralFields(preview: string | undefined): Record<string, unknown> {
  const merge: Record<string, unknown> = {};
  if (!preview) return merge;
  let parsed: unknown;
  try {
    parsed = JSON.parse(preview);
  } catch {
    return merge;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return merge;

  for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
    const lowered = key.toLowerCase();
    if (!REPORT_HINTS.some((needle) => lowered.includes(needle))) continue;
    if (typeof value === "string") merge[key] = "";
    else if (typeof value === "number") merge[key] = 0;
    else if (typeof value === "boolean") merge[key] = false;
    else if (Array.isArray(value)) merge[key] = [];
  }
  return merge;
}
