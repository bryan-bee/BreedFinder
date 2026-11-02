// Finds the dog, and its head, in each breed reference photo with Apple's Vision, so the
// app can cut small square thumbnails around the dog instead of the middle of the photo
// (which, for the many side-on photos, is the dog's body without its head). Run it on a
// Mac whenever the photos change:
//
//     swift tools/find_dogs_in_photos.swift
//
// Writes Resources/BreedPhotos/focus.json. For each photo: the dog's box and its head's
// box as fractions of the photo's size, origin at the top left (either can be missing if
// Vision didn't find it), and the start of the file's SHA-256 so a unit test notices a
// photo that changed without being analyzed again.

import CryptoKit
import Foundation
import ImageIO
import Vision

struct Entry: Codable {
    let sha256: String
    let dog: CGRect?
    let head: CGRect?
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/BreedPhotos")
let photos = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    .filter { $0.lowercased().hasSuffix(".jpg") }
    .sorted()

/// The photo upright, the way UIImage shows it.
func uprightImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

/// Vision's rects start at the bottom left; the app's at the top left.
func topLeft(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
}

func rounded(_ rect: CGRect) -> CGRect {
    func r(_ value: CGFloat) -> CGFloat { (value * 10_000).rounded() / 10_000 }
    return CGRect(x: r(rect.minX), y: r(rect.minY), width: r(rect.width), height: r(rect.height))
}

/// The biggest dog Apple's animal detector finds, the same detector the app scans with.
func dogBox(in image: CGImage) throws -> CGRect? {
    let request = VNRecognizeAnimalsRequest()
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    return (request.results ?? [])
        .filter { $0.labels.contains { $0.identifier == VNAnimalIdentifier.dog.rawValue && $0.confidence >= 0.3 } }
        .map(\.boundingBox)
        .max { $0.width * $0.height < $1.width * $1.height }
}

/// A square around the eyes, nose and ears that Vision's animal pose detector finds, a
/// little bigger than they are, since they sit inside the head. Prefers the dog in `dog`.
func headBox(in image: CGImage, dog: CGRect?) throws -> CGRect? {
    guard #available(macOS 14, *) else { return nil }
    let request = VNDetectAnimalBodyPoseRequest()
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    let heads: [CGRect] = (request.results ?? []).compactMap { pose in
        let points = ((try? pose.recognizedPoints(.head)) ?? [:]).values.filter { $0.confidence > 0.2 }
        guard points.count >= 2 else { return nil }
        let xs = points.map(\.location.x), ys = points.map(\.location.y)
        let center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        // Normalized units differ on the two axes; size the square in pixels.
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let span = max((xs.max()! - xs.min()!) * width, (ys.max()! - ys.min()!) * height)
        let side = max(span * 1.6, min(width, height) * 0.12)
        return CGRect(x: center.x - side / 2 / width, y: center.y - side / 2 / height,
                      width: side / width, height: side / height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    guard let dog else { return heads.first }
    return heads.first { dog.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? heads.first
}

var entries: [String: Entry] = [:]
var found = (dog: 0, head: 0)
for name in photos {
    let url = folder.appendingPathComponent(name)
    let data = try Data(contentsOf: url)
    let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16)
    guard let image = uprightImage(url) else {
        print("Couldn't read \(name)")
        continue
    }
    let dog = try dogBox(in: image)
    let head = try headBox(in: image, dog: dog)
    found.dog += dog == nil ? 0 : 1
    found.head += head == nil ? 0 : 1
    entries[name] = Entry(sha256: String(sha), dog: dog.map { rounded(topLeft($0)) },
                          head: head.map { rounded(topLeft($0)) })
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(entries).write(to: folder.appendingPathComponent("focus.json"))
print("\(photos.count) photos: found the dog in \(found.dog), its head in \(found.head).")
