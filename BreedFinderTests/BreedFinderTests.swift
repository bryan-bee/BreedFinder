import AVFoundation
import CoreGraphics
import CryptoKit
import CoreML
import UIKit
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

    /// Uploaded photos were each chosen on purpose, so one photo of a dog is enough,
    /// while one dog frame in a video still isn't.
    func testOneUploadedPhotoIsEnough() {
        let frames = [FramePrediction(dogDetected: true, breedProbabilities: ["Pug": 0.95])]
        let forPhotos = BreedAggregator.requiredDogFrames(for: .photos)
        let forVideo = BreedAggregator.requiredDogFrames(for: .video)

        XCTAssertEqual(BreedAggregator.topGuesses(from: frames, requiredDogFrames: forPhotos).map(\.breed), ["Pug"])
        XCTAssertTrue(BreedAggregator.topGuesses(from: frames, requiredDogFrames: forVideo).isEmpty)
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

final class BreedSearchTests: XCTestCase {
    func testTypedTextMatchesAnywhereInTheName() {
        let names = ["Chihuahua", "Chinese Crested", "Japanese Chin", "Schipperke", "Beagle", "Cocker Spaniel"]

        XCTAssertEqual(names.filter { BreedSearch.matches($0, query: "Chi") },
                       ["Chihuahua", "Chinese Crested", "Japanese Chin", "Schipperke"])
        XCTAssertEqual(names.filter { BreedSearch.matches($0, query: "C") },
                       ["Chihuahua", "Chinese Crested", "Japanese Chin", "Schipperke", "Cocker Spaniel"])
    }

    func testCaseAndAccentsDontMatter() {
        XCTAssertTrue(BreedSearch.matches("Chihuahua", query: "chi"))
        XCTAssertTrue(BreedSearch.matches("Chihuahua", query: "HUAHUA"))
        XCTAssertTrue(BreedSearch.matches("Bichon Frisé", query: "frise"))
    }

    func testStarStandsForAnyNumberOfCharacters() {
        XCTAssertTrue(BreedSearch.matches("Goldendoodle", query: "g*doodle"))
        XCTAssertTrue(BreedSearch.matches("Goldendoodle", query: "golden*doodle"))  // * can be nothing
        XCTAssertFalse(BreedSearch.matches("Goldendoodle", query: "doodle*golden"))  // order matters
        XCTAssertTrue(BreedSearch.matches("Beagle", query: "*"))
    }

    func testBlankSearchMatchesEveryBreed() {
        XCTAssertTrue(BreedSearch.matches("Beagle", query: ""))
        XCTAssertTrue(BreedSearch.matches("Beagle", query: "   "))
        XCTAssertTrue(BreedSearch.matches("Beagle", query: " bea "))
    }
}

final class PhotoFocusTests: XCTestCase {
    let photo = CGSize(width: 800, height: 600)

    /// A side-on dog longer than the biggest square the photo allows: its head stays in view.
    func testLongDogKeepsItsHeadInView() {
        let head = CGRect(x: 0.82, y: 0.15, width: 0.16, height: 0.25)
        let focus = PhotoFocus(dog: CGRect(x: 0.02, y: 0.2, width: 0.96, height: 0.6), head: head)

        let crop = focus.crop(of: photo, aspectRatio: 1)

        XCTAssertEqual(crop, CGRect(x: 200, y: 0, width: 600, height: 600))
        XCTAssertTrue(crop.contains(CGRect(x: 656, y: 90, width: 128, height: 150)))  // the head, in pixels
    }

    func testWholeDogThatFitsIsCenteredWithRoomAroundIt() {
        let dog = CGRect(x: 80, y: 60, width: 400, height: 360)  // in pixels

        let crop = PhotoFocus(dog: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.6), head: nil)
            .crop(of: photo, aspectRatio: 1)

        XCTAssertTrue(crop.contains(dog))
        XCTAssertGreaterThan(crop.width, dog.width)
        XCTAssertEqual(crop.midX, dog.midX, accuracy: 0.5)
    }

    func testSmallDogIsZoomedInButNotTooFar() {
        let crop = PhotoFocus(dog: CGRect(x: 0.45, y: 0.5, width: 0.1, height: 0.1), head: nil)
            .crop(of: photo, aspectRatio: 1)

        XCTAssertEqual(crop.width, 600 * PhotoFocus.tightestCrop, accuracy: 0.5)
        XCTAssertTrue(crop.contains(CGRect(x: 360, y: 300, width: 80, height: 60)))
    }

    /// Only a head found: the biggest square, slid over to it, rather than a close-up of fur.
    func testHeadWithoutTheDogsOutlineSlidesTheCropWithoutZooming() {
        let crop = PhotoFocus(dog: nil, head: CGRect(x: 0.02, y: 0.1, width: 0.15, height: 0.2))
            .crop(of: photo, aspectRatio: 1)

        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 600, height: 600))
    }

    /// A dog whose outline stops short of its head, like one lying down being petted, still
    /// fits with the bigger margin a scan's photo gets.
    func testScanPhotosLeaveMoreRoomAroundTheDog() {
        let portrait = CGSize(width: 900, height: 1200)
        let focus = PhotoFocus(dog: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4), head: nil)

        let thumbnail = focus.crop(of: portrait, aspectRatio: 1)
        let scanPhoto = focus.crop(of: portrait, aspectRatio: 1, margin: DogAnalyzer.photoMargin)

        XCTAssertGreaterThan(scanPhoto.width, thumbnail.width)
        XCTAssertTrue(scanPhoto.contains(CGRect(x: 72, y: 216, width: 576, height: 768)))  // 30% around the dog
    }

    func testNothingFoundMeansTheMiddle() {
        XCTAssertEqual(PhotoFocus().crop(of: photo, aspectRatio: 1), CGRect(x: 100, y: 0, width: 600, height: 600))
    }

    func testCropsAreSquareAndStayInsideThePhoto() {
        let cases: [(CGSize, CGRect)] = [
            (CGSize(width: 800, height: 600), CGRect(x: 0.9, y: 0.85, width: 0.1, height: 0.15)),  // in a corner
            (CGSize(width: 500, height: 900), CGRect(x: 0, y: 0, width: 1, height: 1)),  // a tall photo, all dog
        ]
        for (size, dog) in cases {
            let crop = PhotoFocus(dog: dog, head: nil).crop(of: size, aspectRatio: 1)

            XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5).contains(crop), "\(crop) in \(size)")
            XCTAssertEqual(crop.width, crop.height, accuracy: 0.5)
        }
    }

    /// tools/find_dogs_in_photos.swift has to run again whenever a photo is added or
    /// replaced, or its thumbnail gets cut around where the dog was in the old photo.
    func testEveryBreedPhotoHasBeenAnalyzed() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "focus", withExtension: "json", subdirectory: "BreedPhotos"))
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])

        for profile in BreedLibrary.shared.allProfiles {
            guard let file = profile.photo?.file else { continue }
            let photo = try XCTUnwrap(Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                                                      withExtension: (file as NSString).pathExtension,
                                                      subdirectory: "BreedPhotos"))
            let sha = SHA256.hash(data: try Data(contentsOf: photo)).map { String(format: "%02x", $0) }.joined().prefix(16)
            XCTAssertEqual(entries[file]?["sha256"] as? String, String(sha),
                           "\(file) is new or changed: run swift tools/find_dogs_in_photos.swift")
        }
    }
}

