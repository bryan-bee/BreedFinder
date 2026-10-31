enum BreedAggregator {
    /// Adds up each breed's probability across every frame that shows a dog, then
    /// rescales the totals to sum to 1. A frame the classifier is unsure about
    /// (blurry, dog half out of view) carries less probability, so it counts for less.
    static func topGuesses(from frames: [FramePrediction], limit: Int = 3) -> [BreedGuess] {
        var totals: [String: Double] = [:]
        for frame in frames where frame.containsDog {
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
