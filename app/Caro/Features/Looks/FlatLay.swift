import SwiftUI

/// One piece lying in a flat lay: its slot and its picture.
struct FlatLayItem: Identifiable, Hashable {
    let id: Int
    let slot: Slot
    /// The server's address for the picture: the cut-out, or the photo when nothing lifted.
    let path: String?
    let isCutout: Bool
}

extension FlatLayItem {
    /// A piece of a saved look. `large` uses the cut-out, otherwise the small thumbnail.
    init(_ piece: Look.LookPiece, large: Bool = false) {
        self.init(
            id: piece.id,
            slot: Slot(rawValue: piece.slot) ?? .accessories,
            path: large ? piece.images.large : piece.images.thumb,
            isCutout: piece.hasCutout
        )
    }
}

/// The automatic flat lay (screen 12): each slot has its own place on the table, taken from the
/// design, so a look always lies the same way. No dragging (PRD section 8). Drawn at any size:
/// the styling table, a look's page, the tiles on Looks and on the piece page.
///
/// Places are worked out on the design's table of 390 by 362 points, then scaled to fit.
struct FlatLay: View {
    let items: [FlatLayItem]
    var shadow: PieceImage.Shadow = .small
    /// On the styling table: the chosen slot, drawn as a dashed spot while it is empty.
    var emptySlot: Slot?
    /// On the styling table: the piece the look started with gets a small tag.
    var startingPieceID: Int?
    /// On the styling table: tapping a piece chooses its slot.
    var onTap: ((FlatLayItem) -> Void)?

    static let table = CGSize(width: 390, height: 362)

    /// Where a piece lies: its top-left corner, its size (a square) and how much it is turned.
    struct Spot {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let turn: Double
    }

    var body: some View {
        GeometryReader { box in
            let scale = min(box.size.width / Self.table.width, box.size.height / Self.table.height)
            // Centred in the box.
            let dx = (box.size.width - Self.table.width * scale) / 2
            let dy = (box.size.height - Self.table.height * scale) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Self.layout(items), id: \.item.id) { placed in
                    let spot = placed.spot
                    PieceImage(path: placed.item.path, isCutout: placed.item.isCutout, shadow: shadow)
                        .frame(width: spot.size * scale, height: spot.size * scale)
                        .rotationEffect(.degrees(placed.item.isCutout ? spot.turn : 0))
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?(placed.item) }
                        .allowsHitTesting(onTap != nil)
                        .offset(x: dx + spot.x * scale, y: dy + spot.y * scale)
                }

                if let emptySlot, let rect = Self.dashedSpot(emptySlot, items: items) {
                    DashedSpot(title: emptySlot.title)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: dx + rect.minX * scale, y: dy + rect.minY * scale)
                        .allowsHitTesting(false)
                }

                if let startingPieceID, let start = Self.layout(items).first(where: { $0.item.id == startingPieceID }) {
                    StartingTag()
                        .offset(
                            x: dx + (start.spot.x + 22) * scale,
                            y: dy + min(start.spot.y + start.spot.size * 0.9, Self.table.height - 30) * scale
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .clipped()
    }

    // MARK: The arrangement

    /// The pieces in drawing order (the shirt under the coat, shoes and bag on top), each with
    /// its spot. The top and the dress move left when there is no outer layer.
    static func layout(_ items: [FlatLayItem]) -> [(item: FlatLayItem, spot: Spot)] {
        let slots = Set(items.map(\.slot))
        let hasOuter = slots.contains(.outerLayer)
        let order: [Slot] = [.top, .outerLayer, .bottom, .onePiece, .shoes, .bag, .accessories]
        var placed: [(item: FlatLayItem, spot: Spot)] = []
        var accessory = 0

        for slot in order {
            for item in items where item.slot == slot {
                let spot: Spot
                switch slot {
                case .outerLayer:
                    spot = Spot(x: 18, y: -2, size: 196, turn: -4)
                case .top:
                    spot = hasOuter ? Spot(x: 156, y: 2, size: 134, turn: 3) : Spot(x: 34, y: 4, size: 170, turn: -3)
                case .bottom:
                    spot = Spot(x: 192, y: 82, size: 176, turn: 2)
                case .onePiece:
                    spot = hasOuter || slots.contains(.top) ? Spot(x: 180, y: 6, size: 200, turn: 2) : Spot(x: 96, y: 4, size: 220, turn: 0)
                case .shoes:
                    spot = Spot(x: 214, y: 228, size: 130, turn: -6)
                case .bag:
                    spot = Spot(x: 30, y: 236, size: 112, turn: -4)
                case .accessories:
                    let spots = [
                        Spot(x: 150, y: 262, size: 84, turn: 6),
                        Spot(x: 132, y: 176, size: 70, turn: -8),
                        Spot(x: 306, y: 10, size: 72, turn: 5),
                        Spot(x: 318, y: 150, size: 62, turn: -4),
                    ]
                    spot = spots[accessory % spots.count]
                    accessory += 1
                }
                placed.append((item, spot))
            }
        }
        return placed
    }

    /// The dashed spot for an empty slot, on the table's own scale. Nil once the slot is filled
    /// (accessories always have room for one more).
    static func dashedSpot(_ slot: Slot, items: [FlatLayItem]) -> CGRect? {
        let slots = Set(items.map(\.slot))
        if slot != .accessories && slots.contains(slot) { return nil }
        switch slot {
        case .outerLayer: return CGRect(x: 40, y: 34, width: 140, height: 180)
        case .top: return slots.contains(.outerLayer) ? CGRect(x: 192, y: 24, width: 110, height: 120) : CGRect(x: 56, y: 26, width: 130, height: 140)
        case .bottom: return CGRect(x: 222, y: 112, width: 118, height: 150)
        case .onePiece: return CGRect(x: 214, y: 30, width: 130, height: 190)
        case .shoes: return CGRect(x: 210, y: 264, width: 138, height: 56)
        case .bag: return CGRect(x: 30, y: 236, width: 112, height: 84)
        case .accessories:
            let next = layout(items + [FlatLayItem(id: -1, slot: .accessories, path: nil, isCutout: true)]).last!.spot
            return CGRect(x: next.x + 8, y: next.y + 8, width: next.size - 16, height: next.size - 16)
        }
    }
}

/// An open slot on the table: a dashed outline in terracotta with the slot's name above it.
private struct DashedSpot: View {
    let title: String

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.terracotta, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.text(11, weight: .semibold, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .tracking(11 * 0.12)
                    .foregroundStyle(Color.terracottaOnTile)
                    .fixedSize()
                    .offset(x: 4, y: -20)
            }
            .accessibilityHidden(true)
    }
}

/// The small paper tag on the piece the look started with: "Your starting piece".
private struct StartingTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(Color.outline, lineWidth: 1)
                .frame(width: 5, height: 5)
            Text("Your starting piece")
                .font(.text(11, relativeTo: .caption2))
                .fixedSize()
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 4)
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .background(Color.tagPaper, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.tagEdge, lineWidth: 1))
        .shadow(color: Color.shadowBrown.opacity(0.12), radius: 2, y: 2)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}
