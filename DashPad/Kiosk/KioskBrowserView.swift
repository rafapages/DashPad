import SwiftUI
import WebKit

struct KioskBrowserView: View {
    @Environment(AppSettings.self) var settings
    @Environment(KioskManager.self) var kioskManager

    var body: some View {
        WebViewRepresentable(settings: settings)
            .ignoresSafeArea()
    }
}

// MARK: - UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let settings: AppSettings

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        injectUserScripts(into: config)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .black
        webView.isOpaque = true

        loadHome(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(settings: settings) }

    // MARK: - Script injection

    private func injectUserScripts(into config: WKWebViewConfiguration) {
        // Kiosk UX hardening: disable text selection and context menus
        let kioskCSS = """
        * { -webkit-user-select: none !important; -webkit-touch-callout: none !important; }
        """
        addCSS(kioskCSS, to: config)

        // User-provided custom CSS
        if !settings.customCSS.isEmpty {
            addCSS(settings.customCSS, to: config)
        }

        // User-provided custom JS
        if !settings.customJS.isEmpty {
            let script = WKUserScript(
                source: settings.customJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }
    }

    private func addCSS(_ css: String, to config: WKWebViewConfiguration) {
        // Escape for JS string literal
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let source = """
        (function(){
            var s = document.createElement('style');
            s.innerHTML = "\(escaped)";
            document.head.appendChild(s);
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
    }

    private func loadHome(in webView: WKWebView) {
        guard let url = URL(string: settings.homeURL) else { return }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Coordinator

extension WebViewRepresentable {
    class Coordinator: NSObject, WKNavigationDelegate {
        let settings: AppSettings
        private var retryTimer: Timer?

        init(settings: AppSettings) {
            self.settings = settings
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            guard !settings.allowedDomainList.isEmpty else { return .allow }
            let host = url.host ?? ""
            let allowed = settings.allowedDomainList.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }
            return allowed ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            scheduleRetry(webView: webView)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            scheduleRetry(webView: webView)
        }

        private func scheduleRetry(webView: WKWebView) {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak webView, weak self] _ in
                guard let webView, let self,
                      let url = URL(string: self.settings.homeURL) else { return }
                webView.load(URLRequest(url: url))
            }
        }
    }
}

#Preview {
    KioskBrowserView()
        .environment(AppSettings())
        .environment(KioskManager())
}
