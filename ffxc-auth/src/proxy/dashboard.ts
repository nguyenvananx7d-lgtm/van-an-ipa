import { type CaptureRecord } from "./suggest.js";
import { type Rule } from "./mitm.js";
import { type Suggestion } from "./suggest.js";

/**
 * The relay's only human surface.
 *
 * It answers three questions in order, because that is the order a person
 * actually asks them: what is this, is it running, and what do I do next. The
 * live tables below are client-side on purpose — a rule applied from the page
 * has to appear without a reload, otherwise the page looks broken exactly when
 * it worked.
 */
export interface DashboardView {
  name: string;
  publicHost: string;
  proxyPort: number;
  adminPort: number;
  rules: Rule[];
  captures: { total: number; recent: CaptureRecord[] };
  suggestions: Suggestion[];
  /** Present when the profile carries a tunnel; changes the setup steps. */
  transport?: { kind: string; server: string; proxyInTunnel: boolean };
  menuUrl?: string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** The server-rendered shell; everything dynamic arrives from `/state`. */
export function renderDashboard(view: DashboardView): string {
  const routeStep = view.transport
    ? {
        title: `Bật ${view.name} VPN`,
        detail: `Settings → VPN → chọn ${view.name} → Kết nối. `
          + (view.transport.proxyInTunnel
            ? `Proxy ${view.proxyPort} đã nằm trong profile, không cần nhập tay.`
            : `Sau đó nhập proxy ${view.publicHost}:${view.proxyPort} trong Wi-Fi.`),
        done: view.captures.total > 0,
      }
    : {
        title: `Nhập proxy trong Wi-Fi: ${view.publicHost} : ${view.proxyPort}`,
        detail: "Settings → Wi-Fi → ⓘ cạnh tên mạng → Configure Proxy → Manual → điền server và port ở trên.",
        done: view.captures.total > 0,
      };

  const steps = [
    {
      title: "Cài profile trên điện thoại",
      detail: "Bấm nút Cài profile bên dưới bằng Safari → Allow → Settings cài profile.",
      done: view.captures.total > 0 || view.rules.length > 0,
    },
    {
      title: "Bật full trust cho chứng chỉ",
      detail: "Settings → General → About → Certificate Trust Settings → bật công tắc.",
      done: view.captures.total > 0,
    },
    routeStep,
    {
      title: "Chơi một trận bình thường",
      detail: "Chưa sửa gì. Relay sẽ ghi lại các request game gửi lên server.",
      done: view.captures.total > 0,
    },
    {
      title: "Bấm Apply ở rule được gợi ý",
      detail: "Rule sống ngay, không cần restart, không rớt trận.",
      done: view.rules.length > 0,
    },
  ];

  const stepHtml = steps
    .map(
      (step, index) => `
      <li style="display:flex;gap:12px;padding:10px 0;border-top:1px solid #1d2624">
        <span style="flex:0 0 26px;height:26px;border-radius:13px;display:grid;place-items:center;
          background:${step.done ? "#1f6f5c" : "#161c1b"};color:${step.done ? "#bff3e4" : "#8d9693"};
          font-weight:700;font-size:13px">${step.done ? "✓" : index + 1}</span>
        <span>
          <b style="color:#eef1f0">${escapeHtml(step.title)}</b><br>
          <span style="color:#8d9693;font-size:13px">${escapeHtml(step.detail)}</span>
        </span>
      </li>`,
    )
    .join("");

  return `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(view.name)}</title>
<body style="margin:0;background:#0b0d0e;color:#eef1f0;font:15px -apple-system;line-height:1.55">
<div style="max-width:860px;margin:0 auto;padding:22px 20px 60px">

  <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px">
    <span id="dot" style="width:9px;height:9px;border-radius:5px;background:#7dd3c0"></span>
    <h1 style="font-size:20px;margin:0">${escapeHtml(view.name)}</h1>
  </div>
  <div id="meta" style="color:#8d9693;font-size:13px">
    proxy ${escapeHtml(view.publicHost)}:${view.proxyPort} · ${view.rules.length} rule · ${view.captures.total} capture
  </div>

  <div style="background:#14181a;border:1px solid #24302e;border-radius:14px;padding:16px 18px;margin:18px 0">
    <b style="color:#7dd3c0">Trang này là gì?</b>
    <p style="margin:8px 0 0;color:#cfe0db">
      Đây là <b>bảng điều khiển relay</b> — con proxy đứng giữa game và server game.
      Không có app nào cần cài: profile cấp chứng chỉ, dựng tunnel và đặt proxy,
      còn relay đọc báo cáo anti-cheat game gửi lên, sửa lại cho sạch, rồi chuyển tiếp.
      Vì code game không bị đụng tới nên nó không có gì để phát hiện.
    </p>
    <pre style="margin:12px 0 0;color:#9fb3ae;font-size:12px;white-space:pre-wrap">Điện thoại ──TLS──▶ relay (${escapeHtml(view.publicHost)}:${view.proxyPort}) ──TLS──▶ server game
                      │
                      └─ ghi lại + sửa rule</pre>
  </div>

  <div style="background:#101516;border:1px solid #24302e;border-radius:14px;padding:14px 16px;margin:0 0 18px">
    <b style="color:#eef1f0">${view.transport ? "Tunnel trong profile" : "Nhập proxy trên iPhone"}</b>
    <div style="margin-top:8px;font-family:ui-monospace,monospace;font-size:15px;color:#bff3e4">
      ${escapeHtml(view.transport?.kind.toUpperCase() ?? "PROXY")}: ${escapeHtml(view.transport?.server ?? view.publicHost)}
      &nbsp;·&nbsp; Proxy: ${escapeHtml(view.publicHost)}:${view.proxyPort}
    </div>
    <div style="color:#8d9693;font-size:13px;margin-top:6px">
      ${view.transport
        ? "Profile đã cài sẵn tunnel và proxy. Chỉ cần bật VPN trong Settings, rồi mở lại game."
        : "Settings → Wi-Fi → bấm ⓘ cạnh tên mạng → Configure Proxy → Manual → điền hai giá trị trên → Save. Cùng một Wi-Fi với máy chạy relay."}
    </div>
  </div>

  <h2 style="font-size:15px;margin:22px 0 6px">Bạn đang ở bước nào</h2>
  <ol style="list-style:none;margin:0;padding:0">${stepHtml}</ol>

  <div style="display:flex;gap:10px;flex-wrap:wrap;margin:16px 0 4px">
    <a href="/profile.mobileconfig" style="background:#7dd3c0;color:#06110f;text-decoration:none;
       border-radius:10px;padding:10px 16px;font-weight:700">Cài profile</a>
    ${view.menuUrl
      ? `<a href="/menu" style="background:#161c1b;color:#cfe0db;text-decoration:none;
           border:1px solid #24302e;border-radius:10px;padding:10px 16px;font-weight:600">Mở menu</a>`
      : ""}
    <button id="clear" style="background:#161c1b;color:#cfe0db;border:1px solid #24302e;
       border-radius:10px;padding:10px 16px;font-weight:600">Xoá capture</button>
    <button id="reload" style="background:#161c1b;color:#cfe0db;border:1px solid #24302e;
       border-radius:10px;padding:10px 16px;font-weight:600">Tải lại</button>
  </div>

