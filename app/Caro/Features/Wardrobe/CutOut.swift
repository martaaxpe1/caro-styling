import CoreImage
import UIKit
import Vision

/// Gets a photo ready to send: upright and resized, then cut out on the iPhone (PRD section 8).
///
/// The cut-out uses Vision, Apple's framework for looking at images on the iPhone. Its
/// "foreground instance mask" is the same feature as touching and holding a subject in Photos:
/// it finds the piece and lifts it off its background. No AI service, no cost, no connection.
/// When nothing lifts, there is no cut-out: the piece keeps its photo, shown on the tile colour.
///
/// This is heavy work, so it runs away from the main thread (@concurrent), and the screen
/// stays smooth while photos are cut out.
enum PhotoPrep {
    /// The photo sent to the server: at most 2000 pixels on the long side (PRD section 8).
    nonisolated static let photoSide: CGFloat = 2000
    /// The cut-out: a little smaller, as it is only ever shown on the iPhone's screen.
    nonisolated static let cutoutSide: CGFloat = 1600
    /// The small picture on the adding screen's tiles.
    nonisolated static let previewSide: CGFloat = 500

    /// A photo ready to send.
    nonisolated struct Prepared: Sendable {
        /// The photo as JPEG. Drawn again from its pixels, so it carries no location or camera notes.
        let photo: Data
        /// The cut-out as PNG, which keeps the transparent background. Empty when nothing lifted.
        let cutout: Data?
        /// For the tile: the cut-out, or the photo.
        let preview: UIImage
    }

    /// Makes the photo, the cut-out and the preview. Nil if the picture cannot be read.
    @concurrent nonisolated static func prepare(_ image: UIImage) async -> Prepared? {
        guard let upright = resized(image, maxSide: photoSide, opaque: true),
              let photo = upright.jpegData(compressionQuality: 0.85)
        else { return nil }

        let lifted = cutOut(upright).flatMap { resized($0, maxSide: cutoutSide, opaque: false) }
        let preview = resized(lifted ?? upright, maxSide: previewSide, opaque: lifted == nil) ?? upright
        return Prepared(photo: photo, cutout: lifted?.pngData(), preview: preview)
    }

    /// Prepares a photo from its file (the photo library hands over files).
    @concurrent nonisolated static func prepare(data: Data) async -> Prepared? {
        guard let image = UIImage(data: data) else { return nil }
        return await prepare(image)
    }

    /// The photo upright (the way the camera held it) and no bigger than maxSide pixels.
    nonisolated static func resized(_ image: UIImage, maxSide: CGFloat, opaque: Bool) -> UIImage? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width > 0, height > 0 else { return nil }
        let factor = min(1, maxSide / max(width, height))
        let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The iPhone's own subject lifting. Every subject it finds is kept (a pair of shoes is two),
    /// cropped to the piece. Nil when nothing lifts.
    nonisolated static func cutOut(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let lifted = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(lifted, from: lifted.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            // The Simulator often cannot run it: then the photo is kept, as when nothing lifts.
            return nil
        }
    }
}
