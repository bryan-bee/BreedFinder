import AVFoundation
import CoreGraphics
import CoreML
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
            FramePrediction(dogDetected: true, breedProbabilities: ["Beagle": 0.85]),
        ]

        let guesses = BreedAggregator.topGuesses(from: frames)

        XCTAssertEqual(guesses.map(\.breed), ["Beagle"])
        XCTAssertEqual(guesses[0].confidence, 1.0, accuracy: 0.0001)
    }

    func testConfidentClassifierCountsEvenWhenDetectorMissesTheDog() {
        let frames = Array(repeating: FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.9]), count: 2)

        XCTAssertEqual(BreedAggregator.topGuesses(from: frames).map(\.breed), ["Pug"])
    }

    /// An empty room: the animal detector fires, but the classifier mostly says "Not a dog".
    func testDetectorAloneDoesNotCountAFrame() {
        let frames = Array(
            repeating: FramePrediction(dogDetected: true, breedProbabilities: ["Pug": 0.1, "Beagle": 0.05, "Boxer": 0.03]),
            count: 5
        )

        XCTAssertTrue(BreedAggregator.topGuesses(from: frames).isEmpty)
    }

    func testUnsureClassifierDoesNotCountAFrame() {
        let frames = Array(
            repeating: FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.4, "Beagle": 0.3]),
            count: 5
        )

        XCTAssertTrue(BreedAggregator.topGuesses(from: frames).isEmpty)
    }

    func testOneStrayDogFrameIsNotEnough() {
        let empty = FramePrediction(dogDetected: false, breedProbabilities: ["Pug": 0.05])
        let frames = [empty, empty, FramePrediction(dogDetected: true, breedProbabilities: ["Pug": 0.95]), empty, empty]

        XCTAssertTrue(BreedAggregator.topGuesses(from: frames).isEmpty)
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

    func testCenterSquareIsCenteredAndSquareInPixels() {
        let region = DogAnalyzer.centerSquare(imageWidth: 1080, imageHeight: 1920)

        XCTAssertEqual(region.width, 1, accuracy: 0.0001)
        XCTAssertEqual(region.height * 1920, 1080, accuracy: 1)
        XCTAssertEqual(region.midY, 0.5, accuracy: 0.0001)
    }
}

final class ZoomScaleTests: XCTestCase {
    /// iPhone 16 Pro Max: ultra-wide, main and 5× telephoto lenses.
    func testTripleCameraWithFiveTimesTelephoto() {
        let scale = ZoomScale(
            lenses: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOverFactors: [2, 10],
            maxDeviceFactor: 100
        )

        XCTAssertEqual(scale.mainLensFactor, 2)
        XCTAssertEqual(scale.deviceFactor(for: 1), 2)
        XCTAssertEqual(scale.deviceFactor(for: 5), 10)
        XCTAssertEqual(scale.maxZoom, ZoomScale.limit)
        XCTAssertEqual(scale.presets, [1, 2, 5])
    }

    /// iPhone 15 Pro: 3× telephoto.
    func testTripleCameraWithThreeTimesTelephoto() {
        let scale = ZoomScale(
            lenses: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOverFactors: [2, 6],
            maxDeviceFactor: 100
        )

        XCTAssertEqual(scale.presets, [1, 2, 3])
    }

    /// iPhone 16: ultra-wide and main lenses, no telephoto.
    func testUltraWideAndMainLens() {
        let scale = ZoomScale(
            lenses: [.builtInUltraWideCamera, .builtInWideAngleCamera], switchOverFactors: [2], maxDeviceFactor: 100
        )

        XCTAssertEqual(scale.mainLensFactor, 2)
        XCTAssertEqual(scale.presets, [1, 2])
    }

    /// iPhone XS: main lens and 2× telephoto, so the telephoto's button is the 2× one.
    func testMainLensAndTwoTimesTelephoto() {
        let scale = ZoomScale(
            lenses: [.builtInWideAngleCamera, .builtInTelephotoCamera], switchOverFactors: [2], maxDeviceFactor: 16
        )

        XCTAssertEqual(scale.mainLensFactor, 1)
        XCTAssertEqual(scale.presets, [1, 2])
    }

    /// iPhone SE: one lens, which isn't a combined camera, so it lists no lenses.
    func testSingleLens() {
        let scale = ZoomScale(lenses: [], switchOverFactors: [], maxDeviceFactor: 16)

        XCTAssertEqual(scale.mainLensFactor, 1)
        XCTAssertEqual(scale.maxZoom, ZoomScale.limit)
        XCTAssertEqual(scale.presets, [1, 2])
    }

    func testButtonsBeyondTheMaximumZoomAreLeftOut() {
        let scale = ZoomScale(lenses: [], switchOverFactors: [], maxDeviceFactor: 1.5)

        XCTAssertEqual(scale.maxZoom, 1.5)
        XCTAssertEqual(scale.presets, [1])
    }

    func testLabelsAreWrittenLikeTheCameraApp() {
        XCTAssertEqual(ZoomScale.label(for: 1), "1")
        XCTAssertEqual(ZoomScale.label(for: 2.43), "2.4")
        XCTAssertEqual(ZoomScale.label(for: 4.98), "5")
    }

    /// On an iPhone, checks the real back camera: 1× and every zoom button must be zoom
    /// factors the camera accepts. The Simulator has no camera, so it skips this.
    func testThisPhonesBackCamera() throws {
        guard let camera = CameraController.backCamera() else { throw XCTSkip("No camera in the Simulator") }
        let scale = ZoomScale(camera: camera)

        XCTAssertEqual(scale.presets.first, 1)
        for zoom in scale.presets + [scale.maxZoom] {
            XCTAssertGreaterThanOrEqual(scale.deviceFactor(for: zoom), camera.minAvailableVideoZoomFactor)
            XCTAssertLessThanOrEqual(scale.deviceFactor(for: zoom), camera.activeFormat.videoMaxZoomFactor)
        }
    }
}

final class BreedContentTests: XCTestCase {
    /// The model and breeds.json are built separately; this catches them drifting apart.
    func testEveryBreedTheModelKnowsHasAProfile() throws {
        let model = try DogBreedClassifier(configuration: MLModelConfiguration()).model
        let labels = model.modelDescription.classLabels as? [String] ?? []
        XCTAssertFalse(labels.isEmpty)

        for label in labels where label != DogAnalyzer.notADogLabel {
            XCTAssertNotNil(BreedLibrary.shared.profile(for: label), "No profile for \(label)")
        }
    }

    func testProfilesWithPhotoCreditsHaveTheirPhotoBundled() throws {
        let model = try DogBreedClassifier(configuration: MLModelConfiguration()).model
        let labels = model.modelDescription.classLabels as? [String] ?? []

        for label in labels where BreedLibrary.shared.profile(for: label)?.photo != nil {
            XCTAssertNotNil(BreedLibrary.shared.photo(for: label), "Photo file missing for \(label)")
        }
    }
}
