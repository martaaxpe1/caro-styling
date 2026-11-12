import SwiftUI

/// The inspiration as large as the page allows, with a numbered terracotta pin on each piece Caro
/// described (screen 15). Claude gives each piece's centre in percent of the photo, so the pins
/// are placed on the photo itself, wherever it sits in its frame. Tapping a pin shows that piece
/// in a small see-through callout beside its pin, on the side with more room (the space beside
/// the picture too), like on a map. The pins stay on top, so each can be tapped. Tapping the
/// pin again, or the callout, closes it.
///
/// The whole photo is shown, never cropped, on the photo colour. A very tall photo is limited
/// to a little taller than it is wide, so the credits stay near.
struct InspirationPhoto: View {
    let path: String
    let pins: [InspirationPiece]
    /// "Saved from Pinterest"
    var caption: String?
    /// The number of the pin whose piece is shown.
    @Binding var selected: Int?

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
                // The callout first, so the pins stay on top of it and can always be tapped.
                if let number = selected, let piece = pins.first(where: { $0.number == number }), piece.pin != nil {
                    let at = point(piece, in: frame)
                    let width = min(Self.calloutWidth, geo.size.width - 16)
                    // On the side of the pin with more room: the space beside the picture too.
                    let right = at.x < geo.size.width / 2
                    card(piece)
                        .frame(width: width)
                        .position(
                            x: clamp(right ? at.x + 20 + width / 2 : at.x - 20 - width / 2, width / 2 + 8, geo.size.width - width / 2 - 8),
                            y: clamp(at.y, 44, geo.size.height - 44)
                        )
                        .transition(.opacity)
                        .id(number)
                }
                ForEach(pins.filter { $0.pin != nil }) { piece in
                    pin(piece)
                        .position(point(piece, in: frame))
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .overlay(alignment: .topLeading) {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspiration photo with \(pins.count) numbered pieces")
    }

    private static let calloutWidth: CGFloat = 210

    /// Where a piece's pin sits: its centre on the photo, kept inside the photo's edges.
    private func point(_ piece: InspirationPiece, in frame: CGRect) -> CGPoint {
        guard let pin = piece.pin else { return .zero }
        return CGPoint(
            x: clamp(frame.minX + frame.width * pin.x / 100, frame.minX + 14, frame.maxX - 14),
            y: clamp(frame.minY + frame.height * pin.y / 100, frame.minY + 14, frame.maxY - 14)
        )
    }

    /// A terracotta pin; the one shown is ink. 24 points, inside a 44 point tap area.
    private func pin(_ piece: InspirationPiece) -> some View {
        let on = selected == piece.number
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selected = on ? nil : piece.number }
        } label: {
            Text("\(piece.number)")
                .font(.text(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(Color.onInk)
                .frame(width: 24, height: 24)
                .background(Circle().fill(on ? Color.ink : Color.terracotta))
                .overlay(Circle().strokeBorder(Color.paper, lineWidth: 1.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityLabel("Piece \(piece.number), \(piece.description)")
    }

    /// The piece of a tapped pin: theirs, and yours for it, or that it is missing.
    private func card(_ piece: InspirationPiece) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selected = nil }
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let own = piece.piece {
                        PieceImage(path: own.images.thumb, isCutout: own.hasCutout)
                            .padding(4)
                            .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                    } else {
                        RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                            .strokeBorder(Color.terracotta, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.description)
                        .font(.text(13, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(piece.isMissing ? Color.terracotta : Color.ink)
                    Text(cardLine(piece))
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(8)
            // See-through, so the photo stays visible around it.
            .background(Color.paper.opacity(0.88), in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
            .shadow(color: Color.shadowBrown.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Closes it")
    }

    /// "Yours: navy wool trousers", "Close: black tank top", "Not in your wardrobe · key".
    private func cardLine(_ piece: InspirationPiece) -> String {
        guard let own = piece.piece?.name else {
            return piece.key ? "Not in your wardrobe · key" : "Not in your wardrobe"
        }
        let name = own.prefix(1).lowercased() + own.dropFirst()
        return piece.match == "close" ? "Close: \(name)" : "Yours: \(name)"
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
