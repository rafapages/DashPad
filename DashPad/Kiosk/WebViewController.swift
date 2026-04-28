import WebKit

@Observable
class WebViewController {
    weak var webView: WKWebView?
    var zoomLevel: Double = 1.0
    var canGoBack: Bool = false
    var currentURL: URL? = nil

    func reload() { webView?.reload() }

    func goHome(url: String) {
        guard let wv = webView, let u = URL(string: url) else { return }
        wv.load(URLRequest(url: u))
    }

    func goBack() { webView?.goBack() }

    func setZoom(_ level: Double) {
        zoomLevel = min(max(level, 0.5), 2.0)
        applyZoom()
    }

    func applyZoom() {
        guard let wv = webView, wv.bounds.width > 0 else { return }
        // Change the layout viewport width rather than scaling rendered pixels.
        // WebKit auto-scales the wider/narrower layout to fit the physical frame,
        // so fixed/sticky elements stay anchored and no empty space appears.
        let viewportWidth = Int(wv.bounds.width / zoomLevel)
        wv.evaluateJavaScript("""
            (function(){
                var m = document.querySelector('meta[name="viewport"]');
                if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
                m.content = 'width=\(viewportWidth), viewport-fit=cover';
            })();
        """, completionHandler: nil)
    }
}
