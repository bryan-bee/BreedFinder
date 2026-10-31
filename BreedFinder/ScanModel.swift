import Foundation

/// The app's state: camera → analyzing → result (or an error), and back again.
@MainActor
final class ScanModel: ObservableObject {
    enum Phase {
        case camera
        case analyzing
        case result(ScanResult)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .camera

    private let analyzer = DogAnalyzer()

    init() {
        // Load the Core ML model now so the first scan doesn't wait on it.
        Task { [analyzer] in await analyzer.warmUp() }
    }

    func handleRecording(_ recording: Result<URL, Error>) {
        switch recording {
        case .success(let url):
            analyze(videoAt: url)
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        phase = .camera
    }

    private func analyze(videoAt url: URL) {
        phase = .analyzing
        Task {
            // The clip is only needed long enough to pull frames out of it.
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                phase = .result(try await analyzer.analyze(videoAt: url))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