final class BreedPageTests: XCTestCase {
    /// Origin grouping lists a breed under each of its countries; swiping goes on from the
    /// row that was tapped.
    func testPagesFollowTheListAsShownFromTheTappedRow() throws {
        let library = BreedLibrary.shared
        let beagle = try XCTUnwrap(library.profile(for: "Beagle"))
        let collie = try XCTUnwrap(library.profile(for: "Border Collie"))
        let chihuahua = try XCTUnwrap(library.profile(for: "Chihuahua"))
        let sections = [
            BreedSection(title: "England", breeds: [beagle, collie]),
            BreedSection(title: "Scotland", breeds: [collie, chihuahua]),
        ]

        let pages = BreedPage.pages(for: sections)

        XCTAssertEqual(pages.map(\.count), [2, 2])
        XCTAssertEqual(pages[1][0].breeds, ["Beagle", "Border Collie", "Border Collie", "Chihuahua"])
        XCTAssertEqual(pages[1][0].index, 2)  // the second Border Collie: next is Chihuahua
        XCTAssertEqual(pages[0][1].index, 1)
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
        XCTAssertEqual(scale.minZoom, 0.5)
        XCTAssertEqual(scale.deviceFactor(for: 0.5), 1)  // the ultra-wide lens
        XCTAssertEqual(scale.deviceFactor(for: 1), 2)
        XCTAssertEqual(scale.deviceFactor(for: 5), 10)
        XCTAssertEqual(scale.maxZoom, ZoomScale.limit)
        XCTAssertEqual(scale.presets, [0.5, 1, 2, 5])
    }

