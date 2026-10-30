import SwiftUI
import UIKit

/// The local build's only screen.
///
/// One button. It applies the conservative profile, runs `localInject`, and the
/// delivery path launches the game; the in-game panel opens itself on its first
/// GUI frame. The gear and log are the only secondary surfaces.
struct LocalHomeView: View {
    @EnvironmentObject private var menu: MenuStore
    @EnvironmentObject private var inject: InjectStore

    @State private var showSettings = false
    @State private var showLog = false
    @State private var busy = false

    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                brand
                Spacer(minLength: 20)
                statusLine
                activateButton
                hint
                if inject.isActive { stopButton }
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                ScrollView(showsIndicators: false) {
                    SettingView()
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.vertical, 16)
                }
                .background(ThemeBackground())
                .navigationTitle("CÀI ĐẶT")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ĐÓNG") { showSettings = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $showLog) {
            NavigationView {
                LogView()
                    .navigationTitle("NHẬT KÝ")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("ĐÓNG") { showLog = false }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            inject.refreshExploitStatus()
            inject.evaluate()
        }
    }

    // MARK: - chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Game.allCases) { game in
                    Button {
                        menu.selectedGame = game
                        inject.evaluate()
                    } label: {
                        if menu.selectedGame == game {
                            Label(game.displayName, systemImage: "checkmark")
                        } else {
                            Text(game.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(menu.selectedGame.displayName.uppercased())
                        .font(.ui(10.5, weight: .semibold))
                        .tracking(1.1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Palette.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }

            Spacer(minLength: 0)

            iconButton("doc.text.magnifyingglass", label: "Nhật ký") {
                showLog = true
            }
            iconButton("gearshape", label: "Cài đặt") {
                showSettings = true
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textDim)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.surface))
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var brand: some View {
        VStack(spacing: 12) {
            brandMark
            VStack(spacing: 4) {
                Text("VORTEX ARENA")
                    .font(.brand(30))
                    .tracking(2.2)
                    .foregroundStyle(Palette.text)
                Text("dev: ngvanan10")
                    .font(.ui(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private var brandUIImage: UIImage? {
        let url = Bundle.main.url(forResource: "vortex-icon-128", withExtension: "png",
                                  subdirectory: "icons")
            ?? Bundle.main.url(forResource: "vortex-icon-128", withExtension: "png")
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    @ViewBuilder
    private var brandMark: some View {
        if let ui = brandUIImage {
            Image(uiImage: ui)
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.edgeTop, lineWidth: 1)
                )
                .shadow(color: Palette.accent.opacity(0.34), radius: 22, y: 8)
        } else {
            Mark(size: 76)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(inject.isActive ? Palette.good : Palette.accent)
                .frame(width: 6, height: 6)
            Text(inject.isActive ? "ĐANG CHẠY" : (busy ? "ĐANG KÍCH HOẠT" : "SẴN SÀNG"))
                .font(.ui(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(inject.isActive ? Palette.good : Palette.textDim)
            if let status = inject.status, !status.isEmpty, !inject.isActive {
                Text("· \(status)")
                    .font(.ui(11))
                    .foregroundStyle(Palette.textFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activateButton: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView()
                        .tint(Palette.void)
                } else {
                    Image(systemName: inject.isActive ? "checkmark.shield.fill" : "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                }
                Text(inject.isActive ? "ĐANG CHẠY" : (busy ? "ĐANG KÍCH HOẠT…" : "KÍCH HOẠT"))
                    .font(.ui(19, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundStyle(Palette.void)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.accentHi.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Palette.accent.opacity(0.32), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(busy || inject.isActive)
        .padding(.top, 16)
    }

    private var hint: some View {
        Text("Nhấn KÍCH HOẠT — game tự mở, menu tự bật.")
            .font(.ui(11))
            .foregroundStyle(Palette.textFaint)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
    }

    private var stopButton: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task { @MainActor in
                await inject.uninject()
                busy = false
            }
        } label: {
            Text("TẮT")
                .font(.ui(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.bad)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.bad.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Palette.bad.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.top, 10)
    }

    private var footer: some View {
        Text("LOCAL · không key · không proxy · không CA")
            .font(.ui(9.5, weight: .medium))
            .tracking(1.0)
            .foregroundStyle(Palette.textFaint)
            .frame(maxWidth: .infinity)
    }

    // MARK: - action

    private func activate() {
        guard !busy, !inject.isActive else { return }
        // The in-game panel has every control; the app only needs to arm the
        // conservative profile and let the delivery route launch the game.
        menu.applySafeProfile()
        busy = true
        Task { @MainActor in
            await inject.localInject()
            busy = false
        }
    }
}
