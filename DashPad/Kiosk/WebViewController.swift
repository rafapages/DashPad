// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

import Combine
import WebKit

/// Why the dashboard couldn't be shown. Cleared as soon as a navigation finishes.
struct LoadFailure: Equatable {
    /// Already stripped of credentials and query: it is shown on a wall-mounted screen.
    let url: String
    let reason: String
    /// False when retrying can't help, e.g. the allowlist blocks the dashboard itself.
    let willRetry: Bool
}

extension LoadFailure {
    /// WebKitErrorDomain codes (WebKitErrors.h) that mean a load was abandoned, not that it failed.
    private static let ignoredWebKitErrors: Set<Int> = [
        101, // CannotShowURL: a link to a scheme the WebView can't open (tel:, mailto:, app links)
        102, // FrameLoadInterruptedByPolicyChange: cancelled by decidePolicyFor (domain allowlist)
        204, // PlugInWillHandleLoad: media handed off to the system player
    ]

    /// True when the error means the load was superseded or handed off, so nothing needs showing.
    static func isAbandonedLoad(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        return nsError.domain == "WebKitErrorDomain" && ignoredWebKitErrors.contains(nsError.code)
    }

    /// The URL without credentials, query or fragment: the error screen is readable by anyone in the room.
    static func displayString(for url: URL) -> String {
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

class WebViewController: ObservableObject {
    /// Delay before a failed dashboard load is retried.
    static let retryInterval: TimeInterval = 10
    /// How long the dashboard request may go unanswered before it fails. WebKit's default is 60
    /// seconds, which is a minute of nothing on screen when the host never replies.
    static let loadTimeout: TimeInterval = 20

    // Not @Published: the web view reference is plumbing, never rendered.
    weak var webView: WKWebView?
    // Not @Published: identifies the in-flight home load so failures can tell it apart from links.
    var homeNavigation: WKNavigation?
    @Published var canGoBack: Bool = false
    @Published var currentURL: URL? = nil
    @Published var loadFailure: LoadFailure? = nil
    /// True from `goHome` until that load finishes or fails. Until a page arrives WebKit draws
    /// plain white, which on its own looks like a broken app, so the view covers it.
    @Published var isLoadingHome = false

    func reload() { webView?.reload() }

    func goHome(url: String) {
        guard let wv = webView, let u = URL(string: url) else { return }
        isLoadingHome = true
        homeNavigation = wv.load(URLRequest(url: u, timeoutInterval: Self.loadTimeout))
    }

    func goBack() { webView?.goBack() }

    /// Loads a page other than the dashboard, for the Home Assistant link's `show_url` action.
    /// It goes through the same navigation policy as a tapped link, allowlist included.
    func show(_ url: URL) {
        webView?.load(URLRequest(url: url, timeoutInterval: Self.loadTimeout))
    }

    /// `percent` comes from `AppSettings.dashboardZoom`, the only place zoom is kept.
    func applyZoom(percent: Int) {
        guard let wv = webView, wv.bounds.width > 0 else { return }
        // Change the layout viewport width rather than scaling rendered pixels.
        // WebKit auto-scales the wider/narrower layout to fit the physical frame,
        // so fixed/sticky elements stay anchored and no empty space appears.
        let viewportWidth = Int(wv.bounds.width * 100 / CGFloat(percent))
        wv.evaluateJavaScript("""
            (function(){
                var m = document.querySelector('meta[name="viewport"]');
                if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
                m.content = 'width=\(viewportWidth), viewport-fit=cover';
            })();
        """, completionHandler: nil)
    }
}
