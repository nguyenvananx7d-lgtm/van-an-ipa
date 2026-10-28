/**
 * The MIZZE-style web portal served by the relay.
 *
 * `/login` is the page a user reaches from the app or from the profile's web
 * clip. It asks for the same three values as the reference product — Key,
 * Mật khẩu, ID máy — and posts them to `/auth/enter`. A successful exchange
 * lands on `/device`, which is the session page with the remaining days and the
 * two-per-day device reset.
 *
 * The page is deliberately server-rendered: it has to work before any app
 * JavaScript or asset bundle is installed, and the only client script is the
 * countdown and the 64-character device-id helper.
 */

export interface PortalLoginView {
  name: string;
  publicHost: string;
  proxyPort: number;
  /** Mount prefix when a reverse proxy strips `/relay`; empty at the root. */
  basePath: string;
  key: string;
  deviceKey: string;
  version: string;
  error?: string;
  notice?: string;
}

export interface PortalDeviceView {
  name: string;
  publicHost: string;
  proxyPort: number;
  /** Mount prefix when a reverse proxy strips `/relay`; empty at the root. */
  basePath: string;
  key: string;
  deviceId: string;
  plan: string;
  expiresAt?: string;
  resetRemaining: number;
  session: string;
  version: string;
  message?: string;
  error?: string;
}

function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const CSS = `
  :root {
    color-scheme: dark;
    --bg:#050706; --card:#0d1210; --line:#1d2925; --edge:#2b3a35;
    --text:#eef5f1; --muted:#8a9b94; --faint:#5c6d66;
    --green:#4ade80; --green-soft:rgba(74,222,128,.12); --red:#ff6b6b;
  }
  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
  html,body { margin:0; min-height:100%; background:var(--bg); }
  body {
    color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
    padding:max(22px,env(safe-area-inset-top)) 16px calc(28px + env(safe-area-inset-bottom));
    max-width:520px; margin:0 auto;
    background:
      radial-gradient(90% 55% at 50% -10%,rgba(74,222,128,.09),transparent 70%),
      var(--bg);
  }
  a { color:var(--green); text-decoration:none; }
  .brand { display:flex; align-items:center; justify-content:space-between; gap:10px; margin:8px 2px 22px; }
  .brand .mark { display:flex; align-items:baseline; gap:5px; font-size:24px; font-weight:900; letter-spacing:.02em; }
  .brand .mark sup { font-size:10px; color:var(--muted); font-weight:700; }
  .brand .arrow {
    width:34px; height:34px; display:grid; place-items:center; border-radius:50%;
    border:1px solid var(--line); color:var(--muted); font-size:15px;
  }
  .card { background:linear-gradient(180deg,rgba(255,255,255,.018),transparent 45%),var(--card);
          border:1px solid var(--line); border-radius:18px; padding:18px; box-shadow:0 24px 60px -36px #000; }
  .kicker { display:flex; align-items:center; justify-content:space-between; margin-bottom:16px; }
  .kicker span:first-child { color:var(--faint); font-size:10.5px; font-weight:800; letter-spacing:.16em; }
  .kicker span:last-child { color:var(--faint); font:10.5px ui-monospace,Menlo,monospace; }
  label { display:block; color:var(--muted); font-size:11.5px; font-weight:700; letter-spacing:.04em; margin:0 0 7px 2px; }
  .field { margin-bottom:14px; }
  input, textarea {
    width:100%; border:1px solid var(--edge); border-radius:12px; background:#070b09;
    color:var(--text); font:14px ui-monospace,SFMono-Regular,Menlo,monospace;
    padding:13px 13px; outline:none; transition:border-color .15s, box-shadow .15s;
  }
  input { letter-spacing:.08em; }
  input:focus, textarea:focus { border-color:rgba(74,222,128,.7); box-shadow:0 0 0 3px rgba(74,222,128,.12); }
  textarea { resize:none; line-height:1.45; letter-spacing:.04em; }
  .hint { color:var(--faint); font-size:11px; margin-top:5px; display:flex; justify-content:space-between; gap:8px; }
  .hint b { color:var(--green); font-weight:600; }
  button { font:inherit; width:100%; border:0; border-radius:12px; cursor:pointer; }
  .enter { margin-top:6px; padding:15px 16px; background:var(--green); color:#04110a; font-weight:900; font-size:15px; letter-spacing:.03em; }
  .enter:active { filter:brightness(.92); }
  .ghost { background:#111915; color:var(--text); border:1px solid var(--line); padding:13px 16px; font-weight:700; }
  .note { min-height:18px; margin:12px 2px 0; font-size:12.5px; }
  .note.bad { color:var(--red); }
  .note.info { color:var(--green); }
  .foot { display:flex; justify-content:space-between; gap:10px; margin-top:16px; padding-top:12px;
          border-top:1px solid var(--line); color:var(--faint); font:10.5px ui-monospace,Menlo,monospace; }
  .pill { font-size:10px; font-weight:800; letter-spacing:.12em; text-transform:uppercase; padding:4px 9px;
          border-radius:999px; color:var(--green); background:var(--green-soft); border:1px solid rgba(74,222,128,.3); }
  .pill.off { color:var(--red); background:rgba(255,107,107,.08); border-color:rgba(255,107,107,.3); }
  .row { display:flex; justify-content:space-between; gap:12px; padding:10px 0; border-bottom:1px solid var(--line); }
  .row:last-of-type { border-bottom:0; }
  .row .k { color:var(--muted); font-size:12px; }
  .row .v { color:var(--green); font:11.5px ui-monospace,Menlo,monospace; text-align:right; word-break:break-all; max-width:64%; }
  .row .v.plain { color:var(--text); }
  .countdown { font-size:26px; font-weight:900; letter-spacing:-.02em; line-height:1.15; margin:2px 0 4px; }
  .countdown small { display:block; font-size:11px; font-weight:600; letter-spacing:.06em; color:var(--faint); margin-top:5px; }
  .mono { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }
  .copy { width:auto; padding:0 4px; background:none; color:var(--green); font-size:11px; }
  .mini { color:var(--faint); font-size:11px; margin-top:7px; text-align:center; }
  .stack { display:flex; flex-direction:column; gap:9px; margin-top:14px; }
  .divider { height:1px; background:var(--line); margin:16px 0; }
`;

