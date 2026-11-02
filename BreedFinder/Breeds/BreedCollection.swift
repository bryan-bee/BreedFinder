import Foundation
import UIKit

/// One scan saved to the user's collection.
struct ScanRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// The breed this scan counts toward: the model's top guess, or the user's correction.
    var breed: String
    /// What the model guessed, kept so corrections can be shown (and measured later).
    let predictedBreed: String
    let confidence: Double
    /// The user's dog, cropped from the scan; a JPEG in the collection's Photos folder.
    let photoFile: String?

    var wasCorrected: Bool { breed != predictedBreed }
}

/// The Breeds tab's "Pokédex": every saved scan, stored on the device only.
///
/// Records live in Application Support/Collection/records.json and the dog photos next
/// to them. Counts are derived from the records, so correcting a scan just changes
/// which breed that one record counts toward.
@MainActor
final class BreedCollection: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []

    private let directory: URL
    /// Decoded dog photos, so list rows don't reread JPEGs from disk on every redraw. Capped:
    /// a decoded 600 × 600 photo takes about 1.4 MB of memory, however small its file.
    private let photoCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
    private var recordsFile: URL { directory.appendingPathComponent("records.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Collection", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: recordsFile),
           let saved = try? Self.decoder.decode([ScanRecord].self, from: data) {
            records = saved
        }
    }

    // MARK: Reading

    func count(for breed: String) -> Int {
        records.lazy.filter { $0.breed == breed }.count
    }

    func records(for breed: String) -> [ScanRecord] {
        records.filter { $0.breed == breed }.sorted { $0.date > $1.date }
    }

    func record(id: UUID) -> ScanRecord? {
        records.first { $0.id == id }
    }

    var collectedBreeds: Set<String> {
        Set(records.map(\.breed))
    }

    func photo(for record: ScanRecord) -> UIImage? {
        guard let file = record.photoFile else { return nil }
        if let cached = photoCache.object(forKey: file as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: photosDirectory.appendingPathComponent(file).path) else { return nil }
        let bytes = Int(image.size.width * image.scale * image.size.height * image.scale) * 4
        photoCache.setObject(image, forKey: file as NSString, cost: bytes)
        return image
    }

    /// The most recent photo of the user's own dog of this breed.
    func latestPhoto(for breed: String) -> UIImage? {
        records(for: breed).lazy.compactMap { self.photo(for: $0) }.first
    }

    // MARK: Changing

    /// Saves a scan that counts toward `breed` (normally the top guess). Returns its id.
    @discardableResult
    func add(breed: String, predictedBreed: String, confidence: Double, photo: CGImage?, date: Date = .now) -> UUID {
        let id = UUID()
        var photoFile: String?
        if let photo, let jpeg = Self.jpeg(from: photo) {
            let name = "\(id.uuidString).jpg"
            if (try? jpeg.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)) != nil {
                photoFile = name
            }
        }
        records.append(ScanRecord(id: id, date: date, breed: breed, predictedBreed: predictedBreed,
                                  confidence: confidence, photoFile: photoFile))
        save()
        return id
    }

    /// Recounts a scan as a different breed (when the prediction was wrong).
    func correct(_ id: UUID, to breed: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].breed = breed
        save()
    }

    /// Removes a scan from the collection, along with its photo.
    func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if let file = records[index].photoFile {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(file))
            photoCache.removeObject(forKey: file as NSString)
        }
        records.remove(at: index)
        save()
    }

    // MARK: Storage

    private func save() {
        do {
            try Self.encoder.encode(records).write(to: recordsFile, options: .atomic)
        } catch {
            assertionFailure("Couldn't save the collection: \(error)")
        }
    }

    /// Long side capped at 600 px; enough for the list and detail screens.
    private static func jpeg(from image: CGImage) -> Data? {
        let scale = min(1, 600 / CGFloat(max(image.width, image.height)))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
