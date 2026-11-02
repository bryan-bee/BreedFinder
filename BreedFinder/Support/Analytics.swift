import Foundation
import TelemetryDeck

/// Anonymous usage stats, through TelemetryDeck (telemetrydeck.com): how many scans find a
/// dog, how long the on-device analysis takes, and how often users say the top guess was
/// right. That last one is Breed Finder's accuracy on real dogs, which the test set of
/// curated photos can't measure.
///
/// No photos, and nothing that identifies the user: TelemetryDeck counts users by the ID iOS
/// gives this app on the phone (identifierForVendor), SHA-256 hashed on the iPhone and again
/// on its servers, and it doesn't store IP addresses. Turning stats off in the Support tab
/// stops the SDK, and it isn't started at launch while they're off. Signals from Debug builds
/// are marked as test data (turn on Test Mode in the dashboard to see them), so running the
/// app from Xcode doesn't mix with real users' numbers.
enum Analytics {
    /// The app's ID from the TelemetryDeck dashboard. While it's empty, the SDK is never
    /// started and nothing is sent.
    static let appID = "7A653FA2-EAE2-451C-95B8-F258B704650E"

    /// UserDefaults key for the Support tab's "Share anonymous usage stats" switch (on by default).
    static let sharingKey = "shareUsageStats"

    static var isConfigured: Bool { !appID.isEmpty }

    /// TelemetryDeck has to be initialized before anything is sent through it.
    @MainActor private static var isRunning = false

    /// Starts the SDK at launch, unless the user turned stats off.
    @MainActor static func start() {
        setSharing(UserDefaults.standard.object(forKey: sharingKey) as? Bool ?? true)
    }

    /// Starts or stops the SDK, for the switch in the Support tab.
    @MainActor static func setSharing(_ sharing: Bool) {
        guard isConfigured, sharing != isRunning else { return }
        if sharing {
            TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        } else {
            TelemetryDeck.terminate()
        }
        isRunning = sharing
    }

    @MainActor static func send(_ event: AnalyticsEvent) {
        guard isRunning else { return }
        TelemetryDeck.signal(event.name, parameters: event.parameters, floatValue: event.floatValue)
    }
}

/// One usage-stats signal: a name and text parameters, which is what TelemetryDeck takes,
/// plus an optional number it can average (a duration or a confidence). Kept apart from the
/// SDK so the tests can check exactly what is sent.
struct AnalyticsEvent: Equatable {
    let name: String
    var parameters: [String: String] = [:]
    var floatValue: Double?
}

extension AnalyticsEvent {
    /// A scan finished: "Scan.completed" with the top guess, or "Scan.noDogFound".
    /// The value is how long the on-device analysis took, in milliseconds.
    static func scanFinished(_ result: ScanResult, analysisTime: Duration, collectedBreeds: Int) -> AnalyticsEvent {
        var parameters = [
            "source": result.source.rawValue,
            "frames": String(result.frames.count),
            "dogFrames": String(result.frames.filter(\.prediction.containsDog).count),
            "modelVersion": result.modelVersion,
        ]
        guard let top = result.guesses.first else {
            return AnalyticsEvent(name: "Scan.noDogFound", parameters: parameters,
                                  floatValue: analysisTime.inMilliseconds)
        }
        parameters["topBreed"] = top.breed
        parameters["confidence"] = confidenceBin(top.confidence)
        parameters["collectedBreeds"] = String(collectedBreeds)
        return AnalyticsEvent(name: "Scan.completed", parameters: parameters,
                              floatValue: analysisTime.inMilliseconds)
    }

    /// A scan couldn't finish. `step` is where: "recording", "frames", "photos" or "analysis".
    static func scanFailed(step: String, error: Error? = nil) -> AnalyticsEvent {
        var parameters = ["step": step]
        if let error {
            let nsError = error as NSError
            parameters["error"] = "\(nsError.domain) \(nsError.code)"
        }
        return AnalyticsEvent(name: "Scan.failed", parameters: parameters)
    }

    /// The user's final answer to "Is it a …?" for one scan. The value is the top guess's
    /// confidence (0–1), so accuracy can be compared with how sure the app was.
    static func feedback(_ feedback: ScanFeedback, on result: ScanResult) -> AnalyticsEvent {
        let top = result.guesses.first
        var parameters = [
            "answer": feedback.statsAnswer,
            "source": result.source.rawValue,
            "modelVersion": result.modelVersion,
        ]
        parameters["topBreed"] = top?.breed
        parameters["confidence"] = top.map { confidenceBin($0.confidence) }
        switch feedback {
        case .correct: parameters["actualBreed"] = top?.breed
        case .otherBreed(let breed, _): parameters["actualBreed"] = breed
        case .notTopGuess, .unsure: break
        }
        return AnalyticsEvent(name: "Scan.feedback", parameters: parameters, floatValue: top?.confidence)
    }

    /// The record button was tapped: at which zoom, and whether the flash was on.
    static func recordingStarted(zoom: CGFloat, flash: Bool) -> AnalyticsEvent {
        let zoomRange = zoom < 0.95 ? "ultra-wide" : zoom <= 1.05 ? "1x" : "zoomed in"
        return AnalyticsEvent(name: "Camera.recordingStarted",
                              parameters: ["zoom": zoomRange, "flash": flash ? "on" : "off"])
    }

    /// A problem report was sent, or handed to another app. Only its kind and whether photos
    /// were attached, never what it says.
    static func reportSent(_ report: ProblemReport, via channel: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "Report.sent", parameters: [
            "kind": report.kind.rawValue,
            "photosAttached": report.photosAttached ? "yes" : "no",
            "trainingUseAllowed": report.allowsTrainingUse ? "yes" : "no",
            "via": channel,
        ])
    }

    /// "70-80%": the confidence rounded down to a 10-point range, so answers can be grouped
    /// by how sure the app was. That checks the confidence calibration on real scans.
    static func confidenceBin(_ confidence: Double) -> String {
        guard confidence.isFinite else { return "unknown" }
        let lower = min(max(Int(confidence * 10), 0), 9) * 10
        return "\(lower)-\(lower + 10)%"
    }
}

private extension Duration {
    var inMilliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
