/* Control panel runtime.
 *
 * The native host owns the truth: it pushes { session, values, defaults } and
 * receives edits back through the `panel` message handler. The page keeps a
 * local draft so a switch does not leave the app until "Áp dụng cấu hình" is
 * pressed, exactly like the reference build.
 *
 * Opened outside the app (no webkit bridge) the page falls back to the demo
 * state below, so the layout can be reviewed in a browser.
 */

(function () {
  "use strict";

  const bridge = {
    get available() {
      return !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.panel);
    },
    post(message) {
      if (this.available) window.webkit.messageHandlers.panel.postMessage(message);
    },
  };

  /* The eight palettes the in-game patch maps. Any other name falls back to
     the first entry, so the swatches have to use these exact keys. */
  const PALETTE = [
    ["emerald", "#52FAA8"], ["ice", "#61D1FF"], ["violet", "#BD8FFF"],
    ["amber", "#FFBD4D"], ["rose", "#FF73A8"], ["lime", "#BDFF6B"],
    ["aqua", "#4DFFEB"], ["pearl", "#F0F7FF"],
  ];

  /* ---- schema ------------------------------------------------------ */

  let TABS = [
    { id: "aim", label: "Aim", groups: [
      { label: "AIM", rows: [
        { type: "toggle", k: "isEnabled", title: "Aim Bot", chip: "MAGNET",
          sub: "Khoá mục tiêu gần tâm trong FOV" },
        { type: "slider", k: "aimbotRadiusValue", title: "Aimbot Radius", unit: "px",
          min: 40, max: 320, step: 5 },
        { type: "segment", k: "aimTarget", title: "Aim Target", stack: true,
          sub: "MIXED trộn đầu–ngực theo Aim Height",
          options: [["head", "HEAD"], ["neck", "NECK"], ["body", "BODY"], ["mixed", "MIXED"]] },
        { type: "segment", k: "drawFov", title: "Aim FOV", stack: true,
          sub: "Vòng FOV quanh tâm",
          options: [[false, "OFF"], [true, "ALWAYS"]] },
        { type: "toggle", k: "aimCrosshair", title: "Crosshair", chip: "RING",
          sub: "Vòng + chấm giữa tâm khi aim đang bật" },
        { type: "toggle", k: "lineEsp", title: "Aim Line",
          sub: "Line nét đứt từ tâm tới mục tiêu" },
        { type: "toggle", k: "aimVisibleOnly", title: "Silent Aim Filter", chip: "FILTER",
          sub: "Bỏ qua enemy ngoài tầm nhìn" },
        { type: "toggle", k: "ignoreKnocked", title: "Skip Knocked",
          sub: "Bỏ qua enemy đã gục" },
        { type: "toggle", k: "sniperScope", title: "Sniper Scope", chip: "OVERLAY",
          sub: "Vẽ kính ngắm quanh tâm" },
        { type: "toggle", k: "aimTouchGate", title: "Touch Gate", chip: "GATE",
          sub: "Chỉ hỗ trợ khi đang chạm màn hình" },
        { type: "slider", k: "aimDistance", title: "Aim Distance", unit: "m",
          min: 20, max: 400, step: 10 },
      ] },
      { label: "ĐỘ NHẠY", rows: [
        { type: "slider", k: "aimSmooth", title: "Aim Smooth",
          min: 0.02, max: 1, step: 0.02 },
        { type: "slider", k: "aimReactionMs", title: "Aim Reaction", unit: "ms",
          min: 60, max: 400, step: 10 },
        { type: "slider", k: "aimLeadMs", title: "Aim Lead", unit: "ms",
          min: 0, max: 250, step: 5 },
        { type: "slider", k: "hitChance", title: "Hit Chance", unit: "%",
          min: 50, max: 100, step: 1 },
        { type: "slider", k: "aimHeight", title: "Aim Height",
          min: 0.35, max: 1.6, step: 0.05 },
      ] },
      { label: "HÀNH VI", rows: [
        { type: "toggle", k: "aimLock", title: "Hard Lock", chip: "LOCK",
          sub: "Ghìm mục tiêu liên tục — tắt nhịp nhả chống ban" },
        { type: "toggle", k: "aimHumanize", title: "Humanize",
          sub: "Jitter, overshoot, micro-break" },
        { type: "toggle", k: "aimLatch", title: "Target Latch",
          sub: "Giữ mục tiêu cũ thay vì nhảy sang địch khác" },
        { type: "toggle", k: "aimRamp", title: "Ramp",
          sub: "Tăng lực dần trong 0.35 s đầu" },
        { type: "slider", k: "aimDeadzone", title: "Dead Zone", unit: "°",
          min: 0, max: 2, step: 0.05 },
        { type: "slider", k: "aimStickiness", title: "Stickiness",
          min: 0, max: 1, step: 0.05 },
        { type: "slider", k: "aimSwitchBias", title: "Switch Bias",
          min: 0, max: 1, step: 0.05 },
        { type: "slider", k: "aimMaxTurn", title: "Max Turn", unit: "°/f",
          min: 20, max: 720, step: 10 },
        { type: "slider", k: "aimTrackGain", title: "Track Gain",
          min: 0, max: 2, step: 0.05 },
        { type: "slider", k: "aimOvershootDeg", title: "Overshoot", unit: "°",
          min: 0, max: 8, step: 0.1 },
        { type: "slider", k: "aimBreakMinMs", title: "Break Min", unit: "ms",
          min: 20, max: 600, step: 10 },
        { type: "slider", k: "aimBreakMaxMs", title: "Break Max", unit: "ms",
          min: 100, max: 1200, step: 10 },
        { type: "slider", k: "aimKillGuardMs", title: "Kill Guard", unit: "ms",
          min: 0, max: 3000, step: 50 },
      ] },
    ] },

    { id: "esp", label: "ESP", groups: [
      { label: "ESP MAIN", rows: [
        { type: "toggle", k: "masterEsp", title: "ESP Master",
          sub: "Công tắc tổng của lớp ESP" },
        { type: "toggle", k: "boxEsp", title: "Box ESP", chip: "W2S",
          sub: "Khung viền enemy" },
        { type: "toggle", k: "lineEsp", title: "Line ESP",
          sub: "Line nét đứt từ tâm tới enemy" },
        { type: "toggle", k: "healthEsp", title: "Health Bar",
          sub: "Thanh máu enemy" },
        { type: "toggle", k: "nameEsp", title: "Name Tag",
          sub: "Tên enemy" },
        { type: "toggle", k: "distanceEsp", title: "Distance Tag",
          sub: "Khoảng cách (m)" },
        { type: "toggle", k: "skeletonEsp", title: "Skeleton ESP",
          sub: "Khung xương enemy" },
        { type: "toggle", k: "tracerEsp", title: "Top Tracer",
          sub: "Tracer kéo từ đáy màn hình" },
        { type: "toggle", k: "drawEnemyCount", title: "ESP Count",
          sub: "Số địch trên màn hình" },
        { type: "toggle", k: "esp360Arrows", title: "360° Arrows",
          sub: "Mũi tên chỉ hướng địch ngoài khung" },
      ] },
      { label: "KHUNG BOX", rows: [
        { type: "segment", k: "boxType", title: "Box Type", stack: true,
          options: [["corner", "CORNERED"], ["edge", "2D BOUNDING"]] },
        { type: "slider", k: "espBoxScalePercent", title: "Box Size", unit: "%",
          min: 50, max: 200, step: 1 },
        { type: "slider", k: "espBoxOffsetY", title: "Box Drop", unit: "px",
          min: -60, max: 60, step: 1 },
        { type: "toggle", k: "espBoxFill", title: "Box Fill",
          sub: "Nền mờ bên trong khung" },
        { type: "slider", k: "espBoxFillAlpha", title: "Fill Opacity",
          min: 0.05, max: 0.9, step: 0.01 },
      ] },
      { label: "LỌC & HIỂN THỊ", rows: [
        { type: "segment", k: "healthType", title: "Health Side", stack: true,
          options: [["right", "RIGHT"], ["left", "LEFT"]] },
        { type: "toggle", k: "espVisibleOnly", title: "Visible Only",
          sub: "Chỉ vẽ địch đang trong tầm nhìn" },
        { type: "toggle", k: "espShowDowned", title: "Show Downed",
          sub: "Vẫn vẽ enemy đã gục" },
        { type: "toggle", k: "espHeadDot", title: "Head Dot",
          sub: "Chấm đánh dấu trên đầu enemy" },
        { type: "slider", k: "espMaxDistance", title: "Max Distance", unit: "m",
          min: 20, max: 500, step: 10 },
        { type: "slider", k: "espTextScale", title: "Text Scale",
          min: 0.5, max: 1.6, step: 0.05 },
      ] },
      { label: "CHI TIẾT", rows: [
        { type: "toggle", k: "espSmoothBox", title: "Smooth Box",
          sub: "Làm mượt box theo frame trước" },
        { type: "toggle", k: "espFadeFar", title: "Fade Far",
          sub: "Mờ dần khi tới giới hạn khoảng cách" },
        { type: "toggle", k: "espOffscreenArrows", title: "Offscreen Arrows",
          sub: "Vẽ bearing cho địch ngoài màn hình" },
        { type: "toggle", k: "espHealthText", title: "Health Text",
          sub: "In HP dưới dòng khoảng cách (≤ 120 m)" },
        { type: "toggle", k: "espGlow", title: "Glow",
          sub: "Halo sau box và line" },
        { type: "toggle", k: "espNameChip", title: "Name Chip",
          sub: "Nền tối sau tên enemy" },
        { type: "toggle", k: "espSkeletonJoints", title: "Joint Rings",
          sub: "Vòng tròn ở khớp xương" },
        { type: "toggle", k: "espTargetHighlight", title: "Target Highlight",
          sub: "Đánh dấu địch đang bị aim khoá" },
      ] },
      { label: "MÀU", rows: [
        { type: "palette", k: "espPalette", title: "Palette",
          sub: "8 bảng màu patch đọc được" },
        { type: "toggle", k: "rainbow", title: "Rainbow",
          sub: "Đổi màu overlay theo chu kỳ" },
        { type: "toggle", k: "allRainbow", title: "All Rainbow",
          sub: "Rainbow cho toàn bộ phần tử" },
      ] },
    ] },

    { id: "antiban", label: "Anti-Ban", groups: [
      { label: "GIỚI HẠN TRONG GAME", rows: [
        { type: "segment", k: "aimStealth", title: "Stealth Tier", stack: true,
          sub: "0 Lock · 1 Low · 2 Balanced · 3 Quiet",
          options: [[0, "LOCK"], [1, "LOW"], [2, "BALANCED"], [3, "QUIET"]] },
        { type: "segment", k: "aimFrom", title: "Solve From", stack: true,
          sub: "Camera là reticle, Eye là viên đạn thật",
          options: [["camera", "CAMERA"], ["eye", "EYE"]] },
        { type: "slider", k: "aimHoldGain", title: "Hold Gain",
          min: 0.3, max: 2.5, step: 0.05 },
        { type: "slider", k: "aimCommitMs", title: "Commit Interval", unit: "ms",
          min: 10, max: 500, step: 10 },
        { type: "slider", k: "antiBanMaxEngageMs", title: "Max Engage", unit: "ms",
          min: 300, max: 8000, step: 100 },
        { type: "slider", k: "antiBanCooldownMs", title: "Release Cooldown", unit: "ms",
          min: 0, max: 5000, step: 100 },
        { type: "note",
          text: "Assist ghi đủ mọi frame — nhảy frame chính là lý do reticle trượt địch. Stealth giờ nằm ở độ dài lock, tốc độ quay và nhịp gọi SetAimRotation (Commit Interval). Max Engage / Release Cooldown do Tier quyết định, slider chỉ ghi đè khi bạn đụng vào." },
      ] },
    ] },

    { id: "system", label: "System", groups: [
      { label: "TÀI KHOẢN", rows: [{ type: "account" }] },
      { label: "ANTI-BAN", rows: [
        { type: "toggle", k: "antiBan", title: "Anti-Ban",
          sub: "Dọn dấu vết ở đầu và cuối phiên" },
        { type: "toggle", k: "consumePayload", title: "Consume Payload",
          sub: "Xoá payload sau khi game đã đọc" },
      ] },
      { label: "KEY INJECTOR", rows: [
        { type: "action", title: "Nạp cấu hình vào game",
          sub: "Ghi patch + localConfig vào container",
          label: "TẢI INJECTOR", action: "inject" },
        { type: "note",
          text: "Áp dụng sẽ ghi localConfig vào container. Patch có live-reload đọc lại file khi đang chơi, nên switch có hiệu lực sau khoảng 2 giây." },
      ] },
    ] },
  ];

  /* ---- state ------------------------------------------------------- */

  let S = { session: {}, values: {}, defaults: {} };
  let draft = {};
  let activeTab = "aim";
  let dirty = false;
  let appliedFlash = 0;
  let elapsed = 0;
  let remaining = 24 * 3600;
  let injector = { visible: false, state: "idle", title: "ĐANG TẢI KEY INJECTOR...", url: "", status: "" };

  const $ = (id) => document.getElementById(id);

  /* ---- relay mode ----------------------------------------------------
   * The same page is served by the relay at /menu, which is the web clip the
   * installed profile opens. There the switches are relay features: each one
   * installs traffic rules, not in-game drawing. Detection is by origin —
   * inside the app the page is file:// and carries the native bridge; on the
   * relay it is http(s) and has neither.
   */
  const params = new URLSearchParams(location.search);
  const relayMode = !bridge.available
    && (params.get("mode") === "relay" || /^https?:$/.test(location.protocol));

  const RELAY = { token: "", payload: null, state: null, hwid: "" };

  function relayKey(name) { return "relay." + name; }

  function relayDeviceId() {
    let id = localStorage.getItem(relayKey("device"));
    if (id) return id;
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
    id = hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-" + hex.slice(12, 16) + "-"
      + hex.slice(16, 20) + "-" + hex.slice(20);
    localStorage.setItem(relayKey("device"), id);
    return id;
  }

  function decodeEnvelope(envelope) {
    const binary = atob(envelope.data);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    return pad2(date.getDate()) + "/" + pad2(date.getMonth() + 1) + "/" + date.getFullYear();
  }

  function maskKey(key) {
    if (!key) return "—";
    if (key.length <= 10) return key;
    return key.slice(0, 6) + "…" + key.slice(-4);
  }

  async function relayGet(path) {
    const headers = {};
    if (RELAY.token) headers["x-menu-session"] = RELAY.token;
    return fetch(path, { headers, cache: "no-store" });
  }

  async function relayPost(path, body) {
    const headers = { "content-type": "application/json" };
    if (RELAY.token) headers["x-menu-session"] = RELAY.token;
    return fetch(path, { method: "POST", headers, body: JSON.stringify(body || {}) });
  }

  function showLogin(message) {
    $("panel").style.display = "none";
    $("loginOverlay").hidden = false;
    $("loginNote").className = "login-note" + (message ? " bad" : "");
    $("loginNote").textContent = message || "";
    $("keyInput").value = localStorage.getItem(relayKey("key")) || "";
  }

  async function relayLogin() {
    const note = $("loginNote");
    const key = ($("keyInput").value || "").trim();
    if (!key) {
      note.className = "login-note bad";
      note.textContent = "Nhập key trước.";
      return;
    }
    note.className = "login-note";
    note.textContent = "Đang kiểm tra key…";

    injector = {
      visible: true, state: "busy", title: "ĐANG TẢI KEY INJECTOR...",
      url: "key=" + key + "&deviceId=" + RELAY.hwid,
      status: "Đang xác thực với relay…",
    };
    renderInjector();

    try {
      const response = await fetch("/menu/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          key,
          hwid: RELAY.hwid,
          device_name: "Web menu",
          ios_version: navigator.userAgent,
        }),
      });
      const envelope = await response.json();
      if (!response.ok || !envelope.data) {
        throw new Error(envelope.error || "Không kết nối được máy chủ bản quyền");
      }
      const payload = decodeEnvelope(envelope);
      if (payload.status !== "valid") throw new Error(payload.message || payload.status);

      RELAY.token = payload.session || "";
      RELAY.payload = payload;
      localStorage.setItem(relayKey("session"), RELAY.token);
      localStorage.setItem(relayKey("payload"), JSON.stringify(payload));
      localStorage.setItem(relayKey("key"), key);
      elapsed = 0;

      injector = {
        visible: true, state: "done", title: "KEY INJECTOR",
        url: "key=" + key + "&deviceId=" + RELAY.hwid,
        status: "Đã kết nối — đang tải menu",
      };
      renderInjector();
      $("loginOverlay").hidden = true;
      $("panel").style.display = "";

      await relayRefresh();
      setTimeout(() => { injector.visible = false; renderInjector(); }, 1400);
    } catch (error) {
      injector = { visible: false, state: "fail", title: "KEY INJECTOR", url: "", status: "" };
      renderInjector();
      note.className = "login-note bad";
      note.textContent = String(error.message || error);
    }
  }

  function relayLogout() {
    RELAY.token = "";
    RELAY.payload = null;
    RELAY.state = null;
    localStorage.removeItem(relayKey("session"));
    localStorage.removeItem(relayKey("payload"));
    showLogin("");
  }

  async function relayRefresh() {
    const response = await relayGet("/state");
    if (!response.ok) throw new Error("relay " + response.status);
    RELAY.state = await response.json();
    applyRelayState();
  }

  function relayTabs(state) {
    const features = state.features || [];
    const rules = state.rules || [];

    const net = {
      id: "net", label: "Mạng",
      groups: [
        { label: "KÊNH RELAY", rows: features.map((feature) => ({
            type: "toggle", k: feature.id, title: feature.label, sub: feature.detail,
            chip: feature.risky ? "RISKY" : (feature.hits ? feature.hits + " HIT" : ""),
          })) },
        { label: "GHI CHÚ", rows: [{ type: "note",
            text: "Mỗi switch là một rule chặn/sửa traffic trên relay. Bật xong, request kế tiếp đi qua tunnel là bị xử lý ngay." }] },
      ],
    };

    const ruleRows = rules.slice(0, 60).map((rule) => ({
      type: "info",
      title: rule.host || "*",
      sub: (rule.pathPattern || "/") + " → " + (rule.action || "rewrite"),
      chip: rule.feature ? String(rule.feature).toUpperCase() : "MANUAL",
    }));

    const ruleTab = {
      id: "rules", label: "Rule",
      groups: [{
        label: rules.length + " RULE ĐANG CHẠY",
        rows: ruleRows.length ? ruleRows
          : [{ type: "note", text: "Relay chưa có rule nào — chỉ ghi traffic." }],
      }],
    };

    const acct = {
      id: "acct", label: "Tài khoản",
      groups: [
        { label: "PHIÊN", rows: [{ type: "account" }] },
        { label: "RELAY", rows: [
          { type: "action", title: "Đồng bộ lại", sub: state.publicHost || "relay",
            label: "TẢI LẠI STATE", action: "refresh" },
          { type: "action", title: "Đăng xuất", sub: "Xoá phiên trên máy này",
            label: "ĐĂNG XUẤT", action: "logout" },
        ] },
      ],
    };

    return [net, ruleTab, acct];
  }

  function applyRelayState() {
    const state = RELAY.state || { features: [], rules: [], name: "Relay" };
    const payload = RELAY.payload || {};
    const values = {};
    (state.features || []).forEach((feature) => { values[feature.id] = !!feature.enabled; });

    const expires = payload.expiresAt ? Date.parse(payload.expiresAt) : NaN;
    const daysLeft = Number.isNaN(expires)
      ? 0
      : Math.max(0, Math.ceil((expires - Date.now()) / 86400000));

    S = {
      session: {
        brand: state.name || "VORTEX ARENA",
        plan: String(payload.plan || "RELAY").toUpperCase(),
        connected: true,
        daysLeft,
        expiry: payload.expiresAt ? formatDate(payload.expiresAt) : "—",
        key: maskKey(localStorage.getItem(relayKey("key")) || ""),
        deviceId: RELAY.hwid,
        game: (state.publicHost || "relay") + (state.proxyPort ? ":" + state.proxyPort : ""),
        injectActive: true,
        injectState: "relay",
        elapsedSeconds: elapsed,
        remainingSeconds: Math.max(0, 24 * 3600 - elapsed),
        injectUrl: "",
      },
      values,
      defaults: Object.assign({}, values),
    };

    TABS = relayTabs(state);
    draft = Object.assign({}, values);
    dirty = false;
    activeTab = TABS.some((tab) => tab.id === activeTab) ? activeTab : TABS[0].id;
    renderAll();
  }

  async function relayApply() {
    const changes = Object.keys(draft).filter((key) => draft[key] !== S.values[key]);
    if (!changes.length) {
      toast("Không có thay đổi");
      return;
    }
    $("applyBtn").disabled = true;
    for (const id of changes) {
      const response = await relayPost("/features", { id, enabled: !!draft[id] });
      if (!response.ok) {
        $("applyBtn").disabled = false;
        toast("Không đổi được " + id + " (" + response.status + ")");
        return;
      }
    }
    $("applyBtn").disabled = false;
    dirty = false;
    appliedFlash = Date.now();
    renderSync();
    toast("Đã áp dụng " + changes.length + " thay đổi");
    try { await relayRefresh(); } catch (error) { toast("Relay: " + error.message); }
  }

  async function initRelay() {
    RELAY.hwid = relayDeviceId();
    RELAY.token = localStorage.getItem(relayKey("session")) || "";
    try {
      const saved = localStorage.getItem(relayKey("payload"));
      RELAY.payload = saved ? JSON.parse(saved) : null;
    } catch (error) {
      RELAY.payload = null;
    }
    if (!RELAY.token) {
      showLogin("");
      return;
    }
    try {
      await relayRefresh();
    } catch (error) {
      RELAY.token = "";
      RELAY.payload = null;
      localStorage.removeItem(relayKey("session"));
      showLogin("Phiên cũ không dùng được — nhập lại key.");
    }
  }

  function bridgeAvailable() { return bridge.available; }

  function demoState() {
    const values = {
      isEnabled: true, aimEnabled: true, silentAim: false, headRate: 55,
      aimbotRadiusValue: 250, aimTarget: "head", drawFov: true, lineEsp: true,
      aimVisibleOnly: true, ignoreKnocked: true, sniperScope: false,
      aimTouchGate: true, hitChance: 50, aimDistance: 120,
      aimSmooth: 0.42, aimReactionMs: 260, aimLeadMs: 60, aimHeight: 0.8,
      aimDeadzone: 0.2, aimLatch: true, aimRamp: true, aimHumanize: true,
      aimStickiness: 0.45, aimSwitchBias: 0.3, aimMaxTurn: 110,
      aimTrackGain: 0.7, aimOvershootDeg: 1.8,
      aimBreakMinMs: 140, aimBreakMaxMs: 420, aimKillGuardMs: 900,
      aimLock: false, aimCrosshair: true,
      aimStealth: 2, aimFrom: "camera", aimHoldGain: 1.0, aimCommitMs: 50,
      antiBanMaxEngageMs: 2400, antiBanCooldownMs: 900,
      masterEsp: true, boxEsp: true, healthEsp: true, nameEsp: true,
      distanceEsp: true, skeletonEsp: true, tracerEsp: true,
      drawEnemyCount: true, esp360Arrows: true, boxType: "corner",
      espBoxScalePercent: 116, espBoxOffsetY: 8, espBoxFill: true,
      espBoxFillAlpha: 0.16, healthType: "right", espVisibleOnly: true,
      espShowDowned: true, espHeadDot: true, espMaxDistance: 250,
      espTextScale: 1.05, espPalette: "emerald",
      espSmoothBox: true, espFadeFar: true, espOffscreenArrows: true,
      espHealthText: true, espGlow: true, espNameChip: true,
      espSkeletonJoints: true, espTargetHighlight: true,
      rainbow: false, allRainbow: false, antiBan: true, consumePayload: true,
    };
    return {
      session: {
        brand: "VORTEX ARENA", plan: "PRO", connected: true, daysLeft: 30,
        expiry: "15/11/2026", key: "DEMO-KEY-0000", deviceId: "DEMO-DEVICE-0000",
        game: "Free Fire", injectActive: false, injectState: "ready",
        elapsedSeconds: 10931, remainingSeconds: 80269,
        injectUrl: "key=DEMO-KEY-0000&deviceId=DEMO-DEVICE-0000",
      },
      values,
      defaults: Object.assign({}, values, { isEnabled: false, aimEnabled: false }),
    };
  }

  /* ---- helpers ----------------------------------------------------- */

  function valueOf(key) {
    return Object.prototype.hasOwnProperty.call(draft, key) ? draft[key] : S.values[key];
  }

  function decimalsOf(step) {
    const s = String(step);
    return s.indexOf(".") >= 0 ? s.split(".")[1].length : 0;
  }

  function formatSlider(value, row) {
    const d = decimalsOf(row.step);
    const v = Number(value);
    const text = d ? v.toFixed(d) : String(Math.round(v));
    return row.unit ? text + row.unit : text;
  }

  function pad2(n) { return n < 10 ? "0" + n : String(n); }

  function hhmmss(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    return pad2(Math.floor(s / 3600)) + ":" + pad2(Math.floor((s % 3600) / 60)) + ":" + pad2(s % 60);
  }

  function countEnabled() {
    const rows = TABS.flatMap((tab) => tab.groups.flatMap((group) => group.rows));
    return rows.filter((row) => row.type === "toggle" && valueOf(row.k)).length;
  }

  /* ---- render ------------------------------------------------------ */

  function renderTabs() {
    const host = $("tabs");
    host.innerHTML = "";
    TABS.forEach((tab) => {
      const b = document.createElement("button");
      b.className = "tab" + (tab.id === activeTab ? " active" : "");
      b.textContent = tab.label;
      b.dataset.tab = tab.id;
      host.appendChild(b);
    });
  }

  function renderHeader() {
    const s = S.session || {};
    $("brand").textContent = s.brand || "CONTROL";
    $("planChip").textContent = s.plan || "PRO";
    $("daysChip").textContent = s.daysLeft != null ? s.daysLeft + "D" : "—";
    $("expiryValue").textContent = s.expiry || "--/--/----";
    const conn = $("connValue");
    conn.classList.toggle("dead", !s.connected);
    conn.innerHTML = "<i></i>" + (s.connected ? "LIVE" : "OFFLINE");
    $("enabledValue").textContent = String(countEnabled());
  }

  function renderTab() {
    const host = $("body");
    const scroll = host.scrollTop;
    host.innerHTML = "";
    const tab = TABS.find((t) => t.id === activeTab) || TABS[0];

    tab.groups.forEach((group) => {
      const wrap = document.createElement("section");
      wrap.className = "group";
      const label = document.createElement("div");
      label.className = "group-label";
      label.textContent = group.label;
      wrap.appendChild(label);

      const card = document.createElement("div");
      card.className = "card";
      group.rows.forEach((row) => {
        if (row.show && !row.show(draft)) return;
        card.appendChild(renderRow(row));
      });
      wrap.appendChild(card);
      host.appendChild(wrap);
    });

    host.scrollTop = scroll;
  }

  function renderRow(row) {
    if (row.type === "toggle") return renderToggle(row);
    if (row.type === "slider") return renderSlider(row);
    if (row.type === "segment") return renderSegment(row);
    if (row.type === "palette") return renderPalette(row);
    if (row.type === "action") return renderAction(row);
    if (row.type === "account") return renderAccount();
    if (row.type === "info") return renderInfo(row);
    return renderNote(row);
  }

  function renderInfo(row) {
    const el = document.createElement("div");
    el.className = "row";
    const col = document.createElement("div");
    col.className = "row-col";
    const title = document.createElement("div");
    title.className = "row-title mono-title";
    title.textContent = row.title;
    col.appendChild(title);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.style.fontFamily = "var(--font-mono)";
      sub.style.fontSize = "10px";
      sub.textContent = row.sub;
      col.appendChild(sub);
    }
    el.appendChild(col);
    if (row.chip) {
      const chip = document.createElement("span");
      chip.className = "chip";
      chip.textContent = row.chip;
      el.appendChild(chip);
    }
    return el;
  }

  function titleBlock(row) {
    const col = document.createElement("div");
    col.className = "row-col";
    const title = document.createElement("div");
    title.className = "row-title";
    title.appendChild(document.createTextNode(row.title));
    if (row.chip) {
      const chip = document.createElement("span");
      chip.className = "chip";
      chip.textContent = row.chip;
      title.appendChild(chip);
    }
    col.appendChild(title);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.textContent = row.sub;
      col.appendChild(sub);
    }
    return col;
  }

  function renderToggle(row) {
    const el = document.createElement("div");
    el.className = "row";
    el.appendChild(titleBlock(row));

    const on = !!valueOf(row.k);
    const btn = document.createElement("button");
    btn.className = "toggle" + (on ? " on" : "");
    btn.setAttribute("role", "switch");
    btn.setAttribute("aria-checked", String(on));
    btn.addEventListener("click", () => {
      const next = !valueOf(row.k);
      draft[row.k] = next;
      if (row.onSet) row.onSet(next);
      dirty = true;
      renderHeader();
      renderSync();
      renderTab();
    });
    el.appendChild(btn);
    return el;
  }

  function fillPercent(row, value) {
    const min = row.min;
    const max = row.max;
    return ((Number(value) - min) / (max - min)) * 100;
  }

  function renderSlider(row) {
    const el = document.createElement("div");
    el.className = "row stack";

    const head = document.createElement("div");
    head.className = "slider-head";
    const title = document.createElement("div");
    title.className = "row-title";
    title.textContent = row.title;
    const pill = document.createElement("span");
    pill.className = "value-pill";
    const value = Number(valueOf(row.k));
    pill.textContent = formatSlider(value, row);
    head.appendChild(title);
    head.appendChild(pill);

    const input = document.createElement("input");
    input.type = "range";
    input.min = String(row.min);
    input.max = String(row.max);
    input.step = String(row.step);
    input.value = String(value);
    input.style.setProperty("--pct", fillPercent(row, value) + "%");
    input.addEventListener("input", () => {
      const raw = Number(input.value);
      const d = decimalsOf(row.step);
      const next = d ? Number(raw.toFixed(d)) : Math.round(raw);
      draft[row.k] = next;
      pill.textContent = formatSlider(next, row);
      input.style.setProperty("--pct", fillPercent(row, next) + "%");
      dirty = true;
      renderSync();
    });

    el.appendChild(head);
    el.appendChild(input);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.textContent = row.sub;
      el.appendChild(sub);
    }
    return el;
  }

  function renderSegment(row) {
    const el = document.createElement("div");
    el.className = "row stack";

    const head = document.createElement("div");
    head.className = "row-title";
    head.textContent = row.title;
    el.appendChild(head);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.textContent = row.sub;
      el.appendChild(sub);
    }

    const seg = document.createElement("div");
    seg.className = "segment";
    const current = valueOf(row.k);
    row.options.forEach(([value, label]) => {
      const b = document.createElement("button");
      const active = current === value;
      b.className = active ? "active" : "";
      b.textContent = label;
      b.addEventListener("click", () => {
        draft[row.k] = value;
        dirty = true;
        renderSync();
        renderTab();
      });
      seg.appendChild(b);
    });
    el.appendChild(seg);
    return el;
  }

  function renderPalette(row) {
    const el = document.createElement("div");
    el.className = "row stack";
    const head = document.createElement("div");
    head.className = "row-title";
    head.textContent = row.title;
    el.appendChild(head);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.textContent = row.sub;
      el.appendChild(sub);
    }

    const wrap = document.createElement("div");
    wrap.className = "palette";
    const current = valueOf(row.k);
    PALETTE.forEach(([name, color]) => {
      const b = document.createElement("button");
      b.className = "swatch" + (name === current ? " active" : "");
      b.style.background = color;
      b.title = name;
      b.addEventListener("click", () => {
        draft[row.k] = name;
        dirty = true;
        renderSync();
        renderTab();
      });
      wrap.appendChild(b);
    });
    el.appendChild(wrap);
    return el;
  }

  function renderAction(row) {
    const el = document.createElement("div");
    el.className = "row stack";
    const head = document.createElement("div");
    head.className = "row-title";
    head.textContent = row.title;
    el.appendChild(head);
    if (row.sub) {
      const sub = document.createElement("div");
      sub.className = "row-sub";
      sub.textContent = row.sub;
      el.appendChild(sub);
    }
    const b = document.createElement("button");
    b.className = "action-btn";
    b.textContent = row.label;
    b.addEventListener("click", () => {
      if (row.action === "inject") startInject();
      else if (row.action === "refresh") {
        relayRefresh().then(() => toast("Đã đồng bộ relay")).catch((error) => toast("Relay: " + error.message));
      } else if (row.action === "logout") relayLogout();
    });
    el.appendChild(b);
    return el;
  }

  function renderAccount() {
    const el = document.createElement("div");
    el.className = "row stack";
    const s = S.session || {};

    const title = document.createElement("div");
    title.className = "row-title";
    title.textContent = "Thiết bị";
    el.appendChild(title);

    const keyRow = document.createElement("div");
    keyRow.className = "row-sub mono";
    keyRow.textContent = "KEY  " + (s.key || "—");
    el.appendChild(keyRow);

    const idWrap = document.createElement("div");
    idWrap.style.cssText = "display:flex;align-items:center;gap:10px;margin-top:10px";
    const idText = document.createElement("div");
    idText.className = "mono";
    idText.style.flex = "1";
    idText.textContent = s.deviceId || "—";
    const copy = document.createElement("button");
    copy.className = "copy-chip";
    copy.textContent = "Sao chép";
    copy.addEventListener("click", () => {
      bridge.post({ type: "copy", text: s.deviceId || "" });
      toast("Đã sao chép Device ID");
    });
    idWrap.appendChild(idText);
    idWrap.appendChild(copy);
    el.appendChild(idWrap);

    const game = document.createElement("div");
    game.className = "row-sub";
    game.style.marginTop = "8px";
    game.textContent = "TARGET  " + (s.game || "—");
    el.appendChild(game);
    return el;
  }

  function renderNote(row) {
    const el = document.createElement("div");
    el.className = "note";
    el.textContent = row.text;
    return el;
  }

  function renderSync() {
    const state = $("syncState");
    const applied = Date.now() - appliedFlash < 2200;
    if (dirty) {
      state.className = "sync-state dirty";
      state.textContent = "Chưa áp dụng";
    } else if (applied) {
      state.className = "sync-state good";
      state.textContent = "Đã áp dụng";
    } else {
      state.className = "sync-state";
      state.textContent = "";
    }
    $("syncLabel").textContent = "Đã đồng bộ " + hhmmss(elapsed);
    $("applyBtn").classList.toggle("done", !dirty && applied);
  }

  function renderSession() {
    $("sessionTimer").textContent = hhmmss(remaining);
    const pct = Math.max(0, Math.min(100, (remaining / (24 * 3600)) * 100));
    $("sessionBar").style.width = pct.toFixed(1) + "%";
    $("sessionPct").textContent = Math.round(pct) + "%";
  }

  function renderInjector() {
    const overlay = $("injectOverlay");
    overlay.hidden = !injector.visible;
    if (!injector.visible) return;
    $("injectTitle").textContent = injector.title;
    $("injectUrl").textContent = injector.url;
    $("injectStatus").textContent = injector.status;
    const spinner = $("injectSpinner");
    spinner.className = "spinner" +
      (injector.state === "done" ? " done" : injector.state === "fail" ? " fail" : "");
    $("injectClose").hidden = injector.state === "busy" || injector.state === "idle";
  }

  function renderAll() {
    renderHeader();
    renderTabs();
    renderTab();
    renderSession();
    renderSync();
    renderInjector();
  }

  /* ---- actions ----------------------------------------------------- */

  function applyDraft() {
    if (relayMode) { relayApply(); return; }
    bridge.post({ type: "apply", values: draft });
    appliedFlash = Date.now();
    dirty = false;
    renderSync();
    toast("Đang áp dụng cấu hình…");
  }

  function resetDraft() {
    if (relayMode) {
      draft = {};
      Object.keys(S.values).forEach((key) => { draft[key] = false; });
    } else {
      draft = Object.assign({}, S.defaults || {});
    }
    dirty = true;
    renderHeader();
    renderTab();
    renderSync();
    toast("Đã khôi phục mặc định — bấm Áp dụng để ghi");
  }

  function startInject() {
    injector = {
      visible: true, state: "busy", title: "ĐANG TẢI KEY INJECTOR...",
      url: (S.session && S.session.injectUrl) || "key=…&deviceId=…",
      status: "Đang ghi patch vào container…",
    };
    renderInjector();
    bridge.post({ type: "inject", values: draft });
  }

  let toastTimer = 0;
  function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 1900);
  }

  /* ---- native API -------------------------------------------------- */

  window.panelAPI = {
    setState(state) {
      S = {
        session: state.session || {},
        values: state.values || {},
        defaults: state.defaults || state.values || {},
      };
      draft = Object.assign({}, S.values);
      dirty = false;
      elapsed = Number(S.session.elapsedSeconds || 0);
      remaining = Number(S.session.remainingSeconds || 24 * 3600);
      renderAll();
    },
    setInjector(payload) {
      injector = Object.assign({}, injector, payload || {});
      renderInjector();
    },
    toast(text) { toast(text); },
    setTab(id) {
      if (TABS.some((t) => t.id === id)) {
        activeTab = id;
        renderTabs();
        renderTab();
      }
    },
  };

  /* ---- wiring ------------------------------------------------------ */

  function tick() {
    elapsed += 1;
    if (remaining > 0) remaining -= 1;
    renderSync();
    renderSession();
  }

  document.addEventListener("click", (event) => {
    const tab = event.target.closest(".tab");
    if (tab) {
      activeTab = tab.dataset.tab;
      renderTabs();
      renderTab();
    }
  });

  $("closeBtn").addEventListener("click", () => {
    if (relayMode) {
      // A web clip has no host to dismiss to; park the menu instead.
      $("panel").style.display = "none";
      $("loginOverlay").hidden = true;
      return;
    }
    bridge.post({ type: "close" });
  });
  $("applyBtn").addEventListener("click", applyDraft);
  $("resetBtn").addEventListener("click", resetDraft);
  $("loginBtn").addEventListener("click", relayLogin);
  $("keyInput").addEventListener("keydown", (event) => {
    if (event.key === "Enter") relayLogin();
  });
  $("injectClose").addEventListener("click", () => {
    injector.visible = false;
    renderInjector();
    bridge.post({ type: "injector-dismiss" });
  });

  setInterval(tick, 1000);

  window.addEventListener("load", () => {
    if (bridgeAvailable()) {
      bridge.post({ type: "ready" });
      return;
    }
    if (relayMode) {
      initRelay();
      return;
    }
    window.panelAPI.setState(demoState());
  });
})();
