import SwiftUI

struct ContentView: View {
    @StateObject private var model = ScanModel()
    // Owned here rather than by CameraScreen so the configured capture session
    // survives trips to the results screen.
    @StateObject private var camera = CameraController()

    var body: some View {
        switch model.phase {
        case .camera:
            CameraScreen(camera: camera) { model.handleRecording($0) }
        case .analyzing:
            AnalyzingView()
        case .result(let result):
            ResultView(result: result) { model.reset() }
        case .failed(let message):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { model.reset() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
