import AVFoundation

enum ScanError: LocalizedError {
    case unreadableVideo

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "The recording couldn't be read. Please try again."
        }
    }
}

enum FrameExtractor {
    /// Grabs one frame from the middle of each equal slice of the video. For a
    /// 5-second clip and 5 frames that's 0.5 s, 1.5 s, 2.5 s, 3.5 s and 4.5 s.
    static func frames(from url: URL, count: Int) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ScanError.unreadableVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        // Rotate frames to match how the video was recorded (portrait), not how the
        // camera sensor stores them (landscape).
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        // By default the generator may snap to the nearest keyframe, which can hand
        // back the same image twice. Ask for frames within 1/30 s of each time.
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var images: [CGImage] = []
        for index in 0..<count {
            let seconds = duration * (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            images.append(try await generator.image(at: time).image)
        }
        return images
    }
}
