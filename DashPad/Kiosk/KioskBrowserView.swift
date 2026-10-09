// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// KioskBrowserView.swift - WKWebView wrapper for the main dashboard.
// The WebView is created once and kept alive for the full app session so that navigating
// back from idle never triggers a full page reload.

import SwiftUI
import WebKit

struct KioskBrowserView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var kioskManager: KioskManager
    @StateObject private var webController = WebViewController()
    @State private var urlReloadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            WebViewRepresentable(settings: settings, webController: webController)
                .ignoresSafeArea()
            if let failure = webController.loadFailure {
                EmptyStatePlaceholder(
                    title: "Can't reach dashboard",
                    systemImage: "wifi.exclamationmark",
                    description: failureDescription(failure)
                )
                .background(Color.black.ignoresSafeArea())
                .environment(\.colorScheme, .dark)
            }
            BrowserDrawer(webController: webController)
        }
        .ignoresSafeArea()
        .onChangeCompat(of: settings.homeURL) { newURL in
            // Debounce: TextField fires on every keystroke; only reload after user stops typing.
            urlReloadTask?.cancel()
            urlReloadTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                webController.goHome(url: newURL)
            }
        }
        .onChangeCompat(of: settings.allowedDomains) { _ in
            // A dashboard blocked by the allowlist is never retried; try again once the list changes.
            guard webController.loadFailure?.willRetry == false else { return }
            webController.goHome(url: settings.homeURL)
        }
    }

    private func failureDescription(_ failure: LoadFailure) -> String {
        var text = "\(failure.url)\n\n\(failure.reason)"
        if failure.willRetry {
            text += "\n\nDashPad will reload your dashboard in \(Int(WebViewController.retryInterval)) seconds."
        }
        return text
    }
}

// MARK: - UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let settings: AppSettings
    let webController: WebViewController

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

        webController.webView = webView

        loadHome(in: webView)
        return webView
    }

    // Intentionally empty: the WebView is long-lived and manages its own state.
    // Settings changes (CSS, JS, URL) are applied on the next explicit page load, not here.
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(settings: settings, webController: webController) }

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
        // WKUserScript can only inject JavaScript, so CSS is wrapped in a JS snippet that
        // creates a <style> element and appends it to <head>. The CSS must be escaped first.
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
        webController.goHome(url: settings.homeURL)
    }
}

// MARK: - Coordinator

extension WebViewRepresentable {
    class Coordinator: NSObject, WKNavigationDelegate {
        let settings: AppSettings
        let webController: WebViewController
        private var retryTimer: Timer?

        init(settings: AppSettings, webController: WebViewController) {
            self.settings = settings
            self.webController = webController
        }

        /// WebKitErrorDomain codes (WebKitErrors.h) that mean a load was abandoned, not that it failed.
        private static let ignoredWebKitErrors: Set<Int> = [
            101, // CannotShowURL: a link to a scheme the WebView can't open (tel:, mailto:, app links)
            102, // FrameLoadInterruptedByPolicyChange: cancelled by decidePolicyFor (domain allowlist)
            204, // PlugInWillHandleLoad: media handed off to the system player
        ]

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
            if !allowed, navigationAction.targetFrame?.isMainFrame == true,
               host == URL(string: settings.homeURL)?.host {
                // Blocking the dashboard itself would leave a blank screen, and retrying can't fix it.
                cancelRetry()
                webController.loadFailure = LoadFailure(
                    url: Self.displayString(for: url),
                    reason: "This domain isn't in Settings → Allowed Domains.",
                    willRetry: false
                )
            }
            return allowed ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // A pending retry would otherwise yank the user back to the home URL after a successful load.
            cancelRetry()
            webController.loadFailure = nil
            webController.canGoBack = webView.canGoBack
            webController.currentURL = webView.url
            webController.applyZoom()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleFailure(error, navigation: navigation, provisional: true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(error, navigation: navigation, provisional: false)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS kills the web content process under memory pressure. No failure callback fires
            // and the view goes blank, so start over from the dashboard.
            webController.goHome(url: settings.homeURL)
        }

        private func handleFailure(_ error: Error, navigation: WKNavigation?, provisional: Bool) {
            let nsError = error as NSError
            // Superseded by a newer navigation: not a failure.
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && Self.ignoredWebKitErrors.contains(nsError.code) { return }

            // A link that fails before committing leaves the current page loaded and usable;
            // covering it with the error and then navigating home would take away a working dashboard.
            if provisional, navigation !== webController.homeNavigation, webController.currentURL != nil { return }

            let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? URL(string: settings.homeURL)
            webController.loadFailure = LoadFailure(
                url: failingURL.map(Self.displayString) ?? "",
                reason: nsError.localizedDescription,
                willRetry: true
            )
            scheduleRetry()
        }

        private func scheduleRetry() {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(
                withTimeInterval: WebViewController.retryInterval,
                repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                self.webController.goHome(url: self.settings.homeURL)
            }
        }

        private func cancelRetry() {
            retryTimer?.invalidate()
            retryTimer = nil
        }

        /// The URL without credentials, query or fragment: the error screen is readable by anyone in the room.
        private static func displayString(for url: URL) -> String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.host ?? ""
            }
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            return components.string ?? url.host ?? ""
        }
    }
}

#Preview {
    KioskBrowserView()
        .environmentObject(AppSettings())
        .environmentObject(KioskManager())
}
