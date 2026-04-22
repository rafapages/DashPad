import Foundation
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
    var logEntries: [LogEntry] = []
    var verboseFrameEvents: Bool = false

    private let maxEntries = 100

    func frameProcessed(observations: [VNDetectedObjectObservation]) {
        lastSampleDate = Date()
        self.observations = observations

        guard verboseFrameEvents else { return }
        if observations.isEmpty {
            addEvent("📷  Frame — 0 detections")
        } else {
            let conf = String(format: "%.2f", observations[0].confidence)
            let suffix = observations.count > 1 ? " (+\(observations.count - 1))" : ""
            addEvent("📷  Frame — \(observations.count) detection\(observations.count == 1 ? "" : "s"), conf \(conf)\(suffix)")
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
