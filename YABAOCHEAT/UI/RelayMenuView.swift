import SwiftUI
import WebKit
import UIKit

/// Full-screen wrapper around the relay's web menu.
///
/// The app does not need its own copy of the ESP/Aim controls in relay mode:
/// the menu lives at `<relay>/menu`, reads the signed session issued during
/// activation and writes the relay's live rule set. The session is handed over
/// in the URL once, then the page keeps it in `localStorage`.
struct RelayMenuView: View {
    let host: String
    @EnvironmentObject private var auth: AuthorizationStore
    @Environment(\.dismiss) private var dismiss

    @State private var reloadID: Int = 0

    private var menuURL: URL? {
        RelayActivationClient.menuURL(
            host: host,
            key: auth.status.displayKey ?? "",
            deviceKey: DeviceIdentityProvider.shared.activationId,
            session: auth.sessionToken
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Palette.hairline)
            if let menuURL {
                RelayWebView(url: menuURL)
                    .id(reloadID)
                    .background(Color.black)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Palette.textFaint)
                    Text("Chưa cấu hình máy chủ relay.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.text)
                    Text("Nhập địa chỉ relay ở màn hình cài đặt rồi mở lại.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.base)
            }
        }
        .background(Palette.base)
        .preferredColorScheme(.dark)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.surfaceHi))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng menu")

            VStack(alignment: .leading, spacing: 2) {
                Text("WEB MENU")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(Palette.text)
                Text(host)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                reloadID += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tải lại")

            Button {
                if let menuURL { UIApplication.shared.open(menuURL) }
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(menuURL == nil)
            .accessibilityLabel("Mở bằng Safari")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Palette.void)
    }
}

private struct RelayWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // The relay portal is first-party; keep its session cookie in the
        // web view's own store instead of the app's URLSession.
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil { uiView.load(URLRequest(url: url)) }
    }
}
