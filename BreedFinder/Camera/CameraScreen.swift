import SwiftUI

struct CameraScreen: View {
    @ObservedObject var camera: CameraController
    let onRecorded: (Result<URL, Error>) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .unknown, .ready:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                controls
            case .denied:
                CameraPermissionView()
            case .unavailable:
                ContentUnavailableView(
                    "No camera available",
                    systemImage: "video.slash",
                    description: Text("Breed Finder needs an iPhone with a back camera.")
                )
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var controls: some View {
        VStack {
            Text(camera.isRecording ? "Keep the dog in frame…" : "Point at a dog and tap record")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 12)

            Spacer()

            RecordButton(isRecording: camera.isRecording, duration: CameraController.clipDuration) {
                camera.recordClip(completion: onRecorded)
            }
            .disabled(camera.status != .ready || camera.isRecording)
            .padding(.bottom, 24)
        }
    }
}

private struct CameraPermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("Breed Finder needs the camera to record your dog. You can turn it on in Settings.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
