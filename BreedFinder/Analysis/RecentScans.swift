import Foundation
import UIKit

/// A scan kept for a while so it can be attached to a problem report.
struct RecentScan: Codable, Identifiable {
    let id: UUID
    let date: Date
    let source: ScanSource
    let guesses: [BreedGuess]
    /// Per frame or photo: did the app think there was a dog in it?
    let framesWithDog: [Bool]
    /// JPEGs of the frames/photos the model looked at, in this scan's cache folder.
    let frameFiles: [String]
    let modelVersion: String
    /// The collection record this scan counts as, if any.
    var recordID: UUID?
}

struct ReportAttachment {
    let fileName: String
    let data: Data
}

/// The last 10 scans (their frames and what the model said), so a problem report can
/// include exactly what the app looked at.
///
/// Stored in the Caches folder: it survives restarts and crashes, the oldest scan is
/// deleted as each new one arrives, and iOS may clear it when storage runs low.
/// Nothing here leaves the phone unless the user attaches it to a report.
@MainActor
final class RecentScansStore: ObservableObject {
    static let limit = 10

    /// Newest first.
    @Published private(set) var scans: [RecentScan] = []

    private let directory: URL
    private let thumbnails = NSCache<NSString, UIImage>()
    private var indexFile: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecentScans", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexFile),
           let saved = try? Self.decoder.decode([RecentScan].self, from: data) {
            // iOS may have cleared part of the cache.
            scans = saved.filter { FileManager.default.fileExists(atPath: folder(for: $0.id).path) }
        }
    }

    func scan(id: UUID?) -> RecentScan? {
        guard let id else { return nil }
        return scans.first { $0.id == id }
    }

    /// Saves a scan's frames and results. The JPEG encoding runs off the main thread.
    func add(id: UUID, result: ScanResult, recordID: UUID?) async {
        let folder = self.folder(for: id)
        let images = result.frames.map(\.image)
        let files = await Task.detached(priority: .utility) { () -> [String] in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files: [String] = []
            for (index, image) in images.enumerated() {
                let name = "frame-\(index + 1).jpg"
                if let data = RecentScansStore.jpeg(from: image),
                   (try? data.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil {
                    files.append(name)
                }
            }
            return files
        }.value

        scans.insert(RecentScan(id: id, date: .now, source: result.source, guesses: result.guesses,
                                framesWithDog: result.frames.map(\.prediction.containsDog),
                                frameFiles: files, modelVersion: result.modelVersion, recordID: recordID),
                     at: 0)
        while scans.count > Self.limit {
            let oldest = scans.removeLast()
            try? FileManager.default.removeItem(at: self.folder(for: oldest.id))
        }
        save()
    }

    /// Updates which collection record a scan counts as (after the user adds it back).
    func link(scanID: UUID, recordID: UUID?) {
        guard let index = scans.firstIndex(where: { $0.id == scanID }) else { return }
        scans[index].recordID = recordID
        save()
    }

    /// A small version of one frame, for pickers and previews.
    func thumbnail(for scan: RecentScan, frame index: Int) -> UIImage? {
        guard scan.frameFiles.indices.contains(index) else { return nil }
        let key = "\(scan.id)-\(index)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let url = folder(for: scan.id).appendingPathComponent(scan.frameFiles[index])
        guard let full = UIImage(contentsOfFile: url.path), full.size.width > 0, full.size.height > 0 else { return nil }
        // Short side 160 px, same proportions as the frame.
        let scale = 160 / min(full.size.width, full.size.height)
        guard let image = full.preparingThumbnail(of: CGSize(width: full.size.width * scale,
                                                             height: full.size.height * scale)) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// The frames as email attachments.
    func attachments(for scan: RecentScan) -> [ReportAttachment] {
        scan.frameFiles.compactMap { file in
            guard let data = try? Data(contentsOf: folder(for: scan.id).appendingPathComponent(file)) else { return nil }
            return ReportAttachment(fileName: "\(scan.source.itemName)-\(file)", data: data)
        }
    }

    // MARK: Storage

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func save() {
        try? Self.encoder.encode(scans).write(to: indexFile, options: .atomic)
    }

    /// Long side at most 1024 px: plenty to see what the model saw, small enough to email.
    nonisolated static func jpeg(from image: CGImage) -> Data? {
        let scale = min(1, 1024 / CGFloat(max(image.width, image.height)))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.75)
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
