import {
  brotliCompressSync,
  brotliDecompressSync,
  deflateSync,
  gunzipSync,
  gzipSync,
  inflateSync,
} from "node:zlib";

/**
 * Body arsenal: the part of the relay that edits what the server sent.
 *
 * The first generation of this relay only understood a top-level JSON object
 * (`json-merge`) and plain text. The interesting documents do not look like
 * that: the game's var table is nested JSON, the settings sync carries a
 * protobuf blob inside a byte array, and both arrive compressed whenever the
 * client asks for it. This module decodes the transport, finds the field by
 * path, rewrites it, re-encodes it with the *same* content encoding, and lets
 * the client believe the origin said it.
 *
 * Nothing here patches the client. A field the server owns is set to a value
 * the server could have sent; the client's own code decides what to do with it.
 * That is the whole point of the config plane (see `LAYER_ZERO.md`).
 */

export type BodyEncoding = "" | "gzip" | "deflate" | "br" | "identity";
export type BodyFormat = "json" | "protobuf" | "text" | "binary" | "empty";

export interface JsonPathOp {
  /** `a.b[0].c`, or `**.Key` to set every object that already carries `Key`. */
  path: string;
  value: unknown;
}

export interface ProtoPathOp {
  /** Dotted field numbers: `16`, `3.2`, or `**.16` for any submessage. */
  path: string;
  value: number | string | boolean;
  wire?: "auto" | "varint" | "string" | "bytes" | "fixed32" | "fixed64";
  /** How a string value is turned into bytes. Defaults to utf8. */
  encoding?: "utf8" | "base64" | "hex";
}

export interface ArsenalRule {
  action: string;
  merge?: Record<string, unknown>;
  jsonOps?: JsonPathOp[];
  protoOps?: ProtoPathOp[];
  find?: string;
  replace?: string;
  note?: string;
}

export interface BodyDescription {
  format: BodyFormat;
  keys: string[];
  fields: number[];
  bytes: number;
}

export interface BodyRewrite {
  body: Buffer;
  applied: string[];
  format: BodyFormat;
  changed: boolean;
}

// ---------------------------------------------------------------------------
// transport

/** Strip one content-encoding layer. Unknown encodings are returned untouched. */
export function decodeBody(
  raw: Buffer,
  contentEncoding: string | undefined,
): { data: Buffer; encoding: BodyEncoding } {
  if (raw.length === 0) return { data: raw, encoding: "" };
  const header = (contentEncoding ?? "").trim().toLowerCase();
  const last = header.split(",").map((part) => part.trim()).filter(Boolean).pop() ?? "";
  try {
    if (last === "br") return { data: brotliDecompressSync(raw), encoding: "br" };
    if (last === "gzip" || last === "x-gzip") return { data: gunzipSync(raw), encoding: "gzip" };
    if (last === "deflate") return { data: inflateSync(raw), encoding: "deflate" };
  } catch {
    // A server that lied about the encoding is not worth crashing the tunnel
    // over: hand back the bytes and let the rule layer report "not rewritable".
    return { data: raw, encoding: "" };
  }
  return { data: raw, encoding: "" };
}

export function encodeBody(data: Buffer, encoding: BodyEncoding): Buffer {
  if (data.length === 0) return data;
  switch (encoding) {
    case "br": return brotliCompressSync(data);
    case "gzip": return gzipSync(data);
    case "deflate": return deflateSync(data);
    default: return data;
  }
}

// ---------------------------------------------------------------------------
// format detection

function tryJson(data: Buffer): unknown | undefined {
  if (data.length === 0 || data.length > 8 * 1024 * 1024) return undefined;
  const first = data[0];
  if (first !== 0x7b && first !== 0x5b && first !== 0x22) return undefined;
  try {
    return JSON.parse(data.toString("utf8")) as unknown;
  } catch {
    return undefined;
  }
}

export function detectFormat(data: Buffer, contentType: string): BodyFormat {
  if (data.length === 0) return "empty";
  if (tryJson(data) !== undefined) return "json";
  const ct = contentType.toLowerCase();
  if (ct.includes("json")) return "json"; // invalid JSON, but the intent is clear
  if (parseProto(data) !== null) return "protobuf";
  if (looksText(data)) return "text";
  return "binary";
}