    /// iPhone 15 Pro: 3× telephoto.
    func testTripleCameraWithThreeTimesTelephoto() {
        let scale = ZoomScale(
            lenses: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOverFactors: [2, 6],
            maxDeviceFactor: 100
        )

        XCTAssertEqual(scale.presets, [0.5, 1, 2, 3])
    }

    /// iPhone 16: ultra-wide and main lenses, no telephoto.
    func testUltraWideAndMainLens() {
        let scale = ZoomScale(
            lenses: [.builtInUltraWideCamera, .builtInWideAngleCamera], switchOverFactors: [2], maxDeviceFactor: 100
        )

        XCTAssertEqual(scale.mainLensFactor, 2)
        XCTAssertEqual(scale.presets, [0.5, 1, 2])
    }

    /// iPhone XS: main lens and 2× telephoto, so the telephoto's button is the 2× one,
    /// and there's no ultra-wide lens for 0.5×.
    func testMainLensAndTwoTimesTelephoto() {
        let scale = ZoomScale(
            lenses: [.builtInWideAngleCamera, .builtInTelephotoCamera], switchOverFactors: [2], maxDeviceFactor: 16
        )

        XCTAssertEqual(scale.mainLensFactor, 1)
        XCTAssertEqual(scale.minZoom, 1)
        XCTAssertEqual(scale.presets, [1, 2])
    }

    /// iPhone SE: one lens, which isn't a combined camera, so it lists no lenses.
    func testSingleLens() {
        let scale = ZoomScale(lenses: [], switchOverFactors: [], maxDeviceFactor: 16)

        XCTAssertEqual(scale.mainLensFactor, 1)
        XCTAssertEqual(scale.minZoom, 1)
        XCTAssertEqual(scale.maxZoom, ZoomScale.limit)
        XCTAssertEqual(scale.presets, [1, 2])
    }

    func testButtonsBeyondTheMaximumZoomAreLeftOut() {
        let scale = ZoomScale(lenses: [], switchOverFactors: [], maxDeviceFactor: 1.5)

        XCTAssertEqual(scale.maxZoom, 1.5)
        XCTAssertEqual(scale.presets, [1])
    }

    func testLabelsAreWrittenLikeTheCameraApp() {
        XCTAssertEqual(ZoomScale.label(for: 0.5), "0.5")
        XCTAssertEqual(ZoomScale.label(for: 1), "1")
        XCTAssertEqual(ZoomScale.label(for: 2.43), "2.4")
        XCTAssertEqual(ZoomScale.label(for: 4.98), "5")
    }

    /// On an iPhone, checks the real back camera: 1× and every zoom button must be zoom
    /// factors the camera accepts. The Simulator has no camera, so it skips this.
    func testThisPhonesBackCamera() throws {
        guard let camera = CameraController.backCamera() else { throw XCTSkip("No camera in the Simulator") }
        let scale = ZoomScale(camera: camera)

        XCTAssertTrue(scale.presets.contains(1))
        for zoom in scale.presets + [scale.minZoom, scale.maxZoom] {
            XCTAssertGreaterThanOrEqual(scale.deviceFactor(for: zoom), camera.minAvailableVideoZoomFactor)
            XCTAssertLessThanOrEqual(scale.deviceFactor(for: zoom), camera.activeFormat.videoMaxZoomFactor)
        }
    }
}

