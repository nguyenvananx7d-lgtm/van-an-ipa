import { type Rule } from "./mitm.js";
import { type CaptureRecord, type Suggestion } from "./suggest.js";

/**
 * The client-facing control surface, and the reason the profile ships a web
 * clip instead of an app.
 *
 * Three screens in one document, in the order the reference product uses:
 *   1. login  — a licence key, exchanged at the auth backend;
 *   2. panel  — the card that proves the session is live: session key, device
 *               key, iOS version, rules, ping;
 *   3. menu   — the switches themselves, over the relay's live rule array.
 *
 * The panel is deliberately informational: the three values on the right
 * (iOS / rules / ping) are read from the page's own environment, so they are
 * true even when the relay is misconfigured. A card that only ever prints
 * "ACTIVE" tells nobody anything.
 */
export interface FeatureState {
  id: string;
  label: string;
  detail: string;
  risky: boolean;
  enabled: boolean;
  rules: number;
  /** Requests this feature actually acted on, counted from the capture log. */
  hits: number;
}

export interface MenuView {
  name: string;
  publicHost: string;
  proxyPort: number;
  deviceKey: string;
  rules: Rule[];
  features: FeatureState[];
  captures: { total: number; recent: CaptureRecord[] };
  suggestions: Suggestion[];
  /** When false, the menu is a viewer: the relay has no auth backend wired. */
  loginEnabled: boolean;
  version: string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function renderMenu(view: MenuView): string {
  return `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#0b0c0d">
<title>${escapeHtml(view.name)}</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #0b0c0d; --card: #151718; --line: #262a2b; --edge: #34393a;
    --text: #eef1f0; --muted: #868f8d; --green: #35d07f; --red: #ff6b6b;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; background: var(--bg); }
  body {
    color: var(--text); font: 15px/1.5 -apple-system, system-ui, sans-serif;
    padding: max(16px, env(safe-area-inset-top)) 14px calc(24px + env(safe-area-inset-bottom));
    max-width: 520px; margin: 0 auto;
  }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 14px;
    padding: 14px 15px; margin: 0 0 12px;
  }
  .head { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; margin-bottom: 14px; }
  .brand { display: flex; align-items: center; gap: 7px; font-size: 15px; letter-spacing: .02em; }
  .brand b { font-weight: 800; }
  .brand span.sub { color: var(--muted); font-weight: 600; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); box-shadow: 0 0 8px rgba(53,208,127,.6); }
  .pill {
    font-size: 10px; font-weight: 800; letter-spacing: .14em; text-transform: uppercase;
    padding: 3px 8px; border-radius: 6px; border: 1px solid rgba(53,208,127,.35);
    color: var(--green); background: rgba(53,208,127,.08);
  }
  .pill.off { color: var(--red); border-color: rgba(255,107,107,.35); background: rgba(255,107,107,.08); }
  .cols { display: grid; grid-template-columns: 1fr 74px; gap: 12px; }
  .field { margin-bottom: 12px; }
  .field .k { display: block; color: var(--muted); font-size: 11px; letter-spacing: .04em; margin-bottom: 3px; }
  .field .k i { font-style: normal; opacity: .75; }
  .field .v {
    display: block; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12.5px; color: var(--green); word-break: break-all; line-height: 1.35;
  }
  .field .v.plain { color: var(--text); }
  .right { border-left: 1px solid var(--line); padding-left: 12px; }
  .right .field { margin-bottom: 10px; }
  .right .v { font-size: 12px; }
  button {
    font: inherit; width: 100%; border: 0; border-radius: 11px; cursor: pointer;
    padding: 14px 16px; font-weight: 700; font-size: 14px; letter-spacing: .04em;
  }
  .primary { background: #f3f6f5; color: #0b0c0d; margin-top: 4px; }
  .primary:active { background: #d9e0de; }
  .danger { background: transparent; color: var(--red); margin-top: 10px; font-weight: 700; font-size: 12.5px; }
  .ghost { background: #1b1f20; color: var(--text); border: 1px solid var(--line); }
  .ghost.small { width: auto; padding: 9px 14px; font-size: 12.5px; }
  .foot {
    margin-top: 14px; padding-top: 10px; border-top: 1px solid var(--line);
    color: #5f6866; font-size: 10.5px; font-family: ui-monospace, Menlo, monospace;
    display: flex; justify-content: space-between; gap: 8px;
  }
  label.lbl { display: block; color: var(--muted); font-size: 11px; letter-spacing: .04em; margin-bottom: 6px; }
  input[type=text] {
    width: 100%; padding: 13px 14px; border-radius: 11px; border: 1px solid var(--edge);
    background: #0f1213; color: var(--text); font-family: ui-monospace, Menlo, monospace;
    font-size: 14px; letter-spacing: .08em; text-transform: uppercase; margin-bottom: 12px;
  }
  input[type=text]:focus { outline: none; border-color: var(--green); }
  h2 { font-size: 13px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted);
       margin: 18px 0 8px; font-weight: 700; }
  .rule, .feat { border: 1px solid var(--line); border-radius: 11px; padding: 10px 12px; margin: 7px 0;
          display: flex; align-items: center; gap: 10px; background: #131617; }
  .feat { align-items: flex-start; }
  .feat.risky { border-color: rgba(255,107,107,.28); }
  .feat .body { flex: 1; font-size: 12.5px; }
  .feat small { display: block; color: var(--muted); font-size: 10.5px; margin-top: 3px; line-height: 1.45; }
  .feat .count { display: block; margin-top: 5px; font-family: ui-monospace, Menlo, monospace;
                 font-size: 10.5px; color: var(--green); }
  .feat .count.zero { color: #5f6866; }
  .switch { position: relative; width: 46px; height: 27px; border-radius: 14px; background: #2a2f30;
            border: 1px solid var(--edge); flex: 0 0 auto; margin-top: 1px; padding: 0; }
  .switch::after { content: ''; position: absolute; top: 2px; left: 2px; width: 21px; height: 21px;
                   border-radius: 50%; background: #9aa3a1; transition: transform .16s ease, background .16s ease; }
  .switch[aria-checked="true"] { background: rgba(53,208,127,.22); border-color: rgba(53,208,127,.5); }
  .switch[aria-checked="true"]::after { transform: translateX(19px); background: var(--green); }
  .rule .body { flex: 1; font-size: 12.5px; }
  .rule small { display: block; color: var(--muted); font-size: 10.5px; margin-top: 2px; }
  .rule button { width: auto; padding: 7px 13px; font-size: 12px; border-radius: 9px; }
  .off-btn { background: rgba(255,107,107,.1); color: var(--red); border: 1px solid rgba(255,107,107,.3); }
  .on-btn { background: rgba(53,208,127,.14); color: var(--green); border: 1px solid rgba(53,208,127,.35); }
  .note { min-height: 17px; color: var(--green); font-size: 12px; margin-top: 10px; }
  .note.bad { color: var(--red); }
  .empty { color: var(--muted); font-size: 12.5px; padding: 4px 0; }
  .back { display: inline-flex; align-items: center; gap: 6px; color: var(--muted); font-size: 13px;
          background: none; border: 0; padding: 6px 0; width: auto; margin-bottom: 2px; }
  .stats { display: grid; grid-template-columns: 1fr 1fr; gap: 9px; margin-top: 4px; }
  .stat { background: #131617; border: 1px solid var(--line); border-radius: 11px; padding: 10px 12px; }
  .stat b { display: block; font-size: 18px; }
  .stat span { color: var(--muted); font-size: 10.5px; }
  [hidden] { display: none !important; }
</style>

<!-- 1. login -->
<section id="view-login" hidden>
  <div class="card">
    <div class="head">
      <div class="brand"><span class="dot"></span><b>${escapeHtml(view.name.toUpperCase())}</b><span class="sub">CONTROL</span></div>
      <span class="pill" id="loginPill">Sign in</span>
    </div>
    <label class="lbl" for="key">KEY BẢN QUYỀN</label>
    <input id="key" type="text" inputmode="text" autocomplete="off" autocapitalize="characters" placeholder="VT-XXXX-XXXX">
    <button id="loginBtn" class="primary">ĐĂNG NHẬP</button>
    <div id="loginNote" class="note"></div>
    <div class="foot"><span>${escapeHtml(view.publicHost)}:${view.proxyPort}</span><span>v${escapeHtml(view.version)}</span></div>
  </div>
</section>

<!-- 2. panel -->
<section id="view-panel" hidden>
  <div class="card">
    <div class="head">
      <div class="brand"><span class="dot"></span><b>${escapeHtml(view.name.toUpperCase())}</b><span class="sub">CONTROL</span></div>
      <span class="pill" id="statePill">Active</span>
    </div>
    <div class="cols">
      <div>
        <div class="field">
          <span class="k">Session key <i>(session ID)</i></span>
          <span class="v" id="sessionKey">—</span>
        </div>
        <div class="field">
          <span class="k">Device key <i>(phone ID)</i></span>
          <span class="v" id="deviceKey">—</span>
        </div>
      </div>
      <div class="right">
        <div class="field"><span class="k">iOS</span><span class="v plain" id="ios">—</span></div>
        <div class="field"><span class="k">Rules</span><span class="v plain" id="ruleCount">—</span></div>
        <div class="field"><span class="k">Ping</span><span class="v plain" id="ping">—</span></div>
      </div>
    </div>
    <button id="openMenu" class="primary">MỞ WEB MENU</button>
    <button id="logout" class="danger">ĐĂNG XUẤT</button>
    <div class="foot">
      <span id="planLine">—</span>
      <span>v${escapeHtml(view.version)}</span>
    </div>
  </div>
</section>

<!-- 3. menu -->
<section id="view-menu" hidden>
  <button id="back" class="back">‹ Quay lại</button>
  <div class="card">
    <div class="head" style="margin-bottom:10px">
      <div class="brand"><span class="dot"></span><b>WEB MENU</b></div>
      <span class="pill" id="menuPill">Active</span>
    </div>
    <div class="stats">
      <div class="stat"><b id="capTotal">0</b><span>request đã bắt</span></div>
      <div class="stat"><b id="menuRuleTotal">0</b><span>rule đang bật</span></div>
    </div>
  </div>
  <h2>Chức năng</h2>
  <div id="features"></div>
  <h2>Rule đang bật</h2>
  <div id="rules"></div>
  <h2>Gợi ý từ traffic</h2>
  <div id="suggestions"></div>
  <div class="note" id="note"></div>
</section>

<script>
const NAME = ${JSON.stringify(view.name)};
const LOGIN_ENABLED = ${view.loginEnabled ? "true" : "false"};
const note = document.getElementById('note');
const fields = {
  session: 'nimbus.session', key: 'nimbus.key', device: 'nimbus.device'
};

let state = { rules: [], features: [], suggestions: [], captures: { total: 0, recent: [] } };
let session = localStorage.getItem(fields.session) || '';
let savedKey = localStorage.getItem(fields.key) || '';

/* A phone ID that survives a re-install of the web clip is impossible; this is
   a per-browser handle, and it is what the auth backend binds the key to. */
function deviceId() {
  let id = localStorage.getItem(fields.device);
  if (id) return id;
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  id = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  localStorage.setItem(fields.device, id);
  return id;
}

function iosVersion() {
  const match = /OS (\\d+)[_.](\\d+)/.exec(navigator.userAgent);
  return match ? match[1] + '.' + match[2] : (navigator.userAgent.includes('Mac') ? 'macOS' : '—');
}

function show(view) {
  for (const id of ['view-login', 'view-panel', 'view-menu']) {
    document.getElementById(id).hidden = id !== 'view-' + view;
  }
  if (view === 'menu') refresh();
}

function decodeEnvelope(envelope) {
  const binary = atob(envelope.data);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

async function login() {
  const input = document.getElementById('key');
  const key = (input.value || '').trim();
  const pill = document.getElementById('loginPill');
  const line = document.getElementById('loginNote');
  if (!key) { line.textContent = 'Nhập key trước.'; line.className = 'note bad'; return; }

  pill.textContent = 'Đang kiểm';
  line.className = 'note';
  line.textContent = '';
  try {
    const response = await fetch('/menu/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ key, hwid: deviceId(), device_name: 'Web menu', ios_version: iosVersion() })
    });
    const envelope = await response.json();
    if (!response.ok || !envelope.data) {
      throw new Error(envelope.error || 'Không kết nối được máy chủ bản quyền');
    }
    const payload = decodeEnvelope(envelope);
    if (payload.status !== 'valid') {
      throw new Error(payload.message || payload.status);
    }
    session = payload.session || '';
    localStorage.setItem(fields.session, session);
    localStorage.setItem(fields.key, key);
    savedKey = key;
    paintPanel(payload);
    show('panel');
  } catch (error) {
    pill.textContent = 'Sign in';
    line.textContent = String(error.message || error);
    line.className = 'note bad';
  }
}

function paintPanel(payload) {
  document.getElementById('sessionKey').textContent = session || '—';
  document.getElementById('deviceKey').textContent = deviceId();
  document.getElementById('ios').textContent = iosVersion();
  const plan = [payload.plan, payload.expiresAt ? 'hết hạn ' + payload.expiresAt.slice(0, 10) : 'không giới hạn']
    .filter(Boolean).join(' · ');
  document.getElementById('planLine').textContent = plan || savedKey;

  const started = performance.now();
  fetch('/state', { cache: 'no-store' })
    .then((r) => r.json())
    .then((data) => {
      document.getElementById('ping').textContent = Math.round(performance.now() - started) + 'ms';
      document.getElementById('ruleCount').textContent = data.rules.length;
    })
    .catch(() => {
      document.getElementById('ping').textContent = '—';
      document.getElementById('ping').style.color = 'var(--red)';
    });
}

async function logout() {
  session = '';
  localStorage.removeItem(fields.session);
  localStorage.removeItem(fields.key);
  savedKey = '';
  show('login');
  document.getElementById('loginPill').textContent = 'Sign in';
  document.getElementById('loginNote').textContent = '';
  document.getElementById('key').value = '';
}

async function post(path, body) {
  const headers = { 'content-type': 'application/json' };
  if (session) headers['x-menu-session'] = session;
  return fetch(path, { method: 'POST', headers, body: JSON.stringify(body === undefined ? {} : body) });
}

function ruleRow(title, sub, buttonLabel, buttonClass, onClick) {
  const row = document.createElement('div');
  row.className = 'rule';
  const body = document.createElement('div');
  body.className = 'body';
  body.textContent = title;
  const small = document.createElement('small');
  small.textContent = sub;
  body.append(small);
  const button = document.createElement('button');
  button.className = buttonClass;
  button.textContent = buttonLabel;
  button.onclick = onClick;
  row.append(body, button);
  return row;
}

function renderFeatures(list) {
  state.features = list;
  const box = document.getElementById('features');
  box.innerHTML = '';
  if (!list.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'Relay không cấu hình chức năng nào.';
    box.append(empty);
    return;
  }
  for (const feature of list) {
    const row = document.createElement('div');
    row.className = 'feat' + (feature.risky ? ' risky' : '');

    const body = document.createElement('div');
    body.className = 'body';
    body.textContent = feature.label;
    const small = document.createElement('small');
    small.textContent = feature.detail;
    const count = document.createElement('span');
    count.className = 'count' + (feature.hits ? '' : ' zero');
    count.textContent = feature.hits
      ? feature.hits + ' request đã xử lý'
      : (feature.enabled ? 'bật — chưa có request nào khớp' : 'đang tắt');
    body.append(small, count);

    const toggle = document.createElement('button');
    toggle.className = 'switch';
    toggle.setAttribute('role', 'switch');
    toggle.setAttribute('aria-checked', feature.enabled ? 'true' : 'false');
    toggle.setAttribute('aria-label', feature.label);
    toggle.onclick = async () => {
      toggle.disabled = true;
      const response = await post('/features', { id: feature.id, enabled: !feature.enabled });
      note.className = response.ok ? 'note' : 'note bad';
      note.textContent = response.ok
        ? (feature.enabled ? 'Đã tắt: ' : 'Đã bật: ') + feature.label.toLowerCase()
        : 'Không đổi được (' + response.status + ')';
      refresh();
    };

    row.append(body, toggle);
    box.append(row);
  }
}

function renderRules(list) {
  state.rules = list;
  const box = document.getElementById('rules');
  box.innerHTML = '';
  document.getElementById('menuRuleTotal').textContent = list.length;
  document.getElementById('ruleCount').textContent = list.length;
  if (!list.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'Chưa bật rule nào — relay chỉ ghi lại traffic.';
    box.append(empty);
    return;
  }
  list.forEach((rule, index) => {
    box.append(ruleRow(
      (rule.host || '*') + ' ' + rule.pathPattern,
      rule.action + (rule.note ? ' · ' + rule.note : ''),
      'Tắt', 'off-btn',
      async () => {
        const next = state.rules.filter((_, i) => i !== index);
        const response = await post('/rules', next);
        note.className = response.ok ? 'note' : 'note bad';
        note.textContent = response.ok ? 'Đã tắt rule' : 'Tắt thất bại (' + response.status + ')';
        refresh();
      }
    ));
  });
}

function renderSuggestions(list) {
  state.suggestions = list;
  const box = document.getElementById('suggestions');
  box.innerHTML = '';
  if (!list.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'Chưa có ứng viên. Chơi một trận rồi tải lại.';
    box.append(empty);
    return;
  }
  for (const suggestion of list) {
    box.append(ruleRow(
      suggestion.host + suggestion.path,
      suggestion.action + ' · score ' + suggestion.score + ' · ' + suggestion.calls + ' lần',
      'Bật', 'on-btn',
      async () => {
        const isPin = suggestion.rule.action === 'respond' && Boolean(suggestion.rule.bodyFile);
        let response;
        if (isPin) {
          response = await post('/pin', suggestion.rule);
        } else {
          const next = state.rules.filter((r) =>
            !(r.host === suggestion.rule.host && r.pathPattern === suggestion.rule.pathPattern));
          next.push(suggestion.rule);
          response = await post('/rules', next);
        }
        note.className = response.ok ? 'note' : 'note bad';
        note.textContent = response.ok
          ? (isPin ? 'Đã pin patch tại URL thật — sống ngay' : 'Đã bật — có hiệu lực ngay')
          : (isPin ? 'Pin thất bại (' + response.status + ')' : 'Bật thất bại (' + response.status + ')');
        refresh();
      }
    ));
  }
}

async function refresh() {
  try {
    const response = await fetch('/state', { cache: 'no-store' });
    const data = await response.json();
    document.getElementById('capTotal').textContent = data.captures.total;
    document.getElementById('menuPill').textContent = 'Active';
    document.getElementById('menuPill').className = 'pill';
    renderFeatures(data.features || []);
    renderRules(data.rules);
    renderSuggestions(data.suggestions);
  } catch (error) {
    document.getElementById('menuPill').textContent = 'Offline';
    document.getElementById('menuPill').className = 'pill off';
    note.className = 'note bad';
    note.textContent = 'Mất kết nối tới relay';
  }
}

document.getElementById('deviceKey').textContent = deviceId();
document.getElementById('ios').textContent = iosVersion();
document.getElementById('loginBtn').onclick = login;
document.getElementById('key').addEventListener('keydown', (event) => {
  if (event.key === 'Enter') login();
});
document.getElementById('openMenu').onclick = () => show('menu');
document.getElementById('back').onclick = () => { show('panel'); };
document.getElementById('logout').onclick = logout;

if (LOGIN_ENABLED && session) {
  show('panel');
  document.getElementById('sessionKey').textContent = session;
  document.getElementById('planLine').textContent = savedKey || '—';
  document.getElementById('deviceKey').textContent = deviceId();
} else if (LOGIN_ENABLED) {
  show('login');
} else {
  // No auth backend wired: the card still shows the live device and relay,
  // it just cannot claim a licensed session.
  document.getElementById('statePill').textContent = 'Open';
  document.getElementById('statePill').className = 'pill off';
  document.getElementById('sessionKey').textContent = 'không bật đăng nhập';
  document.getElementById('sessionKey').style.color = 'var(--muted)';
  document.getElementById('logout').hidden = true;
  show('panel');
  fetch('/state', { cache: 'no-store' })
    .then((r) => r.json())
    .then((data) => {
      document.getElementById('ruleCount').textContent = data.rules.length;
    })
    .catch(() => {});
}
</script>`;
}
