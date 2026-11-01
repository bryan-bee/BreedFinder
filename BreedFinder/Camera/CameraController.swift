import AVFoundation
import Combine

/// Owns the capture session, zooms, lights the dog, and records fixed-length clips from
/// the back camera.
///
/// All AVCaptureSession work happens on `sessionQueue`: starting a session blocks
/// for a noticeable moment, and Apple asks that it never run on the main thread.
/// Published properties are only changed on the main thread.
final class CameraController: NSObject, ObservableObject {
    enum Status {
        case unknown, ready, denied, unavailable
    }

    static let clipDuration: TimeInterval = 5

    @Published private(set) var status: Status = .unknown
    @Published private(set) var isRecording = false
    /// The zoom in the Camera app's numbers, where 1× is the main lens and 0.5× the ultra-wide.
    @Published private(set) var zoom: CGFloat = 1
    /// How far this phone's camera zooms, and its zoom buttons. Nil until the camera is set up.
    @Published private(set) var zoomScale: ZoomScale?
    /// Whether the back camera has a flashlight to light the dog while recording.
    @Published private(set) var hasFlash = false

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "BreedFinder.camera")
    private var camera: AVCaptureDevice?
    private var isConfigured = false
    private var onFinish: ((Result<URL, Error>) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndRun()
                } else {
                    self?.setStatus(.denied)
                }
            }
        default:
            setStatus(.denied)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            setTorch(on: false)
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Records a `clipDuration`-second clip and calls `completion` on the main
    /// thread with the file URL. The caller is responsible for deleting the file.
    /// With `flash`, the flashlight lights the dog for the recording, like the Camera
    /// app's video flash.
    func recordClip(withFlash flash: Bool = false, completion: @escaping (Result<URL, Error>) -> Void) {
        sessionQueue.async { [self] in
            guard session.isRunning, !movieOutput.isRecording else { return }
            onFinish = completion
            if flash { setTorch(on: true) }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Zooms to `zoom` (in the Camera app's numbers), within what this phone allows. The
    /// zoom buttons glide there (`animated`); pinching follows the fingers directly.
    /// Call on the main thread.
    func setZoom(_ zoom: CGFloat, animated: Bool = false) {
        guard let zoomScale else { return }
        let zoom = min(max(zoom, zoomScale.minZoom), zoomScale.maxZoom)
        self.zoom = zoom
        let factor = zoomScale.deviceFactor(for: zoom)
        sessionQueue.async { [self] in setDeviceZoomFactor(factor, animated: animated) }
    }

    private func configureAndRun() {
        sessionQueue.async { [self] in
            if !isConfigured {
                guard configureSession() else {
                    setStatus(.unavailable)
                    return
                }
                isConfigured = true
                setUpZoom()
            }
            if !session.isRunning { session.startRunning() }
            setStatus(.ready)
        }
    }

    private func configureSession() -> Bool {
        guard
            let camera = Self.backCamera(),
            let input = try? AVCaptureDeviceInput(device: camera)
        else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        // Video only: no audio input means no microphone permission prompt.
        guard session.canAddInput(input), session.canAddOutput(movieOutput) else { return false }
        session.addInput(input)
        session.addOutput(movieOutput)
        self.camera = camera

        // AVFoundation stops the recording itself when the clip is long enough.
        movieOutput.maxRecordedDuration = CMTime(seconds: Self.clipDuration, preferredTimescale: 600)

        // The app is portrait-only, so record portrait video.
        if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return true
    }

    /// The back camera. On phones with more than one back lens this is the combined camera,
    /// which switches to the telephoto lens by itself when zoomed in, like the Camera app.
    static func backCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        return types.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
    }

    /// Opens the camera at 1× (on phones with an ultra-wide lens, the combined camera would
    /// otherwise start on it) and publishes how far it zooms and whether it has a flash.
    /// Runs once, before the session first starts: after that the zoom stays wherever the
    /// user left it, scan after scan. Call on `sessionQueue`.
    private func setUpZoom() {
        guard let camera else { return }
        let zoomScale = ZoomScale(camera: camera)
        let hasFlash = camera.hasTorch
        do { try camera.lockForConfiguration() } catch { return }
        // Change lenses only when the user zooms, not by itself when the dog comes close or
        // the light drops, so the picture doesn't jump in the middle of a recording.
        if camera.primaryConstituentDeviceSwitchingBehavior != .unsupported {
            camera.setPrimaryConstituentDeviceSwitchingBehavior(
                .restricted, restrictedSwitchingBehaviorConditions: .videoZoomChanged
            )
        }
        camera.unlockForConfiguration()
        setDeviceZoomFactor(zoomScale.deviceFactor(for: 1), animated: false)

        DispatchQueue.main.async { [self] in
            self.zoomScale = zoomScale
            self.hasFlash = hasFlash
            zoom = 1
        }
    }

    /// Call on `sessionQueue`.
    private func setDeviceZoomFactor(_ factor: CGFloat, animated: Bool) {
        guard let camera else { return }
        do { try camera.lockForConfiguration() } catch { return }
        defer { camera.unlockForConfiguration() }
        // A zoom factor outside the allowed range raises an exception, so clamp it first.
        let factor = min(max(factor, camera.minAvailableVideoZoomFactor), camera.maxAvailableVideoZoomFactor)
        if animated {
            camera.ramp(toVideoZoomFactor: factor, withRate: 6)
        } else {
            camera.videoZoomFactor = factor
        }
    }

    /// Call on `sessionQueue`.
    private func setTorch(on: Bool) {
        guard let camera, camera.hasTorch, camera.isTorchModeSupported(on ? .on : .off) else { return }
        do { try camera.lockForConfiguration() } catch { return }
        camera.torchMode = on ? .on : .off
        camera.unlockForConfiguration()
    }

    private func setStatus(_ status: Status) {
        DispatchQueue.main.async { self.status = status }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async { self.isRecording = true }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Hitting maxRecordedDuration is reported as an error even though the file is
        // complete; AVFoundation flags that case with RecordingSuccessfullyFinished.
        let result: Result<URL, Error>
        if let error, ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) != true {
            try? FileManager.default.removeItem(at: outputFileURL)
            result = .failure(error)
        } else {
            result = .success(outputFileURL)
        }

        sessionQueue.async { [self] in
            setTorch(on: false)
            let completion = onFinish
            onFinish = nil
            DispatchQueue.main.async { [self] in
                isRecording = false
                completion?(result)
            }
        }
    }
}