final class BreedCollectionTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    func testCountsFollowCorrectionsAndRemovals() {
        let collection = BreedCollection(directory: temporaryDirectory())
        let first = collection.add(breed: "Beagle", predictedBreed: "Beagle", confidence: 0.9, photo: nil)
        collection.add(breed: "Beagle", predictedBreed: "Beagle", confidence: 0.8, photo: nil)
        collection.add(breed: "Pug", predictedBreed: "Pug", confidence: 0.7, photo: nil)
        XCTAssertEqual(collection.count(for: "Beagle"), 2)

        // The model said Beagle, but it was really a Pug.
        collection.correct(first, to: "Pug")
        XCTAssertEqual(collection.count(for: "Beagle"), 1)
        XCTAssertEqual(collection.count(for: "Pug"), 2)
        XCTAssertEqual(collection.record(id: first)?.wasCorrected, true)

        collection.remove(first)
        XCTAssertEqual(collection.count(for: "Pug"), 1)
        XCTAssertEqual(collection.collectedBreeds, ["Beagle", "Pug"])
    }

    @MainActor
    func testScansAndPhotosSurviveARestart() throws {
        let directory = temporaryDirectory()
        let photo = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }.cgImage)
        let id = BreedCollection(directory: directory)
            .add(breed: "Vizsla", predictedBreed: "Weimaraner", confidence: 0.6, photo: photo)

        let reopened = BreedCollection(directory: directory)
        let record = try XCTUnwrap(reopened.record(id: id))
        XCTAssertEqual(record.breed, "Vizsla")
        XCTAssertEqual(record.predictedBreed, "Weimaraner")
        XCTAssertNotNil(reopened.photo(for: record))
    }
}

final class RecentScansTests: XCTestCase {
    private func makeResult(frames: Int, top: String?) throws -> ScanResult {
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
        }.cgImage)
        let prediction = FramePrediction(dogDetected: top != nil, breedProbabilities: top.map { [$0: 0.9] } ?? [:])
        return ScanResult(source: .video,
                          frames: Array(repeating: FrameAnalysis(image: image, dogBox: nil, prediction: prediction), count: frames),
                          guesses: top.map { [BreedGuess(breed: $0, confidence: 0.9)] } ?? [],
                          dogPhoto: nil, modelVersion: "test-model")
    }

    @MainActor
    func testKeepsOnlyTheNewestScansAndDeletesOldFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RecentScansStore(directory: directory)
        var ids: [UUID] = []
        for _ in 0..<(RecentScansStore.limit + 2) {
            let id = UUID()
            ids.append(id)
            let result = try makeResult(frames: 2, top: "Beagle")
            await store.add(id: id, result: result, recordID: nil)
        }

        XCTAssertEqual(store.scans.count, RecentScansStore.limit)
        XCTAssertEqual(store.scans.first?.id, ids.last)  // newest first
        XCTAssertNil(store.scan(id: ids[0]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(ids[0].uuidString).path))

        let newest = try XCTUnwrap(store.scans.first)
        XCTAssertEqual(store.attachments(for: newest).count, 2)

        // Survives the app restarting.
        XCTAssertEqual(RecentScansStore(directory: directory).scans.map(\.id), store.scans.map(\.id))
    }
}

final class ProblemReportTests: XCTestCase {
    private func report(kind: ProblemKind, scan: RecentScan?) -> ProblemReport {
        ProblemReport(kind: kind, details: "  It's my neighbor's dog.  ", actualBreed: "Labrador Retriever",
                      scan: scan, countedAs: "Labrador Retriever", appVersion: "1.1.0 (7)",
                      modelVersion: "current-model", systemVersion: "18.1", deviceModel: "iPhone16,1")
    }

    func testWrongBreedReportIncludesWhatTheAppSaidAndWhatItReallyIs() {
        let scan = RecentScan(id: UUID(), date: .now, source: .video,
                              guesses: [BreedGuess(breed: "Golden Retriever", confidence: 0.72),
                                        BreedGuess(breed: "Labrador Retriever", confidence: 0.2)],
                              framesWithDog: [true, true, false, true, true], frameFiles: [],
                              modelVersion: "scan-model", recordID: nil)
        let body = report(kind: .wrongBreed, scan: scan).body

        XCTAssertTrue(body.contains("What it really is: Labrador Retriever"))
        XCTAssertTrue(body.contains("It's my neighbor's dog."))
        XCTAssertTrue(body.contains("App said #1: Golden Retriever"))
        XCTAssertTrue(body.contains("App said #2: Labrador Retriever"))
        XCTAssertTrue(body.contains("5 frames, dog found in 4"))
        XCTAssertTrue(body.contains("Breed model: scan-model"))  // the model that made the guess
        XCTAssertTrue(body.contains("iPhone: iPhone16,1"))
        XCTAssertTrue(body.contains("Photos attached: no"))
    }

