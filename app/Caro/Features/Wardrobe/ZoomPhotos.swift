import SwiftUI
import UIKit

/// The photos of Which photo? (S12) large, one at a time: swipe to the other, pinch or double tap
/// to zoom. Opened by tapping a photo.
struct ZoomPhotos: View {
    let photos: [ComparePhoto]
    @State var shown: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $shown) {
                ForEach(photos) { photo in
                    ZoomPage(photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.tile)
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tile, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.caroButton)
                }
                ToolbarItem(placement: .principal) {
                    Text(photos.first { $0.id == shown }?.title ?? "")
                        .caroLabelStyle()
                }
            }
        }
        .tint(Color.ink)
    }
}

/// One photo that can be zoomed, loaded first when it comes from the server.
private struct ZoomPage: View {
    let photo: ComparePhoto
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = photo.image ?? loaded {
                ZoomableImage(image: image)
                    .accessibilityLabel("\(photo.title). Pinch to zoom.")
            } else if failed {
                Text("This photo did not load.")
                    .font(.caroNote)
                    .foregroundStyle(Color.muted)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard photo.image == nil, let path = photo.path else { return }
            loaded = await ImageCache.shared.image(for: path)
            failed = loaded == nil
        }
    }
}

/// The iPhone's own zooming view (UIScrollView): SwiftUI has no ready-made one.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView(image: image)
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {}
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var laidOutSize = CGSize.zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("Made in code only")
    }

    /// Zoomed out, the photo fits the page. Laid out again only when the page changes size, so
    /// zooming is not undone.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0 else { return }
        laidOutSize = bounds.size
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: bounds.size).insetBy(dx: 16, dy: 16)
        contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
