import AVFoundation
import Combine

/// Owns the capture session and records fixed-length clips from the back camera.
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

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "BreedFinder.camera")
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
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Records a `clipDuration`-second clip and calls `completion` on the main
    /// thread with the file URL. The caller is responsible for deleting the file.
    func recordClip(completion: @escaping (Result<URL, Error>) -> Void) {
        sessionQueue.async { [self] in
            guard session.isRunning, !movieOutput.isRecording else { return }
            onFinish = completion
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [self] in
            if !isConfigured {
                guard configureSession() else {
                    setStatus(.unavailable)
                    return
                }
                isConfigured = true
            }
            if !session.isRunning { session.startRunning() }
            setStatus(.ready)
        }
    }

    private func configureSession() -> Bool {
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera)
        else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        // Video only: no audio input means no microphone permission prompt.
        guard session.canAddInput(input), session.canAddOutput(movieOutput) else { return false }
        session.addInput(input)
        session.addOutput(movieOutput)

        // AVFoundation stops the recording itself when the clip is long enough.
        movieOutput.maxRecordedDuration = CMTime(seconds: Self.clipDuration, preferredTimescale: 600)

        // The app is portrait-only, so record portrait video.
        if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return true
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
            let completion = onFinish
            onFinish = nil
            DispatchQueue.main.async { [self] in
                isRecording = false
                completion?(result)
            }
        }
    }
}