const DEVICE_SCRIPT = `
  var clock = document.getElementById('countdown');
  var expires = clock && clock.getAttribute('data-expires');
  function tick() {
    if (!clock) return;
    if (!expires) { clock.innerHTML = 'Không giới hạn<small>KEY KHÔNG CÓ NGÀY HẾT</small>'; return; }
    var ms = new Date(expires).getTime() - Date.now();
    if (ms <= 0) { clock.innerHTML = 'Đã hết hạn<small>GIA HẠN KEY ĐỂ TIẾP TỤC</small>'; return; }
    var total = Math.floor(ms / 1000);
    var d = Math.floor(total / 86400);
    var h = Math.floor((total % 86400) / 3600);
    var m = Math.floor((total % 3600) / 60);
    clock.innerHTML = (d > 0 ? d + ' ngày ' + h + ' giờ ' + m + ' phút' : (h > 0 ? h + ' giờ ' + m + ' phút' : m + ' phút'))
      + ' còn lại<small>THỜI HẠN CỦA KEY</small>';
  }
  tick();
  setInterval(tick, 30000);
`;

export function renderLogin(view: PortalLoginView): string {
  const name = esc(view.name);
  const base = esc(view.basePath);
  return `<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#050706">
<title>Đăng nhập · ${name}</title>
<style>${CSS}</style>
</head>
<body>
  <div class="brand">
    <div class="mark">${name.toUpperCase()}<sup>®</sup></div>
    <a class="arrow" href="${base}/menu" aria-label="Mở menu">↗</a>
  </div>

  <div class="card">
    <div class="kicker"><span>KÍCH HOẠT MENU</span><span>RELAY v${esc(view.version)}</span></div>
    <form action="${base}/auth/enter" method="post" id="enterForm" autocomplete="off">
      <div class="field">
        <label for="key">Key</label>
        <input id="key" name="key" value="${esc(view.key)}" placeholder="VT-XXXX-XXXX" autocomplete="off"
               autocapitalize="characters" spellcheck="false" required minlength="8" maxlength="128">
      </div>
      <div class="field">
        <label for="password">Mật khẩu</label>
        <input id="password" name="password" type="password" placeholder="Mật khẩu đi kèm key"
               autocomplete="current-password" required minlength="8" maxlength="128">
      </div>
      <div class="field">
        <label for="deviceId">ID máy</label>
        <textarea id="deviceId" name="deviceId" rows="3" placeholder="64 ký tự" required
                  minlength="64" maxlength="64" spellcheck="false">${esc(view.deviceKey)}</textarea>
        <div class="hint"><span>Dán ID từ ứng dụng hoặc để trống để tạo mới</span><b id="deviceCount">0/64</b></div>
      </div>
      <button class="enter" type="submit">Enter</button>
    </form>
    ${view.error ? `<div class="note bad">${esc(view.error)}</div>` : ""}
    ${view.notice ? `<div class="note info">${esc(view.notice)}</div>` : ""}
    <div class="foot"><span>${esc(view.publicHost)}:${view.proxyPort}</span><span>Reset thiết bị · 2 lần mỗi ngày</span></div>
  </div>
  <div class="mini">Chứng chỉ: <a href="${base}/ca.cer">ca.cer</a> · Profile: <a href="${base}/profile.mobileconfig">profile.mobileconfig</a></div>

<script>
(function () {
  var id = document.getElementById('deviceId');
  var count = document.getElementById('deviceCount');
  function paint() { count.textContent = (id.value || '').length + '/64'; }
  function fresh() {
    var bytes = new Uint8Array(32);
    (window.crypto || window.msCrypto).getRandomValues(bytes);
    var out = '';
    for (var i = 0; i < bytes.length; i++) out += ('0' + bytes[i].toString(16)).slice(-2);
    id.value = out;
  }
  if (!id.value) fresh();
  id.addEventListener('input', paint);
  paint();
  document.getElementById('enterForm').addEventListener('submit', function (event) {
    id.value = (id.value || '').trim().toLowerCase();
    if (id.value.length !== 64) { event.preventDefault(); alert('ID máy phải đúng 64 ký tự.'); }
  });
})();
</script>
</body>
</html>`;
}

