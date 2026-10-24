import { type Rule } from "./mitm.js";

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
