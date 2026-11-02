import CoreGraphics

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

    /// The part of a photo of `size` to show in a frame shaped `aspectRatio` (width ÷
    /// height): the whole dog with a little room around it when it fits; otherwise as much
    /// of the dog as fits, keeping its head in view. Without the dog's outline, the biggest
    /// crop, around its head if Vision found that, or else the middle.
    func crop(of size: CGSize, aspectRatio: CGFloat) -> CGRect {
        // The biggest frame-shaped crop the photo has room for.
        let largest = size.width / size.height > aspectRatio
            ? CGSize(width: size.height * aspectRatio, height: size.height)
            : CGSize(width: size.width, height: size.width / aspectRatio)
        func inPixels(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                   width: rect.width * size.width, height: rect.height * size.height)
        }
        let head = self.head.map(inPixels)
        guard let subject = dog.map(inPixels) else {
            // Zooming in on just a head gives a blurry close-up of fur, so only slide the crop.
            let center = head.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
            return CGRect(x: min(max(center.x - largest.width / 2, 0), size.width - largest.width),
                          y: min(max(center.y - largest.height / 2, 0), size.height - largest.height),
                          width: largest.width, height: largest.height)
        }

        // The detector's outline sometimes stops short of an ear or the nose, so count the
        // head as part of the dog.
        let padded = subject.insetBy(dx: -subject.width * Self.margin, dy: -subject.height * Self.margin)
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
