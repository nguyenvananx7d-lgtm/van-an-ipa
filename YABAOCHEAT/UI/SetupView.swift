import SwiftUI
import UIKit
import Foundation

/// The post-activation screen, modelled on the MIZZE 4.0 install video:
///
///   1. install the relay certificate and trust it;
///   2. start Super Proxy with the relay as an HTTP proxy;
///   3. launch Free Fire and open the control menu from this app or Safari.
///
/// The old container-injection flow still exists under "Công cụ nâng cao", but
/// it is deliberately one tap away: on a sealed iOS 18 container it fails with
/// `container access denied`, while the relay does not touch the game at all.
struct SetupView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore

    let onOpenTools: () -> Void

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
                    sessionCard
                    hostCard
                    certificateStep
                    proxyStep
                    menuStep
                    resetCard
                    advanced
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
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Mark(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("VORTEX ARENA")
                        .font(.headline.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(Palette.text)
                    Text(verbatim: "v4.0")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.textFaint)
                }
                Text("Cài đặt relay")
                    .font(.caption)
                    .foregroundStyle(Palette.textDim)
            }
            Spacer(minLength: 8)
            StateBadge(text: "ĐÃ XÁC THỰC", tone: .good)
        }
    }

    // MARK: - session

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THỜI HẠN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textFaint)
                Spacer()
                Text(auth.status.displayKey ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(remaining(at: context.date))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
            }
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.good)
                Text(auth.status.plan ?? "Premium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Text("ID \(device.activationId.prefix(8))…")
                    .font(.caption2.monospaced())
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

    // MARK: - relay host

    private var hostCard: some View {
        SectionGroup(title: "Máy chủ relay", symbol: "network") {
            HStack(spacing: 10) {
                TextField("relay.example.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
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
                    .font(.system(.footnote, design: .monospaced))
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
                    .font(.footnote)
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

    // MARK: - steps

    private var certificateStep: some View {
        stepCard(
            number: 1,
            title: "Cài chứng chỉ relay",
            symbol: "checkmark.shield",
            done: certificateDone
        ) {
            Text("Tải chứng chỉ của relay, cài profile rồi bật tin cậy đầy đủ. Bước này bắt buộc: không có nó, iOS sẽ không cho relay đọc lưu lượng HTTPS.")
                .font(.footnote)
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
                .font(.footnote)
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(proxyEndpoint ?? "—")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                Text("HTTP")
                    .font(.caption2.weight(.bold))
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
                .font(.footnote)
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

    // MARK: - reset / advanced

    private var resetCard: some View {
        SectionGroup(title: "Thiết bị", symbol: "iphone") {
            InfoRow(label: "ID máy", value: device.activationId)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reset thiết bị")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.text)
                    Text("Gỡ máy này khỏi key · 2 lần mỗi ngày")
                        .font(.caption)
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

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenTools) {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Palette.textDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Công cụ nâng cao")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.text)
                        Text("Luồng inject cũ, cấu hình ESP/Aim và nhật ký")
                            .font(.caption)
                            .foregroundStyle(Palette.textFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.textFaint)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, Metrics.rowPaddingH)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .machined(radius: 14)

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
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(width: 28, height: 28)

                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textDim)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                if done {
                    Text("XONG")
                        .font(.caption2.weight(.bold))
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
