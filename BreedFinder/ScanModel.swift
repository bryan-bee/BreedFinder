import CoreGraphics
import Foundation

/// The app's state: home → camera → scanning → result (or an error), and around again.
@MainActor
final class ScanModel: ObservableObject {
    enum Phase {
        case home
        case camera
        case scanning([CGImage])
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

    private let analyzer = DogAnalyzer()

    init() {
        // Load the Core ML model now so the first scan doesn't wait on it.
        Task { [analyzer] in await analyzer.warmUp() }
    }

    func startScan() {
        phase = .camera
    }

    func goHome() {
        phase = .home
    }

    func handleRecording(_ recording: Result<URL, Error>) {
        switch recording {
        case .success(let url):
            Task { await scan(videoAt: url) }
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    private func scan(videoAt url: URL) async {
        // The clip is only needed long enough to pull frames out of it.
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let frames = try await FrameExtractor.frames(from: url, count: DogAnalyzer.framesPerClip)
            phase = .scanning(frames)
            let started = ContinuousClock.now
            let result = try await analyzer.analyze(frames: frames)
            let remaining = Self.minimumScanTime - (ContinuousClock.now - started)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            phase = .result(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