    func testTrainingPermissionIsStatedOnlyWhenPhotosAreAttached() {
        let scan = RecentScan(id: UUID(), date: .now, source: .photos,
                              guesses: [BreedGuess(breed: "Pug", confidence: 0.9)],
                              framesWithDog: [true], frameFiles: ["frame-1.jpg"],
                              modelVersion: "scan-model", recordID: nil)
        var withPhotos = report(kind: .wrongBreed, scan: scan)
        withPhotos.photosAttached = true
        withPhotos.allowsTrainingUse = true

        XCTAssertTrue(withPhotos.body.contains("OK to use these photos to improve breed recognition: yes"))
        XCTAssertFalse(report(kind: .wrongBreed, scan: scan).body.contains("improve breed recognition"))
    }

    func testReportWithoutAScanStillNamesTheModel() {
        let body = report(kind: .crash, scan: nil).body

        XCTAssertFalse(body.contains("What it really is"))  // only for wrong-breed reports
        XCTAssertTrue(body.contains("No scan attached"))
        XCTAssertTrue(body.contains("Breed model: current-model"))
    }
}

final class BreedGroupingTests: XCTestCase {
    private func profile(_ name: String, countries: [String], group: String) -> BreedProfile {
        BreedProfile(name: name, summary: "", origin: countries.joined(separator: " and "), lifespan: "",
                     weight: "", group: group, temperament: [], funFacts: [], photo: nil,
                     originCountries: countries, groupKey: group)
    }

    private lazy var profiles = [
        profile("Beagle", countries: ["England"], group: "Hound"),
        profile("Border Collie", countries: ["Scotland", "England"], group: "Herding"),
        profile("Cockapoo", countries: ["United States"], group: "Designer crossbreed"),
        profile("Dingo", countries: ["Australia"], group: "Other"),
    ]

    func testAlphabeticalIsOneUntitledSection() {
        let sections = BreedGrouping.alphabetical.sections(of: profiles, collected: [])
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
        XCTAssertEqual(sections[0].breeds.count, 4)
    }

    func testOriginListsMultiCountryBreedsUnderEachCountry() {
        let sections = BreedGrouping.origin.sections(of: profiles, collected: [])
        XCTAssertEqual(sections.map(\.title), ["Australia", "England", "Scotland", "United States"])
        XCTAssertEqual(sections[1].breeds.map(\.name), ["Beagle", "Border Collie"])
        XCTAssertEqual(sections[2].breeds.map(\.name), ["Border Collie"])
    }

    func testGroupsFollowAKCOrderWithOthersLast() {
        let titles = BreedGrouping.group.sections(of: profiles, collected: []).map(\.title)
        XCTAssertEqual(titles, ["Hound", "Herding", "Designer crossbreed", "Other breeds"])
    }

