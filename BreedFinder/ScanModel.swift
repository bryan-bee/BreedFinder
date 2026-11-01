import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI

/// The Scan tab's state: home → camera → scanning → result (or an error), and around
/// again. Each result with a dog in it is saved to the user's BreedCollection.
@MainActor
final class ScanModel: ObservableObject {
    enum Phase {
        case home
        case camera
        case scanning([CGImage], ScanSource)
        case result(ScanResult)
        case failed(String)

        /// Identifies the screen, for animating between them.
        var screen: String {
            switch self {
            case .home: return "home"
            case .camera: return "camera"
            case .scanning: return "scanning"
            case .result: return "result"
            case .failed: return "failed"
            }
        }
    }

    /// The model usually finishes in well under a second. Keep the scanning screen up
    /// a little longer so people can see which frames were used.
    static let minimumScanTime: Duration = .seconds(2.5)

    @Published private(set) var phase: Phase = .home
    /// The collection record for the result on screen; nil if it wasn't saved
    /// (no dog found) or the user chose not to count it.
    @Published private(set) var currentRecordID: UUID?
    /// The result on screen in RecentScansStore, for "Report a problem with this scan".
    @Published private(set) var currentScanID: UUID?
    /// The user's answer to "Is it a …?" for the result on screen.
    @Published private(set) var feedback: ScanFeedback?
    /// Which breed model is bundled, for problem reports.
    @Published private(set) var modelVersion = "loading…"

    private let analyzer = DogAnalyzer()
    private let collection: BreedCollection
    private let recentScans: RecentScansStore
    /// Whether the answer for the result on screen has gone into the usage stats.
    private var feedbackSent = false

    init(collection: BreedCollection, recentScans: RecentScansStore) {
        self.collection = collection
        self.recentScans = recentScans
        // Load the Core ML model now so the first scan doesn't wait on it.
        Task { [weak self, analyzer] in
            let version = await analyzer.warmUp()
            self?.modelVersion = version
        }
    }

    var isShowingCamera: Bool {
        if case .camera = phase { return true }
        return false
    }

    func startScan() {
        sendFeedback()
        phase = .camera
    }

    func goHome() {
        sendFeedback()
        phase = .home
    }

    func handleRecording(_ recording: Result<URL, Error>) {
        switch recording {
        case .success(let url):
            Task {
                // The clip is only needed long enough to pull frames out of it.
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let frames = try await FrameExtractor.frames(from: url, count: DogAnalyzer.framesPerClip)
                    await scan(frames, source: .video)
                } catch {
                    phase = .failed(error.localizedDescription)
                    Analytics.send(.scanFailed(step: "frames", error: error))
                }
            }
        case .failure(let error):
            phase = .failed(error.localizedDescription)
            Analytics.send(.scanFailed(step: "recording", error: error))
        }
    }

    func scanPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            let images = await PhotoLoader.images(from: items)
            if images.isEmpty {
                phase = .failed("Those photos couldn't be opened. Try different ones.")
                Analytics.send(.scanFailed(step: "photos"))
            } else {
                await scan(images, source: .photos)
            }
        }
    }

    // MARK: Feedback and the collection

    /// Records the user's answer to "Is it a …?", or a breed they picked from the list.
    /// "Yes" or a named breed counts the scan as that breed: it undoes an earlier
    /// correction, or saves the scan again if the user had taken it out.
    func answer(_ answer: ScanFeedback) {
        guard case .result(let result) = phase, let top = result.guesses.first else { return }
        feedback = answer
        switch answer {
        case .correct: countScan(result, as: top.breed)
        case .otherBreed(let breed, _): countScan(result, as: breed)
        case .notTopGuess, .unsure: break
        }
    }

    /// Takes the current scan back out of the collection.
    func uncountCurrentScan() {
        guard let id = currentRecordID else { return }
        collection.remove(id)
        currentRecordID = nil
    }

    /// Sends the answer for the result on screen to the usage stats, once. Called when the
    /// user leaves the result, or when the app goes to the background (where iOS may close
    /// it), so an answer the user changes is counted once, as they left it.
    func sendFeedback() {
        guard case .result(let result) = phase, let feedback, !feedbackSent else { return }
        feedbackSent = true
        Analytics.send(.feedback(feedback, on: result))
    }

    private func countScan(_ result: ScanResult, as breed: String) {
        if let id = currentRecordID {
            if collection.record(id: id)?.breed != breed {
                collection.correct(id, to: breed)
            }
        } else {
            let id = collection.add(breed: breed,
                                    predictedBreed: result.guesses.first?.breed ?? breed,
                                    confidence: result.guesses.first?.confidence ?? 0,
                                    photo: result.dogPhoto)
            currentRecordID = id
            if let scanID = currentScanID {
                recentScans.link(scanID: scanID, recordID: id)
            }
        }
    }

    // MARK: Scanning

    private func scan(_ images: [CGImage], source: ScanSource) async {
        phase = .scanning(images, source)
        currentRecordID = nil
        currentScanID = nil
        feedback = nil
        feedbackSent = false
        let started = ContinuousClock.now
        do {
            let result = try await analyzer.analyze(frames: images, source: source)
            // Finding the dog and classifying every frame, on the device.
            let analysisTime = ContinuousClock.now - started

            var recordID: UUID?
            if let top = result.guesses.first {
                recordID = collection.add(breed: top.breed, predictedBreed: top.breed,
                                          confidence: top.confidence, photo: result.dogPhoto)
            }
            // Keep the frames for problem reports (also for "no dog found" results);
            // saving overlaps with the minimum time on the scanning screen.
            let scanID = UUID()
            let saving = Task { await recentScans.add(id: scanID, result: result, recordID: recordID) }

            let remaining = Self.minimumScanTime - (ContinuousClock.now - started)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            await saving.value

            currentRecordID = recordID
            currentScanID = scanID
            phase = .result(result)
            Analytics.send(.scanFinished(result, analysisTime: analysisTime,
                                         collectedBreeds: collection.collectedBreeds.count))
        } catch {
            phase = .failed(error.localizedDescription)
            Analytics.send(.scanFailed(step: "analysis", error: error))
        }
    }
}
