import CoreGraphics
import XCTest
@testable import BreedFinder

final class BreedAggregatorTests: XCTestCase {
    func testCombinesFramesAndReturnsTopThree() {
        let frames = [
            FramePrediction(dogDetected: true, breedProbabilities: ["Beagle": 0.6, "Basset Hound": 0.3, "Pug": 0.05]),
            FramePrediction(dogDetected: true, breedProbabilities: ["Beagle": 0.4, "Basset Hound": 0.4, "Pug": 0.1, "Boxer": 0.05]),
        ]

        let guesses = BreedAggregator.topGuesses(from: frames)

        XCTAssertEqual(guesses.map(\.breed), ["Beagle", "Basset Hound", "Pug"])
        // Totals: Beagle 1.0, Basset 0.7, Pug 0.15, Boxer 0.05 → 1.9 overall.
        XCTAssertEqual(guesses[0].confidence, 1.0 / 1.9, accuracy: 0.0001)
        XCTAssertEqual(guesses[1].confidence, 0.7 / 1.9, accuracy: 0.0001)
    }

    func testIgnoresFramesWithoutADog() {
        let frames = [
            FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.2]),
            FramePrediction(dogDetected: true, breedProbabilities: ["Beagle": 0.9]),
        ]

        let guesses = BreedAggregator.topGuesses(from: frames)

        XCTAssertEqual(guesses.map(\.breed), ["Beagle"])
        XCTAssertEqual(guesses[0].confidence, 1.0, accuracy: 0.0001)
    }

    func testConfidentClassifierCountsEvenWhenDetectorMissesTheDog() {
        let frames = [FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.8])]

        XCTAssertEqual(BreedAggregator.topGuesses(from: frames).map(\.breed), ["Pug"])
    }

    func testNoDogInAnyFrameMeansNoGuesses() {
        let frames = Array(
            repeating: FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.1, "Beagle": 0.05]),
            count: 5
        )

        XCTAssertTrue(BreedAggregator.topGuesses(from: frames).isEmpty)
    }
}

final class SquareRegionTests: XCTestCase {
    func testRegionIsSquareInPixelsAndStaysInsideTheImage() {
        // A dog in the bottom-right corner of a portrait 1080x1920 frame.
        let box = CGRect(x: 0.7, y: 0.0, width: 0.3, height: 0.2)

        let region = DogAnalyzer.squareRegion(around: box, imageWidth: 1080, imageHeight: 1920)

        XCTAssertEqual(region.width * 1080, region.height * 1920, accuracy: 1)
        XCTAssertGreaterThanOrEqual(region.minX, 0)
        XCTAssertGreaterThanOrEqual(region.minY, 0)
        XCTAssertLessThanOrEqual(region.maxX, 1)
        XCTAssertLessThanOrEqual(region.maxY, 1)
        XCTAssertTrue(region.contains(CGPoint(x: box.midX, y: box.midY)))
    }

    func testRegionNeverExceedsTheShortSideOfTheImage() {
        let wholeFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let region = DogAnalyzer.squareRegion(around: wholeFrame, imageWidth: 1080, imageHeight: 1920)

        XCTAssertEqual(region.width, 1, accuracy: 0.0001)
        XCTAssertEqual(region.height * 1920, 1080, accuracy: 1)
    }
}
