import Foundation

enum ProblemKind: String, CaseIterable, Identifiable {
    case wrongBreed = "Wrong breed"
    case crash = "App crashed"
    case bug = "Something didn't work"
    case suggestion = "Suggestion"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .wrongBreed: return "questionmark.square.dashed"
        case .crash: return "exclamationmark.triangle"
        case .bug: return "ladybug"
        case .suggestion: return "lightbulb"
        }
    }

    var detailsPrompt: String {
        switch self {
        case .wrongBreed: return "Anything else we should know? (e.g. it's a mix, or a puppy)"
        case .crash: return "What were you doing when it crashed?"
        case .bug: return "What happened, and what did you expect to happen?"
        case .suggestion: return "What would you like Breed Finder to do?"
        }
    }

    /// Whether a report of this kind needs a written description to be useful.
    var requiresDetails: Bool { self == .bug || self == .suggestion }
}

/// Everything in a problem report, turned into an email subject and body.
struct ProblemReport {
    var kind: ProblemKind
    var details: String
    /// Wrong-breed reports: what the dog really is (a breed or the user's description).
    var actualBreed: String?
    var scan: RecentScan?
    /// What the scan currently counts as in the user's collection, if anything.
    var countedAs: String?
    var appVersion: String
    var modelVersion: String
    var systemVersion: String
    var deviceModel: String

    var subject: String { "Breed Finder: \(kind.rawValue)" }

    var body: String {
        var lines = ["Problem: \(kind.rawValue)"]
        if kind == .wrongBreed {
            lines.append("What it really is: \(actualBreed.flatMap(Self.nonEmpty) ?? "not specified")")
        }
        lines.append("")
        lines.append(Self.nonEmpty(details) ?? "(no description)")

        lines.append("")
        if let scan {
            let withDog = scan.framesWithDog.filter { $0 }.count
            lines.append("— Scan —")
            lines.append("When: \(scan.date.formatted(date: .abbreviated, time: .shortened))")
            lines.append("From: \(scan.source == .video ? "video" : "photos"), \(scan.framesWithDog.count) \(scan.source.itemName)s, dog found in \(withDog)")
            if scan.guesses.isEmpty {
                lines.append("App said: no dog found")
            }
            for (index, guess) in scan.guesses.enumerated() {
                lines.append("App said #\(index + 1): \(guess.breed) \(guess.confidence.formatted(.percent.precision(.fractionLength(0))))")
            }
            lines.append("Counted in collection as: \(countedAs ?? "not counted")")
            lines.append("Breed model: \(scan.modelVersion)")
        } else {
            lines.append("No scan attached")
            lines.append("Breed model: \(modelVersion)")
        }

        lines.append("")
        lines.append("— Device —")
        lines.append("App: \(appVersion)")
        lines.append("iOS: \(systemVersion)")
        lines.append("iPhone: \(deviceModel)")
        return lines.joined(separator: "\n")
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
