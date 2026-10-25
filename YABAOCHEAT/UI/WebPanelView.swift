import SwiftUI
import WebKit

/// The web control panel, presented full screen. Rendering, rows and the
/// apply/reset flow all live in `Resources/panel`; this view is only the
/// container and the bridge.
struct WebPanelView: View {
    @ObservedObject var panel = PanelStore.shared

    var body: some View {
        PanelWebContainer(store: panel)
            .ignoresSafeArea()
            .background(Color.black)
            .preferredColorScheme(.dark)
    }
}

private struct PanelWebContainer: UIViewRepresentable {
    let store: PanelStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "panel")
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        // The page pads itself with env(safe-area-inset-*); letting UIKit also
        // inset the scroll view would apply the notch twice.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        store.webView = webView

        if let url = Self.panelIndexURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(Self.missingResourceHTML, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "panel")
    }

    /// XcodeGen copies resources either flattened into the bundle root or into
    /// a `panel` subdirectory depending on how the group is resolved; accept
    /// both instead of failing the load on one build layout.
    static func panelIndexURL() -> URL? {
        if let nested = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "panel") {
            return nested
        }
        return Bundle.main.url(forResource: "index", withExtension: "html")
    }

    static let missingResourceHTML = """
    <html><body style="background:#050506;color:#F1F2F3;font:16px -apple-system;padding:40px">
    <p>panel resources missing</p></body></html>
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let store: PanelStore

        init(store: PanelStore) {
            self.store = store
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "panel" else { return }
            let body = message.body
            Task { @MainActor in
                await self.store.handle(body)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.store.pushState()
                self.store.pushInjector()
            }
        }
    }
}
