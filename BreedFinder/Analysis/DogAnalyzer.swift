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
    /// The "source" metadata convert_model.py writes into the Core ML model, e.g.
    /// "convnext_tiny… fine-tuned (epoch 11, temperature 0.73)". Goes into problem reports.
    private(set) var modelVersion = "not loaded"

    /// Loading the Core ML model takes a second or two the first time (Core ML
    /// compiles it for the Neural Engine), so ScanModel calls this at launch.
    @discardableResult
    func warmUp() -> String {
        _ = try? loadedModel()
        return modelVersion
    }

    func analyze(frames images: [CGImage], source: ScanSource) throws -> ScanResult {
        let model = try loadedModel()
        let frames = try images.map { try analyze($0, model: model) }
        let guesses = BreedAggregator.topGuesses(from: frames.map(\.prediction),
                                                 requiredDogFrames: BreedAggregator.requiredDogFrames(for: source))

        // For the result card: the frame where the top breed is most visible.
        let bestFrame = guesses.first.flatMap { top in
            frames.filter(\.prediction.containsDog).max {
                ($0.prediction.breedProbabilities[top.breed] ?? 0) < ($1.prediction.breedProbabilities[top.breed] ?? 0)
            }
        }
        return ScanResult(source: source, frames: frames, guesses: guesses,
                          dogPhoto: bestFrame.map(Self.photoOfDog), modelVersion: modelVersion)
    }

    private func loadedModel() throws -> VNCoreMLModel {
        if let model { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        // DogBreedClassifier is the class Xcode generates from DogBreedClassifier.mlpackage.
        let classifier = try DogBreedClassifier(configuration: configuration).model
        let metadata = classifier.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        modelVersion = metadata?["source"] ?? "unknown"
        let loaded = try VNCoreMLModel(for: classifier)
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


    /// Room left around the user's dog in the saved photo, as a share of its size on each
    /// side. More than the reference thumbnails get: the detector's outline of a dog lying
    /// down or being petted can stop short of its head.
    static let photoMargin: CGFloat = 0.3

    /// The frame cut to a square around the dog, for the result card and the Breeds
    /// collection, keeping the dog's head in view (see PhotoFocus). The square the classifier
    /// looks at is centered on the dog instead, which cut the top of the head off a dog too
    /// big for it, such as one sitting close to the camera.
    static func photoOfDog(in frame: FrameAnalysis) -> CGImage {
        let focus = PhotoFocus.find(in: frame.image, dog: frame.dogBox)
        let crop = focus.crop(of: CGSize(width: frame.image.width, height: frame.image.height),
                              aspectRatio: 1, margin: photoMargin)
        return frame.image.cropping(to: crop.integral) ?? frame.image
    }
}
