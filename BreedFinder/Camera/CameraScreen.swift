import SwiftUI

struct CameraScreen: View {
    @ObservedObject var camera: CameraController
    let onClose: () -> Void
    let onRecorded: (Result<URL, Error>) -> Void

    /// The zoom when the current pinch began; the pinch scales from there.
    @State private var zoomAtPinchStart: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .unknown, .ready:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .gesture(pinchToZoom)
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

            VStack {
                HStack {
                    // Disabled mid-recording so a finished clip can't arrive after leaving.
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(camera.isRecording)
                    .opacity(camera.isRecording ? 0.4 : 1)
                    .accessibilityLabel("Close camera")
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
                .padding(.top, 60)

            Spacer()

            if let zoomScale = camera.zoomScale, zoomScale.presets.count > 1 {
                ZoomButtons(zoom: camera.zoom, presets: zoomScale.presets) { camera.setZoom($0, animated: true) }
                    .padding(.bottom, 20)
            }

            RecordButton(isRecording: camera.isRecording, duration: CameraController.clipDuration) {
                camera.recordClip(completion: onRecorded)
            }
            .disabled(camera.status != .ready || camera.isRecording)
            .padding(.bottom, 24)
        }
    }

    private var pinchToZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAtPinchStart ?? camera.zoom
                zoomAtPinchStart = start
                camera.setZoom(start * value.magnification)
            }
            .onEnded { _ in zoomAtPinchStart = nil }
    }
}

/// Zoom buttons like the Camera app's. The button for the current zoom range shows the
/// exact zoom, such as "2.4×" mid-pinch; the others show the zoom they jump to.
private struct ZoomButtons: View {
    let zoom: CGFloat
    let presets: [CGFloat]
    let onSelect: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.self) { preset in
                let isCurrent = preset == currentPreset
                Button { onSelect(preset) } label: {
                    Text(isCurrent ? ZoomScale.label(for: zoom) + "×" : ZoomScale.label(for: preset))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.accentColor : .white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ZoomScale.label(for: preset)) times zoom")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// The highest button at or below the current zoom.
    private var currentPreset: CGFloat? {
        presets.last { $0 <= zoom + 0.05 }
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
