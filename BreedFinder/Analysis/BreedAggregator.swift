enum BreedAggregator {
    /// A dog that's really there shows up in most of the 5 frames, so a single stray
    /// frame isn't enough to name a breed.
    static let minimumDogFrames = 2

    /// How many frames must show a dog. Video needs `minimumDogFrames`; uploaded photos
    /// were each chosen on purpose, and there may be only one, so one is enough.
    static func requiredDogFrames(for source: ScanSource) -> Int {
        source == .video ? minimumDogFrames : 1
    }

    /// Adds up each breed's probability across every frame that shows a dog, then
    /// rescales the totals to sum to 1. A frame the classifier is unsure about
    /// (blurry, dog half out of view) carries less probability, so it counts for less.
    static func topGuesses(from frames: [FramePrediction],
                           requiredDogFrames: Int = BreedAggregator.minimumDogFrames,
                           limit: Int = 3) -> [BreedGuess] {
        let dogFrames = frames.filter(\.containsDog)
        guard dogFrames.count >= requiredDogFrames else { return [] }

        var totals: [String: Double] = [:]
        for frame in dogFrames {
            for (breed, probability) in frame.breedProbabilities {
                totals[breed, default: 0] += probability
            }
        }

        let combined = totals.values.reduce(0, +)
        guard combined > 0 else { return [] }

        let ranked = totals
            .map { BreedGuess(breed: $0.key, confidence: $0.value / combined) }
            .sorted { $0.confidence > $1.confidence }
        return Array(ranked.prefix(limit))
    }
}