    func testCollectedSplitsCaughtFromNotYet() {
        let sections = BreedGrouping.collected.sections(of: profiles, collected: ["Dingo"])
        XCTAssertEqual(sections.map(\.title), ["Collected", "Not yet"])
        XCTAssertEqual(sections[0].breeds.map(\.name), ["Dingo"])
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

    /// CC BY and CC BY-SA photos must credit their author and link their license, and every
    /// credit shown in the app must name the license.
    func testPhotoCreditsMeetTheirLicenses() {
        for profile in BreedLibrary.shared.allProfiles {
            guard let credit = profile.photo else { continue }
            XCTAssertTrue(String(credit.attribution.characters).contains(credit.license), profile.name)
            guard credit.license.uppercased().hasPrefix("CC BY") else { continue }
            XCTAssertNotEqual(credit.author, "Unknown", "\(profile.name)'s photo needs an author")
            XCTAssertNotNil(credit.licenseURL.flatMap(URL.init(string:)), "\(profile.name)'s photo needs a license link")
        }
    }

    /// Pets Adviser, who took the Belgian Tervuren photo, asks credits to link to its website,
    /// which CC BY 2.0 lets an author require.
    func testCreditLinksTheAuthorWhenTheyAskForIt() throws {
        let credit = try XCTUnwrap(BreedLibrary.shared.profile(for: "Belgian Tervuren")?.photo)
        let links = credit.attribution.runs.compactMap { $0.link }
        XCTAssertTrue(links.contains(URL(string: "https://www.petsadviser.com")!))
    }

    func testProfilesWithPhotoCreditsHaveTheirPhotoBundled() throws {
        let model = try DogBreedClassifier(configuration: MLModelConfiguration()).model
        let labels = model.modelDescription.classLabels as? [String] ?? []

        for label in labels where BreedLibrary.shared.profile(for: label)?.photo != nil {
            XCTAssertNotNil(BreedLibrary.shared.photo(for: label), "Photo file missing for \(label)")
        }
    }
}

final class FeedbackTests: XCTestCase {
    private let guesses = [BreedGuess(breed: "Golden Retriever", confidence: 0.72),
                           BreedGuess(breed: "Labrador Retriever", confidence: 0.2),
                           BreedGuess(breed: "Flat-Coated Retriever", confidence: 0.05)]

    func testPickedBreedIsRankedAgainstTheTopGuesses() {
        XCTAssertEqual(ScanFeedback(breed: "Golden Retriever", guesses: guesses), .correct)
        XCTAssertEqual(ScanFeedback(breed: "Flat-Coated Retriever", guesses: guesses),
                       .otherBreed("Flat-Coated Retriever", rank: 3))
        XCTAssertEqual(ScanFeedback(breed: "Beagle", guesses: guesses), .otherBreed("Beagle", rank: nil))
    }

    /// The accuracy stats are counted from these: top-1 is "top1" out of every answer but
    /// "unsure", top-3 is "top1" to "top3" out of the answers that name the breed.
    func testAnswersAreRecordedByRank() {
        XCTAssertEqual(ScanFeedback.correct.statsAnswer, "top1")
        XCTAssertEqual(ScanFeedback.otherBreed("Labrador Retriever", rank: 2).statsAnswer, "top2")
        XCTAssertEqual(ScanFeedback.otherBreed("Beagle", rank: nil).statsAnswer, "notInTop3")
        XCTAssertEqual(ScanFeedback.notTopGuess.statsAnswer, "notTop1")
        XCTAssertEqual(ScanFeedback.unsure.statsAnswer, "unsure")
    }

    func testQuestionUsesTheRightArticle() {
        XCTAssertEqual(withArticle("Akita"), "an Akita")
        XCTAssertEqual(withArticle("Old English Sheepdog"), "an Old English Sheepdog")
        XCTAssertEqual(withArticle("Beagle"), "a Beagle")
    }
}

final class AnalyticsEventTests: XCTestCase {
    private let guesses = [BreedGuess(breed: "Golden Retriever", confidence: 0.72),
                           BreedGuess(breed: "Labrador Retriever", confidence: 0.2),
                           BreedGuess(breed: "Flat-Coated Retriever", confidence: 0.05)]

