import PhotosUI
import SwiftUI

enum PhotoLoader {
    static let maxPhotos = 5

    /// Loads photos picked in PhotosPicker as upright CGImages, long side at most 1600 px.
    /// Photos that fail to load are skipped.
    static func images(from items: [PhotosPickerItem]) async -> [CGImage] {
        var images: [CGImage] = []
        for item in items.prefix(maxPhotos) {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let upright = upright(image)
            else { continue }
            images.append(upright)
        }
        return images
    }

    /// Photos store their rotation separately (EXIF orientation). A CGImage ignores it,
    /// so redraw the photo the right way up, shrinking it on the way.
    static func upright(_ image: UIImage, maxSide: CGFloat = 1600) -> CGImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
