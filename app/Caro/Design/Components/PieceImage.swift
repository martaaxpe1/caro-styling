import SwiftUI

/// A piece's picture from the server: its cut-out, or its photo when nothing lifted.
/// Loaded with the session token by ImageCache, and kept on the iPhone.
/// Cut-outs get the soft shadow; a photo fills its tile instead.
struct PieceImage: View {
    /// The server's address for the picture, like /me/pieces/12/thumb?v=ab12.
    let path: String?
    /// True for a cut-out on a transparent background, false for a photo.
    var isCutout = true
    var shadow: Shadow = .small

    enum Shadow { case none, small, large }

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if isCutout {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .modifier(ShadowModifier(shadow: shadow))
                } else {
                    // The photo as it is, on the tile colour (T1's fallback when nothing lifted).
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            } else {
                Color.clear
            }
        }
        .task(id: path) {
            guard let path else { return }
            image = await ImageCache.shared.image(for: path)
        }
        .accessibilityHidden(true)
    }

    private struct ShadowModifier: ViewModifier {
        let shadow: Shadow

        func body(content: Content) -> some View {
            switch shadow {
            case .none: content
            case .small: content.smallShadow()
            case .large: content.cutOutShadow()
            }
        }
    }
}
