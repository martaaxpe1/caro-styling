import SwiftUI

/// The inspiration as large as the page allows, with a numbered ink pin on each piece Caro
/// described (screen 15). Claude gives each piece's centre in percent of the photo, so the pins
/// are placed on the photo itself, wherever it sits in its frame.
///
/// The whole photo is shown, never cropped, on the photo colour. A very tall photo is limited
/// to a little taller than it is wide, so the credits stay near.
struct InspirationPhoto: View {
    let path: String
    let pins: [InspirationPiece]
    /// "Saved from Pinterest"
    var caption: String?

    @State private var image: UIImage?

    /// Width over height: no taller than this.
    private static let tallest: CGFloat = 0.8

    private var ratio: CGFloat {
        guard let image, image.size.height > 0 else { return 0.9 }
        return max(image.size.width / image.size.height, Self.tallest)
    }

    var body: some View {
        GeometryReader { geo in
            let frame = fitted(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.photo
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                ForEach(pins.filter { $0.pin != nil }) { piece in
                    pin(piece.number)
                        .position(
                            x: clamp(frame.minX + frame.width * piece.pin!.x / 100, frame.minX + 14, frame.maxX - 14),
                            y: clamp(frame.minY + frame.height * piece.pin!.y / 100, frame.minY + 14, frame.maxY - 14)
                        )
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            if let caption {
                Text(caption)
                    .font(.text(11, relativeTo: .caption))
                    .tracking(11 * 0.08)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 2))
                    .padding(12)
            }
        }
        .task(id: path) {
            image = await ImageCache.shared.image(for: path)
        }
        .accessibilityElement()
        .accessibilityLabel("Inspiration photo with \(pins.count) numbered pieces")
    }

    private func pin(_ number: Int) -> some View {
        Text("\(number)")
            .font(.text(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color.onInk)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.ink))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// Where the photo sits inside its frame once scaled to fit.
    private func fitted(in size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}
