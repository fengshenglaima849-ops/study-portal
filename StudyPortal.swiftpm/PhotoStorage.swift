import UIKit

/// ウィジェットに飾る写真の置き場所
enum PhotoSlot: String {
    case square, wide
}

enum PhotoStorage {
    private static func url(_ slot: PhotoSlot) -> URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("photo-\(slot.rawValue).jpg")
    }

    static func load(_ slot: PhotoSlot) -> UIImage? {
        guard let url = url(slot), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 大きすぎる写真は縮めてから保存する
    static func save(_ data: Data, slot: PhotoSlot) -> UIImage? {
        guard let original = UIImage(data: data), original.size.width > 0, original.size.height > 0 else { return nil }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(original.size.width, original.size.height))
        let target = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            original.draw(in: CGRect(origin: .zero, size: target))
        }
        if let url = url(slot), let jpeg = image.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: url)
        }
        return image
    }
}
