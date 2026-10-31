import SwiftUI

struct ContentView: View {
    @StateObject private var model = ScanModel()
    // Owned here rather than by CameraScreen so the configured capture session
    // survives trips to the other screens.
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack {
            switch model.phase {
            case .home:
                HomeView { model.startScan() }
                    .transition(.opacity)
            case .camera:
                CameraScreen(camera: camera,
                             onClose: { model.goHome() },
                             onRecorded: { model.handleRecording($0) })
                    .transition(.opacity)
            case .scanning(let frames):
                ScanningView(frames: frames)
                    .transition(.opacity)
            case .result(let result):
                ResultView(result: result,
                           onScanAgain: { model.startScan() },
                           onHome: { model.goHome() })
                    .transition(.opacity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { model.startScan() }
                        .buttonStyle(.borderedProminent)
                    Button("Home") { model.goHome() }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase.screen)
    }
}
