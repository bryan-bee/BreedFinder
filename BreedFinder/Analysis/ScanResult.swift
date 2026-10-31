import CoreGraphics

/// What the models said about a single frame of the video.
struct FramePrediction {
    /// Whether Apple's built-in animal detector found a dog in the frame.
    let dogDetected: Bool

    /// Breed name → probability, straight from the classifier. These add up to the
    /// classifier's confidence that the frame shows a dog at all; the remainder
    /// went to its "Not a dog" class.
    let breedProbabilities: [String: Double]

    var dogProbability: Double { breedProbabilities.values.reduce(0, +) }

    /// Real dogs score above 0.99, even blurry or when the animal detector misses them,
    /// while rooms and furniture usually score well under 0.5. 0.8 leaves room for both.
    static let minimumDogProbability = 0.8

    /// A frame counts toward the answer only if the classifier is convinced there's a dog
    /// in it. The animal detector decides where the classifier looks, but isn't enough on
    /// its own: if it fires on something that isn't a dog, rescaling the classifier's
    /// small leftover breed probabilities to 100% turns them into a confident-looking guess.
    var containsDog: Bool { dogProbability >= Self.minimumDogProbability }
}

struct FrameAnalysis {
    let image: CGImage
    /// Where the animal detector found the dog: normalized, origin at the bottom-left
    /// (Vision's convention). Nil when it found none.
    let dogBox: CGRect?
    let prediction: FramePrediction
}

struct BreedGuess: Hashable, Identifiable {
    let breed: String
    /// 0...1, this breed's share of the combined dog probability across frames.
    let confidence: Double

    var id: String { breed }
}

struct ScanResult {
    let frames: [FrameAnalysis]
    /// Up to three guesses, best first. Empty when no frame contained a dog.
    let guesses: [BreedGuess]
    /// The frame that most resembles the top guess, cropped to the dog, for the result card.
    let dogPhoto: CGImage?
}
