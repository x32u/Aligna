import Foundation
import UIKit

enum AvatarImageProcessor {
    static let maximumPixelDimension: CGFloat = 512
    static let maximumByteCount = 2 * 1_024 * 1_024

    static func jpegData(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw AvatarImageError.invalidImage
        }

        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maximumPixelDimension / max(longestSide, 1))
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        for quality in stride(from: 0.82, through: 0.42, by: -0.1) {
            if let encoded = resized.jpegData(
                compressionQuality: quality
            ), encoded.count <= maximumByteCount {
                return encoded
            }
        }
        throw AvatarImageError.tooLarge
    }
}

enum AvatarImageError: LocalizedError {
    case invalidImage
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected photo could not be read."
        case .tooLarge:
            "The avatar is still larger than 2 MB after resizing."
        }
    }
}
