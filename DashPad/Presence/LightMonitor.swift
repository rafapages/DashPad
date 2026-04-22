import UIKit

/// Monitors screen brightness as a proxy for ambient light level.
/// Uses UIScreen.brightnessDidChangeNotification for efficiency and polls
/// periodically as a fallback.
class LightMonitor {
    /// Called on the main thread whenever brightness changes.
    var onBrightnessChanged: ((CGFloat) -> Void)?

    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?

    func start() {
        // Fire immediately with current brightness
        report()

        // Respond to system brightness changes (triggered by auto-brightness)
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.report(screen: notification.object as? UIScreen)
        }

        // Poll every 60 s as a safety net for devices where the notification is unreliable
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.report()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func report(screen: UIScreen? = nil) {
        let s = screen ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
        guard let brightness = s?.brightness else { return }
        onBrightnessChanged?(brightness)
    }
}