function looksText(data: Buffer): boolean {
  const limit = Math.min(data.length, 512);
  let printable = 0;
  for (let index = 0; index < limit; index++) {
    const byte = data[index] ?? 0;
    if (byte === 9 || byte === 10 || byte === 13 || (byte >= 32 && byte < 127)) printable++;
  }
  return printable / limit > 0.92;
}

// ---------------------------------------------------------------------------
// JSON path setter
//
// Two forms are supported because the relay must work before a capture has
// pinned the schema:
//
//   data.GameVarDef.EnableShowPlayerOutline   exact path, creates missing keys
//   **.EnableShowPlayerOutline                every object that already has it
//
// The wildcard form is the important one for the var table. Its nesting has
// changed across releases; the field name has not.

type JsonSegment = string | number | "**";

function splitJsonPath(path: string): JsonSegment[] {
  const segments: JsonSegment[] = [];
  for (const raw of path.split(".")) {
    if (!raw) continue;
    if (raw === "**") {
      segments.push("**");
      continue;
    }
    const re = /([^[\]]+)|\[(\d+)\]/g;
    let match: RegExpExecArray | null;
    while ((match = re.exec(raw)) !== null) {
      if (match[1] !== undefined) segments.push(match[1]);
      else if (match[2] !== undefined) segments.push(Number(match[2]));
    }
  }
  return segments;
}

function hasOwn(value: unknown, key: string): boolean {
  return typeof value === "object" && value !== null
    && Object.prototype.hasOwnProperty.call(value, key);
}

/** Set a path on an object that is known to already carry its first key. */
function setExistingPath(node: unknown, segments: JsonSegment[], value: unknown): boolean {
  if (typeof node !== "object" || node === null || segments.length === 0) return false;
  const head = segments[0];
  if (head === undefined || head === "**") return false;
  const tail = segments.slice(1);

  if (tail.length === 0) {
    if (Array.isArray(node)) {
      if (typeof head !== "number" || head < 0 || head >= node.length) return false;
      node[head] = value;
      return true;
    }
    if (!hasOwn(node, String(head))) return false;
    (node as Record<string, unknown>)[String(head)] = value;
    return true;
  }

  const next = Array.isArray(node) ? node[typeof head === "number" ? head : -1] : (node as Record<string, unknown>)[String(head)];
  if (next === undefined) return false;
  return setExistingPath(next, tail, value);
}

function setAnyPath(node: unknown, segments: JsonSegment[], value: unknown): unknown {
  if (segments.length === 0) return value;
  const head = segments[0];
  if (head === undefined || head === "**") return node;
  const tail = segments.slice(1);

  if (typeof head === "number") {
    const array = Array.isArray(node) ? node : [];
    while (array.length <= head) array.push(null);
    array[head] = setAnyPath(array[head], tail, value);
    return array;
  }

  const object = (typeof node === "object" && node !== null && !Array.isArray(node))
    ? node as Record<string, unknown>
    : {};
  object[head] = setAnyPath(object[head], tail, value);
  return object;
}

function applyEverywhere(node: unknown, segments: JsonSegment[], value: unknown, depth: number): number {
  if (depth > 12 || typeof node !== "object" || node === null) return 0;
  let changed = 0;
  if (setExistingPath(node, segments, value)) changed++;
  if (Array.isArray(node)) {
    for (const child of node) changed += applyEverywhere(child, segments, value, depth + 1);
    return changed;
  }
  for (const key of Object.keys(node)) {
    changed += applyEverywhere((node as Record<string, unknown>)[key], segments, value, depth + 1);
  }
  return changed;
}

/** Apply one JSON path. Returns the new root and whether anything changed. */
export function setJsonPath(root: unknown, path: string, value: unknown): { root: unknown; changed: boolean } {
  const segments = splitJsonPath(path);
  if (segments.length === 0) return { root, changed: false };
  if (segments[0] === "**") {
    const count = applyEverywhere(root, segments.slice(1), value, 0);
    return { root, changed: count > 0 };
  }
  return { root: setAnyPath(root, segments, value), changed: true };
}

function deepMerge(target: Record<string, unknown>, patch: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(patch)) {
    const current = target[key];
    if (value && typeof value === "object" && !Array.isArray(value)
      && current && typeof current === "object" && !Array.isArray(current)) {
      deepMerge(current as Record<string, unknown>, value as Record<string, unknown>);
    } else {
      target[key] = value;
    }
  }
}

