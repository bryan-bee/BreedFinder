import CoreML
import Vision

/// Turns the frames of a recorded clip into breed guesses:
/// for each frame, find the dog → classify the breed; then combine the frames.
///
/// An actor so the heavy Vision/Core ML work runs off the main thread, one scan at a time.
actor DogAnalyzer {
    /// The classifier's class for "no dog in this photo". Must match NOT_A_DOG in
    /// ml/convert_model.py and ml/data/breeds.py.
    static let notADogLabel = "Not a dog"
    static let framesPerClip = 5

    private var model: VNCoreMLModel?

    /// Loading the Core ML model takes a second or two the first time (Core ML
    /// compiles it for the Neural Engine), so ScanModel calls this at launch.
    func warmUp() {
        _ = try? loadedModel()
    }

    func analyze(frames images: [CGImage]) throws -> ScanResult {
        let model = try loadedModel()
        let frames = try images.map { try analyze($0, model: model) }
        let guesses = BreedAggregator.topGuesses(from: frames.map(\.prediction))

        // For the result card: the frame where the top breed is most visible.
        let bestFrame = guesses.first.flatMap { top in
            frames.filter(\.prediction.containsDog).max {
                ($0.prediction.breedProbabilities[top.breed] ?? 0) < ($1.prediction.breedProbabilities[top.breed] ?? 0)
            }
        }
        return ScanResult(frames: frames, guesses: guesses, dogPhoto: bestFrame.map(Self.cropToDog))
    }

    private func loadedModel() throws -> VNCoreMLModel {
        if let model { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        // DogBreedClassifier is the class Xcode generates from DogBreedClassifier.mlpackage.
        let loaded = try VNCoreMLModel(for: DogBreedClassifier(configuration: configuration).model)
        model = loaded
        return loaded
    }

    private func analyze(_ image: CGImage, model: VNCoreMLModel) throws -> FrameAnalysis {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)

        // 1. Apple's built-in animal detector: is there a dog, and where?
        let detectRequest = VNRecognizeAnimalsRequest()
        try handler.perform([detectRequest])
        let dogBox = Self.largestDogBox(in: detectRequest.results ?? [])

        // 2. The breed classifier, zoomed in on the dog when the detector found one.
        let classifyRequest = VNCoreMLRequest(model: model)
        classifyRequest.imageCropAndScaleOption = .centerCrop
        if let dogBox {
            classifyRequest.regionOfInterest = Self.squareRegion(
                around: dogBox, imageWidth: image.width, imageHeight: image.height
            )
        }
        try handler.perform([classifyRequest])

        var breedProbabilities: [String: Double] = [:]
        let observations = (classifyRequest.results as? [VNClassificationObservation]) ?? []
        for observation in observations where observation.identifier != Self.notADogLabel {
            breedProbabilities[observation.identifier] = Double(observation.confidence)
        }
        let prediction = FramePrediction(dogDetected: dogBox != nil, breedProbabilities: breedProbabilities)
        return FrameAnalysis(image: image, dogBox: dogBox, prediction: prediction)
    }

    /// The biggest dog in the frame, as a normalized Vision rect (origin bottom-left).
    static func largestDogBox(in observations: [VNRecognizedObjectObservation]) -> CGRect? {
        observations
            .filter { observation in
                observation.labels.contains {
                    $0.identifier == VNAnimalIdentifier.dog.rawValue && $0.confidence >= 0.5
                }
            }
            .map(\.boundingBox)
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Expands the dog's bounding box into a padded square (square in pixels, not
    /// in normalized units), so the classifier's center crop sees the whole dog
    /// instead of cutting off its head or tail.
    static func squareRegion(
        around box: CGRect, imageWidth: Int, imageHeight: Int, padding: CGFloat = 1.15
    ) -> CGRect {
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)
        let pixelBox = VNImageRectForNormalizedRect(box, imageWidth, imageHeight)
        let side = min(max(pixelBox.width, pixelBox.height) * padding, min(width, height))

        var square = CGRect(x: pixelBox.midX - side / 2, y: pixelBox.midY - side / 2, width: side, height: side)
        // Slide the square back inside the image rather than shrinking it.
        square.origin.x = min(max(square.origin.x, 0), width - side)
        square.origin.y = min(max(square.origin.y, 0), height - side)

        // Vision rejects regions even a rounding error outside the unit square.
        return VNNormalizedRectForImageRect(square, imageWidth, imageHeight)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The largest centered square, as a normalized rect.
    static func centerSquare(imageWidth: Int, imageHeight: Int) -> CGRect {
        let side = CGFloat(min(imageWidth, imageHeight))
        let width = side / CGFloat(imageWidth)
        let height = side / CGFloat(imageHeight)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// The frame cropped to the square the classifier looked at: around the dog, or
    /// the center of the frame when the detector didn't find one.
    static func cropToDog(_ frame: FrameAnalysis) -> CGImage {
        let width = frame.image.width
        let height = frame.image.height
        let region = frame.dogBox.map { squareRegion(around: $0, imageWidth: width, imageHeight: height) }
            ?? centerSquare(imageWidth: width, imageHeight: height)
        var rect = VNImageRectForNormalizedRect(region, width, height)
        // Vision's normalized rects start at the bottom-left; CGImage's pixels at the top-left.
        rect.origin.y = CGFloat(height) - rect.maxY
        return frame.image.cropping(to: rect.integral) ?? frame.image
    }
}
