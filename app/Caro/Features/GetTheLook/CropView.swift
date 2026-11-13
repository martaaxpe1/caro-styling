import SwiftUI

/// Bought (T11, to design): the store's picture of the product, in a square frame. Drag it and
/// pinch it so the piece fills the frame (store pictures often show a person wearing it), then
/// Use this picture. The iPhone's own cut-out then lifts the piece, as for any new photo.
///
/// Opened as a sheet from Find it. `use` gets the cropped square; the sheet closes itself.
struct CropView: View {
    let imagePath: String
    let productName: String
    let use: (UIImage) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var frameSide: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Fit the piece in the frame. Caro cuts it out and adds it to your edit. When it arrives, retake it with your own photo.")
                    .font(.caroNote)
                    .foregroundStyle(Color.muted)

                GeometryReader { geometry in
                    let side = geometry.size.width
                    frame(side: side)
                }
                .aspectRatio(1, contentMode: .fit)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 8)
            .foregroundStyle(Color.ink)
            .background(Color.paper)
            .navigationTitle(productName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(Color.onInk) }
                        Text(saving ? "Adding to your edit" : "Use this picture")
                    }
                }
                .buttonStyle(.pill)
                .disabled(image == nil || saving)
                .bottomButtonBar()
            }
        }
        .task {
            image = await ImageCache.shared.image(for: imagePath)
            loadFailed = image == nil
        }
        .interactiveDismissDisabled(saving)
    }

    // MARK: The frame

    @ViewBuilder
    private func frame(side: CGFloat) -> some View {
        ZStack {
            Color.white
            if let image {
                let size = displayedSize(of: image, side: side)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .offset(offset)
            } else if loadFailed {
                Text("The store's picture did not load.")
                    .font(.caroNote)
                    .foregroundStyle(Color.muted)
            } else {
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = clamped(CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height), side: side)
                }
                .onEnded { _ in lastOffset = offset }
                .simultaneously(with:
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value.magnification, minScale), 6)
                            offset = clamped(offset, side: side)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            lastOffset = offset
                        }
                )
        )
        .accessibilityLabel("The store's picture. Drag to move it, pinch to zoom.")
        .onAppear { frameSide = side }
        .onChange(of: side) { _, new in frameSide = new }
    }

    /// Zoomed all the way out, the whole picture fits the frame (on white).
    private var minScale: CGFloat {
        guard let image, image.size.width > 0, image.size.height > 0 else { return 1 }
        return min(image.size.width, image.size.height) / max(image.size.width, image.size.height)
    }

    /// At scale 1 the picture fills the frame; smaller shows all of it.
    private func displayedSize(of image: UIImage, side: CGFloat) -> CGSize {
        let fill = side / min(image.size.width, image.size.height)
        return CGSize(width: image.size.width * fill * scale, height: image.size.height * fill * scale)
    }

    /// The picture never moves further than its own edge.
    private func clamped(_ proposed: CGSize, side: CGFloat) -> CGSize {
        guard let image else { return .zero }
        let size = displayedSize(of: image, side: side)
        let maxX = abs(size.width - side) / 2
        let maxY = abs(size.height - side) / 2
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }

    // MARK: Saving

    /// Draws what the frame shows into a square picture, on white.
    private func cropped(_ image: UIImage, side: CGFloat) -> UIImage {
        let output: CGFloat = 1600
        let factor = output / side
        let size = displayedSize(of: image, side: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: output, height: output))
            let rect = CGRect(
                x: (side / 2 + offset.width - size.width / 2) * factor,
                y: (side / 2 + offset.height - size.height / 2) * factor,
                width: size.width * factor,
                height: size.height * factor
            )
            image.draw(in: rect)
        }
    }

    private func save() async {
        guard let image else { return }
        // The frame's width on screen, which the offsets are measured in.
        let side = frameSide
        saving = true
        defer { saving = false }
        errorMessage = nil
        if let message = await use(cropped(image, side: side)) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}
