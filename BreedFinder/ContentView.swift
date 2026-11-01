import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ScanTab()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            BreedsView()
                .tabItem { Label("Breeds", systemImage: "pawprint.fill") }
            SupportView()
                .tabItem { Label("Support", systemImage: "questionmark.circle") }
        }
    }
}

/// Home → (camera) → scanning → result. The camera covers the whole screen, tab bar
/// included; the other screens live inside the tab.
private struct ScanTab: View {
    @EnvironmentObject private var model: ScanModel
    // Owned here so the configured capture session survives between scans.
    @StateObject private var camera = CameraController()

    private var showingCamera: Binding<Bool> {
        Binding(
            get: { model.isShowingCamera },
            set: { isShowing in
                if !isShowing, model.isShowingCamera { model.goHome() }
            }
        )
    }

    var body: some View {
        ZStack {
            switch model.phase {
            case .home, .camera:
                HomeView(onScan: { model.startScan() }, onPhotos: { model.scanPhotos($0) })
                    .transition(.opacity)
            case .scanning(let frames, let source):
                ScanningView(frames: frames, source: source)
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
                        .bold()  // white on orange is 3.6:1 in dark mode, enough only for bold text
                    Button("Home") { model.goHome() }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase.screen)
        .fullScreenCover(isPresented: showingCamera) {
            CameraScreen(camera: camera,
                         onClose: { model.goHome() },
                         onRecorded: { model.handleRecording($0) })
        }
    }
}