// ---------------------------------------------------------------------------
// protobuf path setter
//
// Wire format only: field number + wire type. No .proto file is needed because
// the path is numeric (`16`) and the wire type is inferred from the existing
// field, or from the value when the field is new.

interface ProtoField {
  no: number;
  wire: number;
  /** Payload for wire 2; the raw scalar for wire 0/1/5. */
  raw: Buffer;
  /** Parsed children when a wire-2 payload is itself a message. */
  sub?: ProtoField[];
}

function readVarint(buffer: Buffer, start: number): { value: number; next: number } | null {
  let value = 0;
  let shift = 0;
  let position = start;
  while (position < buffer.length && shift < 64) {
    const byte = buffer[position] ?? 0;
    position++;
    value += (byte & 0x7f) * Math.pow(2, shift);
    if ((byte & 0x80) === 0) return { value, next: position };
    shift += 7;
  }
  return null;
}

function writeVarint(value: number): Buffer {
  const bytes: number[] = [];
  let current = Math.max(0, Math.trunc(value));
  do {
    let byte = current % 128;
    current = Math.floor(current / 128);
    if (current > 0) byte |= 0x80;
    bytes.push(byte);
  } while (current > 0);
  return Buffer.from(bytes);
}

function parseProto(buffer: Buffer): ProtoField[] | null {
  const fields: ProtoField[] = [];
  let position = 0;
  while (position < buffer.length) {
    const key = readVarint(buffer, position);
    if (!key) return null;
    const no = Math.floor(key.value / 8);
    const wire = key.value % 8;
    if (no <= 0) return null;
    position = key.next;
    if (wire === 0) {
      const value = readVarint(buffer, position);
      if (!value) return null;
      fields.push({ no, wire, raw: buffer.subarray(position, value.next) });
      position = value.next;
    } else if (wire === 1) {
      if (position + 8 > buffer.length) return null;
      fields.push({ no, wire, raw: buffer.subarray(position, position + 8) });
      position += 8;
    } else if (wire === 2) {
      const length = readVarint(buffer, position);
      if (!length) return null;
      const end = length.next + length.value;
      if (end > buffer.length) return null;
      const raw = buffer.subarray(length.next, end);
      const field: ProtoField = { no, wire, raw };
      const sub = parseProto(raw);
      if (sub && sub.length > 0) field.sub = sub;
      fields.push(field);
      position = end;
    } else if (wire === 5) {
      if (position + 4 > buffer.length) return null;
      fields.push({ no, wire, raw: buffer.subarray(position, position + 4) });
      position += 4;
    } else {
      // Groups (3/4) are obsolete and never appear in these documents.
      return null;
    }
  }
  return fields.length > 0 ? fields : null;
}

function encodeProto(fields: ProtoField[]): Buffer {
  const parts: Buffer[] = [];
  for (const field of fields) {
    const key = writeVarint(field.no * 8 + field.wire);
    if (field.wire === 2) {
      parts.push(key, writeVarint(field.raw.length), field.raw);
    } else {
      parts.push(key, field.raw);
    }
  }
  return Buffer.concat(parts);
}

function scalarFor(op: ProtoPathOp): { wire: number; raw: Buffer } {
  const wire = op.wire ?? "auto";
  const stringBytes = (): Buffer => {
    if (typeof op.value !== "string") return Buffer.from(String(op.value), "utf8");
    if (op.encoding === "base64") return Buffer.from(op.value, "base64");
    if (op.encoding === "hex") return Buffer.from(op.value, "hex");
    return Buffer.from(op.value, "utf8");
  };
  if (wire === "string" || wire === "bytes" || (wire === "auto" && typeof op.value === "string")) {
    return { wire: 2, raw: stringBytes() };
  }
  if (wire === "fixed32") {
    const buffer = Buffer.alloc(4);
    buffer.writeUInt32LE(Number(op.value) >>> 0, 0);
    return { wire: 5, raw: buffer };
  }
  if (wire === "fixed64") {
    const buffer = Buffer.alloc(8);
    buffer.writeBigUInt64LE(BigInt(Math.trunc(Number(op.value))), 0);
    return { wire: 1, raw: buffer };
  }
  const numeric = typeof op.value === "boolean" ? (op.value ? 1 : 0) : Math.trunc(Number(op.value));
  return { wire: 0, raw: writeVarint(Number.isFinite(numeric) ? numeric : 0) };
}

