// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// IdleView.swift - shown whenever KioskManager.displayState is .idle.
// Switches between the idle screen modes (clock, photos, blank, custom URL), or shows the
// night screen while KioskManager.isNightActive.

import SwiftUI
import WebKit

struct IdleView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var kioskManager: KioskManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if kioskManager.isNightActive {
                nightScreen.transition(.opacity)
            } else {
                idleScreen.transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var nightScreen: some View {
        switch settings.nightScreenType {
        case .blank: Color.black
        case .clock: ClockView(isNight: true)
        }
    }

    @ViewBuilder
    private var idleScreen: some View {
        ZStack {
            switch settings.idleScreenType {
            case .blank:
                Color.black

            case .clock:
                ClockView()

            case .photos:
                // With no photos yet, show the clock rather than a black screen.
                if settings.idlePhotos.isEmpty {
                    ClockView()
                } else {
                    PhotoSlideshowView(photos: settings.idlePhotos, options: settings.photoOptions)
                }

            case .customURL:
                if let url = settings.idleWebURL {
                    IdleWebPage(url: url)
                } else {
                    ClockView()
                }
            }
        }
    }
}

// MARK: - Idle web page (for Custom URL mode)

/// A display-only page: it never takes touches, so any tap reaches ContentView and wakes the
/// dashboard, and nobody can browse away from the idle URL. It is created fresh each time the
/// screen goes idle, so the page always starts from the configured URL.
private struct IdleWebPage: View {
    let url: URL
    @State private var failure: LoadFailure?

    var body: some View {
        ZStack {
            IdleWebView(url: url, failure: $failure)
            if let failure {
                EmptyStatePlaceholder(
                    title: "Can't load idle screen",
                    systemImage: "wifi.exclamationmark",
                    description: "\(failure.url)\n\n\(failure.reason)\n\n"
                        + "DashPad will try again in \(Int(WebViewController.retryInterval)) seconds."
                )
                .background(Color.black.ignoresSafeArea())
                .environment(\.colorScheme, .dark)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct IdleWebView: UIViewRepresentable {
    let url: URL
    @Binding var failure: LoadFailure?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Slideshows and camera feeds have to start on their own: nobody taps an idle screen to play.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        // Not opaque, so the black behind it shows until the page paints instead of a white flash.
        webView.isOpaque = false
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.failure = $failure
        if context.coordinator.url != url {
            context.coordinator.load(url, in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelRetry()
    }

    func makeCoordinator() -> Coordinator { Coordinator(failure: $failure) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var failure: Binding<LoadFailure?>
        private(set) var url: URL?
        private var retryTimer: Timer?

        init(failure: Binding<LoadFailure?>) {
            self.failure = failure
        }

        func load(_ url: URL, in webView: WKWebView) {
            cancelRetry()
            self.url = url
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            cancelRetry()
            failure.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            handleFailure(error, in: webView)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            handleFailure(error, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The idle page can stay up all night; if iOS reclaims its process, start it again.
            guard let url else { return }
            load(url, in: webView)
        }

        func cancelRetry() {
            retryTimer?.invalidate()
            retryTimer = nil
        }

        private func handleFailure(_ error: Error, in webView: WKWebView) {
            guard !LoadFailure.isAbandonedLoad(error), let url else { return }
            let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url
            failure.wrappedValue = LoadFailure(
                url: LoadFailure.displayString(for: failingURL),
                reason: error.localizedDescription,
                willRetry: true
            )
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(
                withTimeInterval: WebViewController.retryInterval,
                repeats: false
            ) { [weak self, weak webView] _ in
                guard let self, let webView, let url = self.url else { return }
                self.load(url, in: webView)
            }
        }
    }
}

#Preview {
    IdleView()
        .environmentObject(AppSettings())
        .environmentObject(KioskManager())
}
