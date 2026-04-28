// PresenceDebugViewModel.swift — observable state for the presence debug overlay in settings.
// KioskManager holds a weak reference to this; when debug mode is turned off the reference
// is cleared to nil, which stops all debug output with no additional coordination needed.

import Foundation
import UIKit
import Vision
import Observation

@Observable
final class PresenceDebugViewModel {

    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    var observations: [VNDetectedObjectObservation] = []
    var lastSampleDate: Date = .distantPast
    var lastLuminance: Double = 0
    var lastPhoto: UIImage?
    var logEntries: [LogEntry] = []
    var verboseFrameEvents: Bool = false

    private let maxEntries = 100

    func frameProcessed(luminance: Double, observations: [VNDetectedObjectObservation], image: UIImage?) {
        lastSampleDate = Date()
        lastLuminance = luminance
        self.observations = observations
        lastPhoto = image

        guard verboseFrameEvents else { return }
        if observations.isEmpty {
            addEvent(String(format: "📷  Frame — 0 detections, lum %.0f", luminance))
        } else {
            let conf = String(format: "%.2f", observations[0].confidence)
            let suffix = observations.count > 1 ? " (+\(observations.count - 1))" : ""
            addEvent(String(format: "📷  Frame — %d detection%@, conf %@, lum %.0f",
                            observations.count,
                            observations.count == 1 ? "" : "s",
                            conf + suffix,
                            luminance))
        }
    }

    func addEvent(_ message: String) {
        logEntries.append(LogEntry(date: Date(), message: message))
        if logEntries.count > maxEntries {
            logEntries.removeFirst()
        }
    }

    func clearLog() {
        logEntries.removeAll()
    }
}
