import SwiftUI
import WebKit

struct IdleView: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch settings.idleScreenType {
            case .blank:
                Color.black

            case .clock:
                ClockView()

            case .customURL:
                if let url = URL(string: settings.idleCustomURL), !settings.idleCustomURL.isEmpty {
                    IdleWebView(url: url)
                } else {
                    ClockView()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Idle web view (for Custom URL mode)

private struct IdleWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
    IdleView()
        .environment(AppSettings())
}