  <h2 style="font-size:15px;margin:26px 0 8px">Capture gần đây <span style="color:#8d9693;font-weight:400;font-size:12px">(request game đã đi qua relay)</span></h2>
  <div id="captures" style="color:#8d9693;font-size:13px">đang tải…</div>

  <h2 style="font-size:15px;margin:26px 0 8px">Rule đang áp</h2>
  <div id="rules" style="color:#8d9693;font-size:13px">đang tải…</div>

  <h2 style="font-size:15px;margin:26px 0 8px">Gợi ý từ capture</h2>
  <div id="suggestions" style="color:#8d9693;font-size:13px">đang tải…</div>
  <div id="note" style="color:#7dd3c0;min-height:20px;margin-top:8px;font-size:13px"></div>

  <p style="color:#5f6b68;font-size:12px;margin-top:30px">
    Relay ghi lại host/path/status/preview của traffic đi qua. Không có capture nghĩa là
    chưa có request nào tới được đây: kiểm tra profile đã cài, cert đã trust, và tunnel/proxy
    trên điện thoại đang trỏ đúng ${escapeHtml(view.publicHost)}:${view.proxyPort}.
  </p>
</div>

<script>
const note = document.getElementById('note');
let rules = [];

/* When the relay has an admin token, rule writes need it. Opening the
   dashboard once as /?token=... is enough: it stays in sessionStorage. */
const adminToken = new URLSearchParams(location.search).get('token')
  || sessionStorage.getItem('nimbus.admin') || '';
if (adminToken) sessionStorage.setItem('nimbus.admin', adminToken);

async function post(path, body) {
  const headers = { 'content-type': 'application/json' };
  if (adminToken) headers['x-admin-token'] = adminToken;
  const response = await fetch(path, {
    method: 'POST',
    headers,
    body: body === undefined ? '{}' : JSON.stringify(body)
  });
  if (response.status === 401) {
    note.textContent = 'Cần token: mở lại trang với /?token=<ADMIN_TOKEN>';
  }
  return response;
}

function cell(text, width) {
  const td = document.createElement('td');
  td.textContent = text;
  td.style = 'padding:7px 8px;border-top:1px solid #1d2624;color:#cfe0db;font-size:12.5px;'
    + (width ? 'width:' + width + 'px;' : '');
  return td;
}

function renderCaptures(data) {
  const box = document.getElementById('captures');
  box.innerHTML = '';
  if (!data.recent.length) {
    box.textContent = 'Chưa có request nào. Cài profile, bật trust, rồi chơi một trận.';
    return;
  }
  const table = document.createElement('table');
  table.style = 'width:100%;border-collapse:collapse';
  const head = document.createElement('tr');
  for (const label of ['Giờ', 'Host', 'Path', 'Mã', 'Bytes', 'Đã sửa']) {
    const th = document.createElement('th');
    th.textContent = label;
    th.style = 'text-align:left;padding:6px 8px;color:#8d9693;font-size:11px;text-transform:uppercase';
    head.append(th);
  }
  table.append(head);
  for (const record of data.recent) {
    const row = document.createElement('tr');
    const time = (record.ts || '').slice(11, 19);
    row.append(
      cell(time, 64),
      cell(record.host || '-'),
      cell((record.path || '-').slice(0, 48)),
      cell(String(record.status ?? record.error ?? '-'), 52),
      cell(String(record.resBytes ?? record.reqBytes ?? '-'), 56),
      cell((record.applied || []).join(', ') || '-', 130)
    );
    table.append(row);
  }
  box.append(table);
}

function renderRules(list) {
  rules = list;
  const box = document.getElementById('rules');
  box.innerHTML = '';
  if (!list.length) {
    box.textContent = 'Chưa áp rule nào. Relay đang chỉ ghi lại, chưa sửa gì.';
    return;
  }
  list.forEach((rule, index) => {
    const row = document.createElement('div');
    row.style = 'border:1px solid #24302e;border-radius:10px;padding:10px 12px;margin:8px 0;display:flex;gap:10px;align-items:center';
    const label = document.createElement('div');
    label.style = 'flex:1;font-size:13px;color:#eef1f0';
    label.textContent = (rule.host || '*') + ' ' + rule.pathPattern + ' → ' + rule.action;
    const remove = document.createElement('button');
    remove.textContent = 'Xoá';
    remove.style = 'background:#1b1414;color:#e9a3a3;border:1px solid #3a2222;border-radius:8px;padding:6px 12px';
    remove.onclick = async () => {
      const next = rules.filter((_, i) => i !== index);
      const response = await post('/rules', next);
      note.textContent = response.ok ? 'Đã xoá rule' : 'Xoá thất bại';
      refresh();
    };
    row.append(label, remove);
    box.append(row);
  });
}

function renderSuggestions(list) {
  const box = document.getElementById('suggestions');
  box.innerHTML = '';
  if (!list.length) {
    box.textContent = 'Chưa có ứng viên. Chơi một trận rồi quay lại.';
    return;
  }
  for (const suggestion of list) {
    const row = document.createElement('div');
    row.style = 'border:1px solid #24302e;border-radius:12px;padding:12px 14px;margin:10px 0';
    const head = document.createElement('div');
    const name = document.createElement('b');
    name.textContent = suggestion.host + suggestion.path;
    const meta = document.createElement('span');
    meta.style = 'color:#8d9693;font-size:12px;margin-left:8px';
    meta.textContent = 'score ' + suggestion.score + ' · ' + suggestion.calls + ' lần · ' + suggestion.action;
    head.append(name, meta);
    const pre = document.createElement('pre');
    pre.style = 'white-space:pre-wrap;color:#9fb3ae;font-size:11.5px;margin:10px 0;background:#14181a;padding:10px;border-radius:8px';
    pre.textContent = JSON.stringify(suggestion.rule, null, 2);
    const apply = document.createElement('button');
    apply.textContent = 'Apply';
    apply.style = 'background:#7dd3c0;color:#06110f;border:0;border-radius:9px;padding:8px 16px;font-weight:700';
    apply.onclick = async () => {
      // The patch suggestion is a response body-file pin at the game's real
      // CodePatchUrl. It is feature-tagged, so /rules would drop it; /pin
      // stores it under the codepatch feature and persists it.
      const isPin = suggestion.rule.action === 'respond' && Boolean(suggestion.rule.bodyFile);
      let response;
      if (isPin) {
        response = await post('/pin', suggestion.rule);
      } else {
        const next = rules.filter((r) => !(r.host === suggestion.rule.host && r.pathPattern === suggestion.rule.pathPattern));
        next.push(suggestion.rule);
        response = await post('/rules', next);
      }
      note.textContent = response.ok
        ? (isPin ? 'Đã pin patch tại URL thật của game — sống ngay' : 'Đã áp rule — sống ngay, không cần restart')
        : (isPin ? 'Pin thất bại' : 'Áp thất bại');
      refresh();
    };
    row.append(head, pre, apply);
    box.append(row);
  }
}

async function refresh() {
  try {
    const response = await fetch('/state', { cache: 'no-store' });
    const state = await response.json();
    document.getElementById('dot').style.background = '#7dd3c0';
    document.getElementById('meta').textContent =
      'proxy ' + state.publicHost + ':' + state.proxyPort
      + ' · ' + state.rules.length + ' rule · ' + state.captures.total + ' capture';
    renderRules(state.rules);
    renderCaptures(state.captures);
    renderSuggestions(state.suggestions);
  } catch (error) {
    document.getElementById('dot').style.background = '#e9a3a3';
    document.getElementById('meta').textContent = 'mất kết nối tới relay: ' + error;
  }
}

document.getElementById('reload').onclick = () => { note.textContent = ''; refresh(); };
document.getElementById('clear').onclick = async () => {
  const response = await post('/captures/clear');
  note.textContent = response.ok ? 'Đã xoá capture' : 'Xoá thất bại';
  refresh();
};

refresh();
setInterval(refresh, 5000);
</script>
</body>`;
}