    /// A video scan of `frames` frames, the first `dogFrames` of them with a dog.
    private func makeResult(guesses: [BreedGuess], dogFrames: Int, frames: Int = 5) throws -> ScanResult {
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
        }.cgImage)
        let dog = FramePrediction(dogDetected: true, breedProbabilities: ["Golden Retriever": 0.95])
        let empty = FramePrediction(dogDetected: false, breedProbabilities: [:])
        let analyses = (0..<frames).map { index in
            FrameAnalysis(image: image, dogBox: nil, prediction: index < dogFrames ? dog : empty)
        }
        return ScanResult(source: .video, frames: analyses, guesses: guesses, dogPhoto: nil, modelVersion: "test-model")
    }

    func testCompletedScanSendsTheGuessConfidenceAndAnalysisTime() throws {
        let scan = try makeResult(guesses: guesses, dogFrames: 4)
        let event = AnalyticsEvent.scanFinished(scan, analysisTime: .milliseconds(420), collectedBreeds: 7)

        XCTAssertEqual(event.name, "Scan.completed")
        XCTAssertEqual(event.parameters["source"], "video")
        XCTAssertEqual(event.parameters["frames"], "5")
        XCTAssertEqual(event.parameters["dogFrames"], "4")
        XCTAssertEqual(event.parameters["topBreed"], "Golden Retriever")
        XCTAssertEqual(event.parameters["confidence"], "70-80%")
        XCTAssertEqual(event.parameters["collectedBreeds"], "7")
        XCTAssertEqual(event.parameters["modelVersion"], "test-model")
        XCTAssertEqual(try XCTUnwrap(event.floatValue), 420, accuracy: 0.001)  // milliseconds
    }

    func testScanWithoutADogIsItsOwnSignal() throws {
        let scan = try makeResult(guesses: [], dogFrames: 1)
        let event = AnalyticsEvent.scanFinished(scan, analysisTime: .milliseconds(300), collectedBreeds: 0)

        XCTAssertEqual(event.name, "Scan.noDogFound")
        XCTAssertEqual(event.parameters["dogFrames"], "1")
        XCTAssertNil(event.parameters["topBreed"])
    }

    func testFeedbackNamesWhatTheAppSaidAndWhatItReallyIs() throws {
        let scan = try makeResult(guesses: guesses, dogFrames: 5)
        let corrected = AnalyticsEvent.feedback(.otherBreed("Labrador Retriever", rank: 2), on: scan)

        XCTAssertEqual(corrected.name, "Scan.feedback")
        XCTAssertEqual(corrected.parameters["answer"], "top2")
        XCTAssertEqual(corrected.parameters["topBreed"], "Golden Retriever")
        XCTAssertEqual(corrected.parameters["actualBreed"], "Labrador Retriever")
        XCTAssertEqual(corrected.parameters["confidence"], "70-80%")
        XCTAssertEqual(try XCTUnwrap(corrected.floatValue), 0.72, accuracy: 0.0001)

        XCTAssertEqual(AnalyticsEvent.feedback(.correct, on: scan).parameters["actualBreed"], "Golden Retriever")
        XCTAssertNil(AnalyticsEvent.feedback(.unsure, on: scan).parameters["actualBreed"])
    }

    func testConfidenceIsGroupedInTenPointRanges() {
        XCTAssertEqual(AnalyticsEvent.confidenceBin(0.05), "0-10%")
        XCTAssertEqual(AnalyticsEvent.confidenceBin(0.72), "70-80%")
        XCTAssertEqual(AnalyticsEvent.confidenceBin(0.999), "90-100%")
        XCTAssertEqual(AnalyticsEvent.confidenceBin(1), "90-100%")
        XCTAssertEqual(AnalyticsEvent.confidenceBin(.nan), "unknown")
    }

    func testReportSendsItsKindButNeverItsText() {
        var report = ProblemReport(kind: .wrongBreed, details: "It's my neighbor's dog.", actualBreed: "Pug",
                                   scan: nil, countedAs: nil, appVersion: "1.0.0 (2)", modelVersion: "model",
                                   systemVersion: "26.0", deviceModel: "iPhone17,1")
        report.photosAttached = true
        let event = AnalyticsEvent.reportSent(report, via: "mail")

        XCTAssertEqual(event.name, "Report.sent")
        XCTAssertEqual(event.parameters["kind"], "Wrong breed")
        XCTAssertEqual(event.parameters["photosAttached"], "yes")
        XCTAssertFalse(event.parameters.values.contains { $0.contains("neighbor") || $0 == "Pug" })
    }

    /// With no TelemetryDeck App ID the SDK never starts, so sending has to do nothing.
    /// (TelemetryDeck halts Debug builds that send a signal before it's initialized.)
    @MainActor
    func testSendingWithoutAnAppIDDoesNothing() throws {
        try XCTSkipIf(Analytics.isConfigured, "A TelemetryDeck App ID is set")
        Analytics.start()
        Analytics.send(.scanFailed(step: "test"))
    }
}
