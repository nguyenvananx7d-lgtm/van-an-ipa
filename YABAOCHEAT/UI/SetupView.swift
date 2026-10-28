import SwiftUI
import UIKit
import Foundation

/// The only screen the operator needs: activate, read the two-minute guide,
/// then play. The ESP/Aim switches live inside the game now — the floating
/// icon menu — so this app is a launcher, not a control panel.
///
/// The relay section below stays for the `.hotfix` route (iOS that denies the
/// task port); on the Ghost route it is advisory only.
struct SetupView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var inject: InjectStore
    @EnvironmentObject var menu: MenuStore

    let onOpenSettings: () -> Void

    @AppStorage("relay.host") private var storedHost: String = ""
    @AppStorage("setup.cert") private var certificateDone: Bool = false
    @AppStorage("setup.proxy") private var proxyDone: Bool = false

    @State private var host: String = ""
    @State private var probe: ProbeState = .idle
    @State private var copiedProxy: Bool = false
    @State private var showMenu: Bool = false
    @State private var showReset: Bool = false
    @State private var resetBusy: Bool = false
    @State private var showCertificateHelp: Bool = false
    @State private var showProxyHelp: Bool = false
    @State private var runningTask: Task<Void, Never>?
    /// Bumped when the cached device id lands, so the ID rows re-render.
    @State private var deviceIdTick: Int = 0

    private let superProxyURL = URL(
        string: "https://apps.apple.com/vn/app/super-proxy-tunnel-your-apps/id6478274781?l=vi"
    )!

    private var device: DeviceIdentityProvider { .shared }

    private enum ProbeState: Equatable {
        case idle
        case busy
        case ok(Int)
        case failed(String)
    }

    var body: some View {
        ZStack {
            ThemeBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    header
                    if let message = auth.revocationMessage {
                        Banner(kind: .error, message: message)
                    }
                    if let notice = auth.noticeMessage {
                        Banner(kind: .info, message: notice)
                    }
                    injectCard
                    guideCard
                    sessionCard
                    relayGroup
                    resetCard
                    footer
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if host.isEmpty {
                host = storedHost.isEmpty ? RelayActivationClient.configuredHost : storedHost
            }
            /* Container resolution (MCM) is file-system work with an XPC
               round trip; running it straight off onAppear stalls the first
               frame on a busy device. Hand it to a task so the UI commits
               first. */
            Task { inject.evaluate() }
        }
        .fullScreenCover(isPresented: $showMenu) {
            RelayMenuView(host: host)
        }
        .alert("Cài chứng chỉ", isPresented: $showCertificateHelp) {
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            Text("Safari mở trang chứng chỉ. Chọn Cho phép, rồi vào Cài đặt > Cài đặt chung > VPN & Quản lý thiết bị để cài. Sau đó mở Cài đặt > Cài đặt chung > Giới thiệu > Cài đặt tin cậy chứng chỉ và bật tin cậy đầy đủ cho chứng chỉ relay.")
        }
        .alert("Super Proxy", isPresented: $showProxyHelp) {
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            Text("Mở Super Proxy, chọn HTTP, nhập máy chủ và cổng bên dưới, rồi bấm Start. Giữ Super Proxy chạy trong lúc chơi. Nếu dùng Wi-Fi, có thể thêm proxy trong Cài đặt Wi-Fi thay thế.")
        }
        .alert("Reset thiết bị?", isPresented: $showReset) {
            Button("Huỷ", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetBusy = true
                Task {
                    _ = await auth.resetDevice()
                    resetBusy = false
                }
            }
        } message: {
            Text("Thiết bị này sẽ được gỡ khỏi key. Bạn còn tối đa 2 lần reset mỗi ngày.")
        }
        .animation(.easeInOut(duration: 0.2), value: auth.revocationMessage)
        .onReceive(NotificationCenter.default.publisher(for: Notifications.deviceIdReady)) { _ in
            deviceIdTick &+= 1
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Mark(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("VORTEX ARENA")
                    .font(.brand(23))
                    .tracking(1.2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Palette.accentHi, Palette.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                HStack(spacing: 7) {
                    Text("v4.0")
                        .font(.ui(11))
                        .foregroundStyle(Palette.textFaint)
                    Text("·")
                        .foregroundStyle(Palette.textFaint)
                    Text(InjectPlan.route().displayName)
                        .font(.ui(11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                statusBadge
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textDim)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surface))
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cài đặt")
            }
        }
    }

    private var statusBadge: some View {
        let s = auth.status
        if s.isOnline {
            return StateBadge(text: "ĐÃ XÁC THỰC", tone: .good)
        }
        if case .checking = s {
            return StateBadge(text: "ĐANG KIỂM TRA", tone: .busy)
        }
        return StateBadge(text: "NGOẠI TUYẾN", tone: .bad)
    }

    // MARK: - inject

    private var injectCard: some View {
        SectionGroup(title: "Kích hoạt", symbol: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // Which title the injector launches. Free Fire and Free Fire Max
                // are different bundle ids; picking the wrong one fails the
                // launch before the payload can ever map.
                SegmentedControl(
                    selection: $menu.selectedGame,
                    items: Game.allCases.map { SegItem(value: $0, title: $0.displayName) }
                )

                // Two delivery paths. Modern = relay hotfix (needs Super Proxy
                // and the CA). Legacy = the patch is staged into the game's
                // container, which this install can write — no proxy, so the
                // phone never loses its network.
                Toggle(isOn: Binding(
                    get: { menu.controls.preferModernInjection },
                    set: { value in
                        var controls = menu.controls
                        controls.preferModernInjection = value
                        if !value {
                            // The sweep is not optional on the container route.
                            controls.antiBan = true
                        }
                        menu.controls = controls
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Injection hiện đại")
                            .font(.ui(14, weight: .medium))
                            .foregroundStyle(Palette.text)
                        Text("Tắt để stage patch thẳng vào container — không cần proxy, không mất mạng")
                            .font(.ui(11))
                            .foregroundStyle(Palette.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !menu.controls.preferModernInjection {
                    // Persistent staging (the MIZZE behaviour): the patch stays
                    // in the container, the game loads it on every launch, and
                    // the player never presses Inject again. Off means the
                    // consume-once pass deletes the files fifteen seconds after
                    // the game boots — cleaner on disk, but every session needs
                    // one Inject press first.
                    Toggle(isOn: Binding(
                        get: { !menu.controls.consumePayload },
                        set: { keep in
                            var controls = menu.controls
                            controls.consumePayload = !keep
                            menu.controls = controls
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Giữ patch trong container")
                                .font(.ui(14, weight: .medium))
                                .foregroundStyle(Palette.text)
                            Text("Bật: stage một lần, mở game là có menu (kiểu MIZZE). Tắt: patch bị xoá sau ~15s, an toàn hơn nhưng mỗi phiên phải Kích hoạt lại.")
                                .font(.ui(11))
                                .foregroundStyle(Palette.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                let route = InjectPlan.route()
                HStack(spacing: 8) {
                    Image(systemName: route == .ghost ? "sparkles" : "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accentHi)
                    Text(route.displayName)
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    Text(InjectPlan.readiness(for: route))
                        .font(.ui(11))
                        .foregroundStyle(Palette.textFaint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Button {
                    runningTask = Task {
                        await inject.install(
                            expectedDigest: auth.expectedPatchSHA256,
                            monitorMs: auth.patchOpenMonitorMs
                        )
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("KÍCH HOẠT")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(!auth.status.isOnline || runningTask != nil)

                if let status = inject.status {
                    HStack(spacing: 8) {
                        Image(systemName: inject.isActive ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(inject.isActive ? Palette.good : Palette.textFaint)
                        Text(status)
                            .font(.ui(13))
                            .foregroundStyle(Palette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                if inject.isActive && InjectPlan.route() == .ghost {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(Palette.accent)
                        Text("Biểu tượng vàng đã nổi trong game — chạm để mở menu.")
                            .font(.ui(12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        runningTask = Task { await inject.keepFeatures() }
                    } label: {
                        Text("Giữ tính năng, gỡ app")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(AccentButtonStyle(prominent: false))
                    .disabled(runningTask != nil)

                    Button {
                        runningTask = Task { await inject.uninject() }
                    } label: {
                        Text("Gỡ hoàn toàn")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(AccentButtonStyle(prominent: false, destructive: true))
                    .disabled(runningTask != nil)
                }
            }
            .padding(Metrics.rowPaddingH)
        }
    }

    // MARK: - guide

    private var guideCard: some View {
        SectionGroup(title: "Cách dùng", symbol: "book") {
            VStack(alignment: .leading, spacing: 0) {
                guideStep(1, "Bấm Kích hoạt — game tự khởi động, hack đã nằm trong tiến trình trước cả frame đầu tiên.")
                guideStep(2, "Trong game, biểu tượng logo nổi ở mép phải màn hình. Chạm một lần để mở menu.")
                guideStep(3, "Menu có 11 công tắc: ESP, khung, tên, khoảng cách, máu, tracer, vòng FOV, aim, chỉ mục tiêu nhìn thấy, bỏ qua kẻ gục, aim theo chạm.")
                guideStep(4, "Chạm từng dòng để bật/tắt ngay lập tức — không cần quay lại app.")
                guideStep(5, "Đổi cấu hình trong app sẽ ghi đè công tắc đang bật trong game.")

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.info)
                    Text("\"Aim touch\" bật sẵn: aim chỉ kéo khi có ngón tay chạm màn hình — vết aim giống tay người hơn.")
                        .font(.ui(12))
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.rowPaddingH)
                .padding(.vertical, 12)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.ui(12, weight: .bold))
                .foregroundStyle(Palette.void)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.accent))
            Text(text)
                .font(.ui(14))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowPaddingH)
        .padding(.vertical, 11)
        .rowDivider()
    }

    // MARK: - session

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THỜI HẠN")
                    .font(.ui(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textFaint)
                Spacer()
                Text(auth.status.displayKey ?? "—")
                    .font(.ui(12))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(remaining(at: context.date))
                    .font(.ui(26, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ui(12))
                    .foregroundStyle(Palette.good)
                Text(auth.status.plan ?? "Premium")
                    .font(.ui(12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Text("ID \(device.activationId.prefix(8))…")
                    .font(.ui(11))
                    .foregroundStyle(Palette.textFaint)
            }
        }
        .padding(17)
        .machined(radius: 16)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Palette.accent.opacity(0.08))
                .frame(width: 90, height: 90)
                .offset(x: 30, y: -38)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private func remaining(at date: Date) -> String {
        guard let expires = auth.status.expiresAt else { return "Không giới hạn" }
        let total = Int(expires.timeIntervalSince(date))
        guard total > 0 else { return "Đã hết hạn" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) ngày \(hours) giờ \(minutes) phút còn lại" }
        if hours > 0 { return "\(hours) giờ \(minutes) phút còn lại" }
        return "\(minutes) phút còn lại"
    }

    // MARK: - relay (hotfix route only)

    private var relayGroup: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.8))
                Text("RELAY — CHỈ CẦN KHI ROUTE LÀ HOTFIX")
                    .font(.ui(12, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .textCase(.uppercase)
                    .tracking(0.9)
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .padding(.horizontal, 2)

            hostCard
            certificateStep
            proxyStep
            menuStep
        }
    }

    private var hostCard: some View {
        SectionGroup(title: "Máy chủ relay", symbol: "server.rack") {
            HStack(spacing: 10) {
                TextField("relay.example.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.ui(15))
                    .onChange(of: host) { new in
                        storedHost = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                if !host.isEmpty {
                    Button {
                        host = ""
                        storedHost = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, Metrics.rowPaddingH)
            .rowDivider()

            HStack(spacing: 10) {
                Text(proxyEndpoint ?? "Chưa có địa chỉ proxy")
                    .font(.ui(13))
                    .foregroundStyle(proxyEndpoint == nil ? Palette.textFaint : Palette.text)
                Spacer(minLength: 8)
                if let proxyEndpoint {
                    Button {
                        UIPasteboard.general.string = proxyEndpoint
                        copiedProxy = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(copiedProxy ? "Đã chép" : "Chép", systemImage: copiedProxy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
            .rowDivider()

            HStack(spacing: 10) {
                Text(probeText)
                    .font(.ui(13))
                    .foregroundStyle(probeTint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    probeRelay()
                } label: {
                    if probe == .busy {
                        ProgressView().tint(Palette.accent)
                    } else {
                        Text("Kiểm tra")
                    }
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(probe == .busy || baseURL == nil)
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
        }
    }

    private var probeText: String {
        switch probe {
        case .idle:
            return "Kiểm tra máy chủ trước khi cài."
        case .busy:
            return "Đang kiểm tra…"
        case .ok(let count):
            return "Relay OK · \(count) request đã bắt"
        case .failed(let message):
            return "Không kết nối được: \(message)"
        }
    }

    private var probeTint: Color {
        switch probe {
        case .ok: return Palette.good
        case .failed: return Palette.bad
        default: return Palette.textDim
        }
    }

    // MARK: - relay steps

    private var certificateStep: some View {
        stepCard(
            number: 1,
            title: "Cài chứng chỉ relay",
            symbol: "checkmark.shield",
            done: certificateDone
        ) {
            Text("Tải chứng chỉ của relay, cài profile rồi bật tin cậy đầy đủ. Bước này bắt buộc: không có nó, iOS sẽ không cho relay đọc lưu lượng HTTPS.")
                .font(.ui(13))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    guard let url = RelayActivationClient.certificateURL(host: host) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("Tải chứng chỉ", systemImage: "arrow.down.circle")
                }
                .buttonStyle(ChipButtonStyle(filled: true))
                .disabled(baseURL == nil)

                Button("Hướng dẫn") { showCertificateHelp = true }
                    .buttonStyle(ChipButtonStyle())

                Spacer(minLength: 6)

                Button {
                    certificateDone.toggle()
                } label: {
                    Image(systemName: certificateDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(certificateDone ? Palette.good : Palette.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đánh dấu đã cài chứng chỉ")
            }
        }
    }

    private var proxyStep: some View {
        stepCard(
            number: 2,
            title: "Bật Super Proxy",
            symbol: "antenna.radiowaves.left.and.right",
            done: proxyDone
        ) {
            Text("Mở Super Proxy, chọn giao thức HTTP, nhập địa chỉ relay bên dưới rồi bấm Start. Giữ ứng dụng chạy nền trong lúc chơi.")
                .font(.ui(13))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(proxyEndpoint ?? "—")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                Text("HTTP")
                    .font(.ui(11, weight: .bold))
                    .foregroundStyle(Palette.textFaint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.surfaceHi))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .insetWell(radius: 10)

            HStack(spacing: 10) {
                Button {
                    UIApplication.shared.open(superProxyURL)
                } label: {
                    Label("Mở App Store", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(ChipButtonStyle(filled: true))

                Button("Hướng dẫn") { showProxyHelp = true }
                    .buttonStyle(ChipButtonStyle())

                Spacer(minLength: 6)

                Button {
                    proxyDone.toggle()
                } label: {
                    Image(systemName: proxyDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(proxyDone ? Palette.good : Palette.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đánh dấu đã bật proxy")
            }
        }
    }

    private var menuStep: some View {
        stepCard(
            number: 3,
            title: "Mở menu điều khiển",
            symbol: "slider.horizontal.3",
            done: false
        ) {
            Text("Sau khi Super Proxy báo Started, mở Free Fire rồi quay lại đây. Menu chạy trên relay nên không cần cài thêm gì vào game.")
                .font(.ui(13))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    showMenu = true
                } label: {
                    Label("Mở menu", systemImage: "rectangle.inset.filled.and.person.filled")
                }
                .buttonStyle(ChipButtonStyle(filled: true))
                .disabled(baseURL == nil)

                Button {
                    guard let url = RelayActivationClient.loginURL(
                        host: host,
                        key: auth.status.displayKey ?? "",
                        deviceKey: device.activationId
                    ) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("Mở bằng Safari", systemImage: "safari")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(baseURL == nil)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - device / footer

    private var resetCard: some View {
        SectionGroup(title: "Thiết bị", symbol: "iphone") {
            InfoRow(label: "ID máy", value: device.activationId)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reset thiết bị")
                        .font(.ui(15, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text("Gỡ máy này khỏi key · 2 lần mỗi ngày")
                        .font(.ui(12))
                        .foregroundStyle(Palette.textFaint)
                }
                Spacer(minLength: 8)
                Button {
                    showReset = true
                } label: {
                    if resetBusy {
                        ProgressView().tint(Palette.bad)
                    } else {
                        Text("Reset")
                    }
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(resetBusy || auth.sessionToken == nil)
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                language.hasChosen = false
            } label: {
                Label(language.selected.displayName, systemImage: "globe")
            }
            .buttonStyle(ChipButtonStyle())

            Spacer()

            Button(role: .destructive) {
                auth.logout()
            } label: {
                Text("Đăng xuất")
            }
            .buttonStyle(ChipButtonStyle())
        }
        .padding(.top, 2)
    }

    // MARK: - step chrome

    private func stepCard<Content: View>(
        number: Int,
        title: String,
        symbol: String,
        done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(done ? Palette.good.opacity(0.16) : Palette.surfaceHi)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.good)
                    } else {
                        Text("\(number)")
                            .font(.ui(12, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(width: 28, height: 28)

                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textDim)
                    Text(title)
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                if done {
                    Text("XONG")
                        .font(.ui(11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.good)
                }
            }
            content()
        }
        .padding(16)
        .machined(radius: 16)
    }

    // MARK: - networking

    private var baseURL: URL? {
        RelayActivationClient.baseURL(from: host)
    }

    private var proxyEndpoint: String? {
        RelayActivationClient.proxyEndpoint(from: host)
    }

    private func probeRelay() {
        guard let base = baseURL else { return }
        probe = .busy
        var request = URLRequest(url: base.appendingPathComponent("state"))
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let captures = object?["captures"] as? [String: Any]
                let total = captures?["total"] as? Int
                await MainActor.run {
                    if code == 200 {
                        probe = .ok(total ?? 0)
                    } else {
                        probe = .failed("HTTP \(code)")
                    }
                }
            } catch {
                await MainActor.run {
                    probe = .failed(error.localizedDescription)
                }
            }
        }
    }
}
