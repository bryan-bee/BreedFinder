import CoreML
import Vision

/// Turns a recorded clip into breed guesses:
/// video → 5 frames → find the dog in each → classify the breed → combine.
///
/// An actor so the heavy Vision/Core ML work runs off the main thread, one scan at a time.
actor DogAnalyzer {
    /// The classifier's extra class covering every non-dog ImageNet class.
    /// Must match NOT_A_DOG in ml/convert_model.py.
    static let notADogLabel = "Not a dog"
    static let framesPerClip = 5

    private var model: VNCoreMLModel?

    /// Loading the Core ML model takes a second or two the first time (Core ML
    /// compiles it for the Neural Engine), so ScanModel calls this at launch.
    func warmUp() {
        _ = try? loadedModel()
    }

    func analyze(videoAt url: URL) async throws -> ScanResult {
        let images = try await FrameExtractor.frames(from: url, count: Self.framesPerClip)
        let model = try loadedModel()
        let frames = try images.map { image in
            FrameAnalysis(image: image, prediction: try predict(image, model: model))
        }
        return ScanResult(
            frames: frames,
            guesses: BreedAggregator.topGuesses(from: frames.map(\.prediction))
        )
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

    private func predict(_ image: CGImage, model: VNCoreMLModel) throws -> FramePrediction {
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
        return FramePrediction(dogDetected: dogBox != nil, breedProbabilities: breedProbabilities)
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
}
