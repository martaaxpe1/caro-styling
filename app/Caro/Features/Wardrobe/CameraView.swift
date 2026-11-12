import AVFoundation
import SwiftUI
import UIKit

/// Take photos: the iPhone's own camera (UIImagePickerController), with a bar of Caro's own
/// instead of the usual controls (to design, added in T5): Done, the shutter, and how many
/// photos were taken. Hiding the usual controls is Apple's way of taking several photos
/// without leaving the camera. Each photo goes into the line at once, so cutting out and
/// reading start while the member keeps photographing.
///
/// The camera is a UIKit screen, so its bar is built from plain UIKit buttons (CameraBarView),
/// laid on the camera in a see-through layer that only covers the bottom.
struct CameraView: UIViewControllerRepresentable {
    /// Retake takes one photo and closes; adding pieces takes as many as the member likes.
    var single = false
    /// Each photo, upright and resized, as a JPEG file.
    let took: (Data) -> Void
    /// Done, with how many photos were taken.
    let done: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.delegate = context.coordinator

        let coordinator = context.coordinator
        coordinator.picker = picker

        // The camera stretches its overlay over the whole screen. So the overlay is a see-through
        // layer, and Caro's bar sits in it, pinned to the bottom: the camera's picture shows above.
        let screen = UIScreen.main.bounds
        let overlay = PassThroughView(frame: screen)
        overlay.backgroundColor = .clear
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let bar = CameraBarView(
            frame: CGRect(x: 0, y: screen.height - CameraBarView.height, width: screen.width, height: CameraBarView.height),
            doneTitle: single ? "Cancel" : "Done"
        )
        bar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        bar.doneButton.addAction(UIAction { [weak coordinator] _ in coordinator?.finish() }, for: .touchUpInside)
        bar.shutterButton.addAction(UIAction { [weak coordinator] _ in coordinator?.shutter() }, for: .touchUpInside)
        overlay.addSubview(bar)
        coordinator.bar = bar
        picker.cameraOverlayView = overlay

        // The camera's picture is 4 by 3 at the top of the screen: move it down, between the
        // top of the screen and Caro's bar.
        let previewHeight = screen.width * 4 / 3
        let space = screen.height - CameraBarView.height - previewHeight
        picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: max(space / 2, 0))
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        weak var picker: UIImagePickerController?
        weak var bar: CameraBarView?
        private var count = 0
        private var last: UIImage?
        private var busy = false {
            didSet { showOnBar() }
        }

        init(parent: CameraView) {
            self.parent = parent
        }

        func shutter() {
            guard !busy else { return }
            busy = true
            bar?.flashShutter()
            picker?.takePicture()
            // If the camera never answers (it happens when it is still starting), the shutter
            // works again after a moment.
            Task {
                try? await Task.sleep(for: .seconds(3))
                busy = false
            }
        }

        func finish() {
            parent.done(count)
        }

        private func showOnBar() {
            bar?.update(count: count, last: last, busy: busy)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                busy = false
                return
            }
            Task {
                // Made small at once, so many photos in a row do not fill the iPhone's memory.
                let file = await PhotoPrep.photoFile(from: image)
                guard let file else {
                    busy = false
                    return
                }
                count += 1
                last = PhotoPrep.resized(image, maxSide: 200, opaque: true)
                busy = false
                parent.took(file)
                if parent.single {
                    finish()
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish()
        }
    }
}

/// Caro's camera bar at the bottom of the camera: ink, with Done on the left, the shutter in the
/// middle and the last photo with the count on the right.
final class CameraBarView: UIView {
    static let height: CGFloat = 170

    let doneButton = UIButton(type: .system)
    let shutterButton = UIButton(type: .custom)
    private let countLabel = UILabel()
    private let lastPhoto = UIImageView()

    init(frame: CGRect, doneTitle: String) {
        super.init(frame: frame)
        backgroundColor = UIColor(Color.ink)
        let onInk = UIColor(Color.onInk)
        let font = Self.inter(15, weight: .medium)

        doneButton.setTitle(doneTitle, for: .normal)
        doneButton.setTitleColor(onInk, for: .normal)
        doneButton.titleLabel?.font = font
        doneButton.contentHorizontalAlignment = .leading

        // The shutter: a filled circle inside a ring.
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 69, height: 69)).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = onInk.cgColor
        ring.lineWidth = 3
        let dot = CAShapeLayer()
        dot.path = UIBezierPath(ovalIn: CGRect(x: 7, y: 7, width: 58, height: 58)).cgPath
        dot.fillColor = onInk.cgColor
        shutterButton.layer.addSublayer(ring)
        shutterButton.layer.addSublayer(dot)
        shutterButton.accessibilityLabel = "Take photo"

        countLabel.textColor = onInk
        countLabel.font = font
        lastPhoto.contentMode = .scaleAspectFill
        lastPhoto.clipsToBounds = true
        lastPhoto.layer.cornerRadius = CaroLayout.tileRadius
        lastPhoto.isAccessibilityElement = false

        for view in [doneButton, shutterButton, countLabel, lastPhoto] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            shutterButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            doneButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CaroLayout.pageMargin),
            doneButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: CaroLayout.minTouchTarget),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CaroLayout.pageMargin),
            countLabel.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            lastPhoto.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -8),
            lastPhoto.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            lastPhoto.widthAnchor.constraint(equalToConstant: 40),
            lastPhoto.heightAnchor.constraint(equalToConstant: 40),
        ])
        update(count: 0, last: nil, busy: false)
    }

    required init?(coder: NSCoder) {
        fatalError("CameraBarView is made in code.")
    }

    func update(count: Int, last: UIImage?, busy: Bool) {
        countLabel.text = count > 0 ? "\(count)" : nil
        countLabel.accessibilityLabel = count == 1 ? "1 photo taken" : "\(count) photos taken"
        lastPhoto.image = last
        lastPhoto.isHidden = last == nil
        shutterButton.isEnabled = !busy
        shutterButton.alpha = busy ? 0.5 : 1
    }

    /// A short press of the shutter, so the member sees the photo was taken.
    func flashShutter() {
        UIView.animate(withDuration: 0.08, animations: {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) { self.shutterButton.transform = .identity }
        })
    }

    /// Inter, the app's text font, at a weight.
    private static func inter(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Inter",
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// A see-through layer: touches on it go to whatever is under it; only its own content
/// (Caro's bar) takes them.
final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// The camera needs the member's yes, asked once by the iPhone with the line from Info.plist.
enum CameraAccess {
    enum Answer { case allowed, refused, noCamera }

    static func ask() async -> Answer {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .allowed
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .allowed : .refused
        default:
            return .refused
        }
    }
}

extension PhotoPrep {
    /// A photo from the camera as a JPEG file: upright, at most 2000 pixels.
    @concurrent nonisolated static func photoFile(from image: UIImage) async -> Data? {
        resized(image, maxSide: photoSide, opaque: true)?.jpegData(compressionQuality: 0.9)
    }
}