function setLeaf(fields: ProtoField[], no: number, op: ProtoPathOp): boolean {
  const index = fields.findIndex((field) => field.no === no);
  const incoming = scalarFor(op);
  if (index >= 0) {
    const existing = fields[index];
    if (!existing) return false;
    if (existing.wire !== incoming.wire) {
      fields[index] = { no, wire: incoming.wire, raw: incoming.raw };
    } else {
      existing.raw = incoming.raw;
      delete existing.sub;
    }
    return true;
  }
  fields.push({ no, wire: incoming.wire, raw: incoming.raw });
  return true;
}

function setProtoAt(fields: ProtoField[], segments: number[], op: ProtoPathOp, depth: number): number {
  if (segments.length === 0 || depth > 12) return 0;
  const head = segments[0];
  if (head === undefined) return 0;
  if (segments.length === 1) return setLeaf(fields, head, op) ? 1 : 0;

  const index = fields.findIndex((field) => field.no === head);
  if (index < 0) {
    // Create the intermediate message so a path can address a field the server
    // omitted. An empty message is valid protobuf and the client's default
    // value applies to everything inside it.
    const created: ProtoField = { no: head, wire: 2, raw: Buffer.alloc(0), sub: [] };
    fields.push(created);
    return setProtoAt(created.sub ?? [], segments.slice(1), op, depth + 1);
  }
  const field = fields[index];
  if (!field || field.wire !== 2) return 0;
  const sub = field.sub ?? (parseProto(field.raw) ?? []);
  const changed = setProtoAt(sub, segments.slice(1), op, depth + 1);
  if (changed > 0) {
    field.sub = sub;
    field.raw = encodeProto(sub);
  }
  return changed;
}

function setProtoEverywhere(
  fields: ProtoField[],
  segments: number[],
  op: ProtoPathOp,
  depth: number,
): number {
  if (depth > 12) return 0;
  let changed = setProtoAt(fields, segments, op, depth);
  for (const field of fields) {
    if (field.wire !== 2) continue;
    const sub = field.sub ?? parseProto(field.raw);
    if (!sub || sub.length === 0) continue;
    const hits = setProtoEverywhere(sub, segments, op, depth + 1);
    if (hits > 0) {
      field.sub = sub;
      field.raw = encodeProto(sub);
      changed += hits;
    }
  }
  return changed;
}

/** Apply one numeric protobuf path to a message. */
export function setProtoPath(
  buffer: Buffer,
  path: string,
  op: Omit<ProtoPathOp, "path">,
): { buffer: Buffer; changed: boolean } {
  const fields = parseProto(buffer);
  if (!fields) return { buffer, changed: false };
  const parts = path.split(".").map((part) => part.trim()).filter(Boolean);
  if (parts.length === 0) return { buffer, changed: false };
  const wildcard = parts[0] === "**";
  const numbers = parts.filter((part) => part !== "**").map(Number);
  if (numbers.some((value) => !Number.isFinite(value) || value <= 0)) {
    return { buffer, changed: false };
  }
  const full = { ...op, path } as ProtoPathOp;
  const changed = wildcard
    ? setProtoEverywhere(fields, numbers, full, 0)
    : setProtoAt(fields, numbers, full, 0);
  return { buffer: changed > 0 ? encodeProto(fields) : buffer, changed: changed > 0 };
}

// ---------------------------------------------------------------------------
// rule application

