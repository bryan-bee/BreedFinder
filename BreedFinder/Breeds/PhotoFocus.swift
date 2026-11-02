import CoreGraphics
import Vision

/// Where the dog is in a breed's reference photo: the whole dog and its head, as fractions
/// of the photo's size with the origin at the top left. Found ahead of time with Apple's
/// Vision by tools/find_dogs_in_photos.swift and stored in BreedPhotos/focus.json; either
/// can be missing when Vision didn't find it.
struct PhotoFocus: Decodable, Equatable {
    var dog: CGRect?
    var head: CGRect?

    /// Room left around the dog, as a share of its size on each side.
    static let margin: CGFloat = 0.08
    /// The tightest crop, as a share of the biggest one the photo allows, so a small dog in
    /// a big photo doesn't become a blurry close-up.
    static let tightestCrop: CGFloat = 0.4
    /// The most of a photo's width or height a frame may cut off to fill itself. Any more
    /// risks the dog's head or legs, so the frame shows the whole photo instead.
    static let mostCutToFill: CGFloat = 0.15

    /// The part of a photo of `size` to show in a frame shaped `aspectRatio` (width ÷
    /// height): the whole dog with a little room around it when it fits; otherwise as much
    /// of the dog as fits, keeping its head in view. Without the dog's outline, the biggest
    /// crop, around its head if Vision found that, or else the middle.
    func crop(of size: CGSize, aspectRatio: CGFloat, margin: CGFloat = PhotoFocus.margin) -> CGRect {
        let largest = Self.largestCrop(of: size, aspectRatio: aspectRatio)
        let head = self.head.map { Self.inPixels($0, of: size) }
        guard let subject = dog.map({ Self.inPixels($0, of: size) }) else {
            // Zooming in on just a head gives a blurry close-up of fur, so only slide the crop.
            let center = head.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
            return CGRect(x: min(max(center.x - largest.width / 2, 0), size.width - largest.width),
                          y: min(max(center.y - largest.height / 2, 0), size.height - largest.height),
                          width: largest.width, height: largest.height)
        }

        // The detector's outline sometimes stops short of an ear or the nose, so count the
        // head as part of the dog.
        let padded = subject.insetBy(dx: -subject.width * margin, dy: -subject.height * margin)
            .union(head ?? .null)
        // The narrowest frame-shaped crop that holds the padded dog, within the limits above.
        let width = min(max(padded.width, padded.height * aspectRatio, largest.width * Self.tightestCrop),
                        largest.width)
        let height = width / aspectRatio
        let x = Self.start(of: width, subject: padded.minX...padded.maxX, head: head.map { $0.minX...$0.maxX },
                           photoLength: size.width, withoutHead: .middle)
        let y = Self.start(of: height, subject: padded.minY...padded.maxY, head: head.map { $0.minY...$0.maxY },
                           photoLength: size.height, withoutHead: .start)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The part of a photo of `size` to show in a frame shaped `aspectRatio` that should show
    /// the whole dog, like the breed page's photo. A photo close to the frame's shape fills
    /// it, the strip cut off taken from where it keeps the dog's head in view (or, with no
    /// head found, the top of the dog). Any other photo is shown whole: the rect runs past
    /// its edges where the frame has room left over. Unlike crop(of:aspectRatio:) it never
    /// zooms in on the dog, since Vision's outline of a dog often stops above its legs.
    func region(of size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let photoRatio = size.width / size.height
        guard 1 - min(photoRatio, aspectRatio) / max(photoRatio, aspectRatio) <= Self.mostCutToFill else {
            let width = max(size.width, size.height * aspectRatio)
            let height = width / aspectRatio
            return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }
        let largest = Self.largestCrop(of: size, aspectRatio: aspectRatio)
        let keep = (head ?? dog).map { Self.inPixels($0, of: size) }
        func start(of length: CGFloat, photoLength: CGFloat, keeping range: ClosedRange<CGFloat>?) -> CGFloat {
            var start = (photoLength - length) / 2
            if let range {
                // Its far end first, so a head longer than the frame keeps its top.
                start = min(max(start, range.upperBound - length), range.lowerBound)
            }
            return min(max(start, 0), photoLength - length)
        }
        return CGRect(x: start(of: largest.width, photoLength: size.width, keeping: keep.map { $0.minX...$0.maxX }),
                      y: start(of: largest.height, photoLength: size.height, keeping: keep.map { $0.minY...$0.maxY }),
                      width: largest.width, height: largest.height)
    }

    /// The biggest frame-shaped crop a photo of `size` has room for.
    private static func largestCrop(of size: CGSize, aspectRatio: CGFloat) -> CGSize {
        size.width / size.height > aspectRatio
            ? CGSize(width: size.height * aspectRatio, height: size.height)
            : CGSize(width: size.width, height: size.width / aspectRatio)
    }

    private static func inPixels(_ rect: CGRect, of size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    private enum Placement { case start, middle }

    /// Where the crop starts along one axis. Centered on the dog when the dog fits;
    /// otherwise centered on the head while staying on the dog, or, with no head found,
    /// at the dog's top (dogs' heads are usually up) or its middle. Always inside the photo.
    private static func start(of length: CGFloat, subject: ClosedRange<CGFloat>, head: ClosedRange<CGFloat>?,
                              photoLength: CGFloat, withoutHead placement: Placement) -> CGFloat {
        func middle(_ range: ClosedRange<CGFloat>) -> CGFloat { (range.lowerBound + range.upperBound) / 2 }
        let start: CGFloat
        if subject.upperBound - subject.lowerBound <= length {
            start = middle(subject) - length / 2
        } else if let head {
            start = min(max(middle(head) - length / 2, subject.lowerBound), subject.upperBound - length)
        } else {
            start = placement == .start ? subject.lowerBound : middle(subject) - length / 2
        }
        return min(max(start, 0), photoLength - length)
    }
}

extension PhotoFocus {
    /// Where the dog is in `image`, given the dog's outline from Apple's animal detector
    /// (normalized, origin at the bottom left, as Vision gives it), with its head found by
    /// Vision's animal pose detector. Used for the photo a scan saves of the user's dog;
    /// tools/find_dogs_in_photos.swift does the same for the reference photos.
    static func find(in image: CGImage, dog: CGRect?) -> PhotoFocus {
        func topLeft(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        }
        return PhotoFocus(dog: dog.map(topLeft), head: headBox(in: image, dog: dog).map(topLeft))
    }

    /// A square around the eyes, nose and ears the pose detector finds, a little bigger than
    /// they are, since they sit inside the head. Prefers the head inside `dog`.
    private static func headBox(in image: CGImage, dog: CGRect?) -> CGRect? {
        let request = VNDetectAnimalBodyPoseRequest()
        guard (try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])) != nil else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let heads: [CGRect] = (request.results ?? []).compactMap { pose in
            let points = ((try? pose.recognizedPoints(.head)) ?? [:]).values.filter { $0.confidence > 0.2 }
            guard points.count >= 2 else { return nil }
            let xs = points.map(\.location.x), ys = points.map(\.location.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            // Normalized units differ on the two axes, so size the square in pixels.
            let side = max(max((maxX - minX) * width, (maxY - minY) * height) * 1.6, min(width, height) * 0.12)
            return CGRect(x: (minX + maxX) / 2 - side / 2 / width, y: (minY + maxY) / 2 - side / 2 / height,
                          width: side / width, height: side / height)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let dog else { return heads.first }
        return heads.first { dog.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? heads.first
    }
}
