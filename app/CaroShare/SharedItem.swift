import Foundation
import UIKit
import UniformTypeIdentifiers

/// What another app shared with Caro: the first image, and the first web link, from the
/// share sheet's items. The image is read when it is needed, not before.
struct SharedItem {
    var imageProvider: NSItemProvider?
    var linkProvider: NSItemProvider?
    var textProvider: NSItemProvider?

    static func from(_ items: [NSExtensionItem]) -> SharedItem {
        var shared = SharedItem()
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if shared.imageProvider == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                shared.imageProvider = provider
            } else if shared.linkProvider == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                shared.linkProvider = provider
            } else if shared.textProvider == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                shared.textProvider = provider
            }
        }
        return shared
    }

    /// The image as a JPEG: upright, at most 2000 pixels, so it carries no location or camera notes.
    func image() async -> Data? {
        guard let provider = imageProvider else { return nil }
        var image: UIImage?
        if let data = await Self.data(of: provider) {
            image = UIImage(data: data)
        }
        if image == nil, let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) {
            if let shared = item as? UIImage {
                image = shared
            } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            }
        }
        guard let image else { return nil }
        return Self.jpeg(image)
    }

    /// The web address shared: a link item, or the first link in shared text.
    func link() async -> String? {
        if let provider = linkProvider,
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
           url.scheme == "https" || url.scheme == "http" {
            return url.absoluteString
        }
        if let provider = textProvider,
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            if let url = match?.url, url.scheme == "https" || url.scheme == "http" {
                return url.absoluteString
            }
        }
        return nil
    }

    /// The image's bytes, as the sharing app gave them.
    private static func data(of provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Drawn again upright and at most 2000 pixels on the long side.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 2000 / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: 0.9)
    }
}