export function renderDevice(view: PortalDeviceView): string {
  const name = esc(view.name);
  const base = esc(view.basePath);
  const menuHref = `${base}/menu?k=${encodeURIComponent(view.deviceId)}&session=${encodeURIComponent(view.session)}`;
  return `<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#050706">
<title>Thiết bị · ${name}</title>
<style>${CSS}</style>
</head>
<body>
  <div class="brand">
    <div class="mark">${name.toUpperCase()}<sup>®</sup></div>
    <span class="pill">ĐÃ XÁC THỰC</span>
  </div>

  <div class="card">
    <div class="kicker"><span>THIẾT BỊ</span><span>${esc(view.plan.toUpperCase())}</span></div>
    <div class="countdown" id="countdown" data-expires="${esc(view.expiresAt ?? "")}">Đang tính…</div>
    <div class="divider"></div>
    <div class="row"><span class="k">Key</span><span class="v">${esc(view.key)}</span></div>
    <div class="row"><span class="k">ID máy</span><span class="v">${esc(view.deviceId)}</span></div>
    <div class="row"><span class="k">Reset hôm nay</span><span class="v plain">${view.resetRemaining}/2 lần còn lại</span></div>

    ${view.message ? `<div class="note info">${esc(view.message)}</div>` : ""}
    ${view.error ? `<div class="note bad">${esc(view.error)}</div>` : ""}

    <div class="stack">
      <a class="ghost" href="${menuHref}" style="display:block;text-align:center;text-decoration:none">Mở menu điều khiển</a>
      <form action="${base}/device/reset" method="post" onsubmit="return confirm('Reset thiết bị này khỏi key?');">
        <input type="hidden" name="session" value="${esc(view.session)}">
        <input type="hidden" name="deviceId" value="${esc(view.deviceId)}">
        <button class="ghost" type="submit" ${view.resetRemaining <= 0 ? "disabled style=\"opacity:.45\"" : ""}>Reset thiết bị · ${view.resetRemaining}/2</button>
      </form>
    </div>
    <div class="foot"><span>${esc(view.publicHost)}:${view.proxyPort}</span><span>Reset thiết bị · 2 lần mỗi ngày</span></div>
  </div>
  <div class="mini"><a href="${base}/login">Đăng nhập thiết bị khác</a> · <a href="${base}/menu">Web menu</a></div>

<script>${DEVICE_SCRIPT}</script>
</body>
</html>`;
}