export function rewriteBody(
  body: Buffer,
  contentType: string,
  rules: ArsenalRule[],
  log: (line: string) => void,
): BodyRewrite {
  let out = body;
  let format = detectFormat(out, contentType);
  let changed = false;
  const applied: string[] = [];

  let json: unknown;
  let jsonValid = false;
  let jsonTouched = false;
  if (format === "json") {
    json = tryJson(out);
    jsonValid = json !== undefined;
  }

  for (const rule of rules) {
    if (rule.action === "json-merge" && rule.merge) {
      if (!jsonValid) {
        log("relay: json-merge skipped — body is not JSON");
        continue;
      }
      if (typeof json !== "object" || json === null || Array.isArray(json)) {
        log("relay: json-merge skipped — root is not an object");
        continue;
      }
      deepMerge(json as Record<string, unknown>, rule.merge);
      jsonTouched = true;
      changed = true;
      applied.push(`json-merge(${rule.note ?? "merge"})`);
    }

    if (rule.action === "json-set" && rule.jsonOps && rule.jsonOps.length > 0) {
      if (!jsonValid) {
        log("relay: json-set skipped — body is not JSON");
        continue;
      }
      let touched = 0;
      for (const op of rule.jsonOps) {
        const result = setJsonPath(json, op.path, op.value);
        json = result.root;
        if (result.changed) touched++;
      }
      if (touched > 0) {
        jsonTouched = true;
        changed = true;
        applied.push(`json-set(${rule.note ?? rule.jsonOps.length + " paths"})`);
      }
    }

    if (rule.action === "proto-set" && rule.protoOps && rule.protoOps.length > 0) {
      if (jsonTouched) {
        out = Buffer.from(JSON.stringify(json), "utf8");
        jsonTouched = false;
        jsonValid = false;
      }
      let touched = 0;
      for (const op of rule.protoOps) {
        const result = setProtoPath(out, op.path, op);
        if (result.changed) {
          out = result.buffer;
          touched++;
        }
      }
      if (touched > 0) {
        changed = true;
        format = "protobuf";
        applied.push(`proto-set(${rule.note ?? touched + " fields"})`);
      }
    }

    if (rule.action === "text-replace" && rule.find) {
      if (jsonTouched) {
        out = Buffer.from(JSON.stringify(json), "utf8");
        jsonTouched = false;
        jsonValid = false;
      }
      const text = out.toString("utf8");
      if (text.includes(rule.find)) {
        out = Buffer.from(text.split(rule.find).join(rule.replace ?? ""), "utf8");
        changed = true;
        applied.push(`text-replace(${rule.note ?? rule.find})`);
      }
    }
  }

  if (jsonTouched) out = Buffer.from(JSON.stringify(json), "utf8");
  return { body: out, applied, format, changed };
}

export function describeBody(body: Buffer, contentType: string): BodyDescription {
  const format = detectFormat(body, contentType);
  const description: BodyDescription = { format, keys: [], fields: [], bytes: body.length };
  if (format === "json") {
    const parsed = tryJson(body);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      description.keys = Object.keys(parsed as Record<string, unknown>).slice(0, 32);
    } else if (Array.isArray(parsed) && parsed.length > 0
      && typeof parsed[0] === "object" && parsed[0] !== null) {
      description.keys = Object.keys(parsed[0] as Record<string, unknown>).slice(0, 32);
    }
  } else if (format === "protobuf") {
    const fields = parseProto(body);
    if (fields) description.fields = fields.map((field) => field.no).slice(0, 32);
  }
  return description;
}

// ---------------------------------------------------------------------------
// mining
//
// A capture is only useful if the interesting fields can be recognised without
// knowing which host carried them. These helpers look for the field *names* in
// JSON (the var table) and for a settings-shaped protobuf blob.

const VAR_TABLE_HINTS = [
  "EnableShowPlayerOutline",
  "ShowPlayerOutlineMaxDistance",
  "CodePatchUrl",
  "GameVarDef",
  "EnableStropAimAssist",
  "EnableBeAimAssistWhenStropDash",
];

export function jsonCarriesVarTable(record: { resPreview?: string }): boolean {
  const preview = record.resPreview ?? "";
  if (!preview.includes("{")) return false;
  let hits = 0;
  for (const hint of VAR_TABLE_HINTS) if (preview.includes(hint)) hits++;
  return hits > 0;
}

export function settingsBlobCarriesAimAssist(body: Buffer): boolean {
  const fields = parseProto(body);
  if (!fields) return false;
  // SettingDetail is a small message whose aim_assist field sits in the middle
  // of a run of varints/floats. A protobuf with a 20-60 byte payload and at
  // least eight scalar fields is a plausible settings document; the relay never
  // guesses beyond that, it only tells the miner where to look.
  let scalars = 0;
  for (const field of fields) if (field.wire === 0 || field.wire === 5) scalars++;
  return body.length >= 20 && body.length <= 4096 && scalars >= 8;
}
