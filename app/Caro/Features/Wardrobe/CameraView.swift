import AVFoundation
import SwiftUI
import UIKit

/// Take photos: the iPhone's own camera (UIImagePickerController), with a bar of Caro's own
/// instead of the usual controls (to design, added in T5): Done, the shutter, and how many
/// photos were taken. Hiding the usual controls is Apple's way of taking several photos
/// without leaving the camera. Each photo goes into the line at once, so cutting out and
/// reading start while the member keeps photographing.
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
        let bar = UIHostingController(rootView: CameraBar(model: coordinator.model, single: single) {
            coordinator.shutter()
        } done: {
            coordinator.finish()
        })
        bar.view.backgroundColor = .clear
        bar.view.frame = UIScreen.main.bounds
        coordinator.bar = bar
        // The bar's screen belongs to the camera's screen, so its buttons get the taps.
        picker.addChild(bar)
        picker.cameraOverlayView = bar.view
        bar.didMove(toParent: picker)

        // The camera's picture is 4 by 3 at the top of the screen: move it down, between the
        // top of the screen and Caro's bar.
        let screen = UIScreen.main.bounds
        let previewHeight = screen.width * 4 / 3
        let space = screen.height - CameraBar.height - previewHeight
        picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: max(space / 2, 0))
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    /// What the bar shows: the photos taken so far, and whether the camera is busy with one.
    @Observable
    final class Model {
        var count = 0
        var last: UIImage?
        var busy = false
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        let model = Model()
        weak var picker: UIImagePickerController?
        var bar: UIHostingController<CameraBar>?

        init(parent: CameraView) {
            self.parent = parent
        }

        func shutter() {
            guard !model.busy else { return }
            model.busy = true
            picker?.takePicture()
            // If the camera never answers (it happens when it is still starting), the shutter
            // works again after a moment.
            Task {
                try? await Task.sleep(for: .seconds(3))
                model.busy = false
            }
        }

        func finish() {
            parent.done(model.count)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                model.busy = false
                return
            }
            Task {
                // Made small at once, so many photos in a row do not fill the iPhone's memory.
                let file = await PhotoPrep.photoFile(from: image)
                model.busy = false
                guard let file else { return }
                model.count += 1
                model.last = PhotoPrep.resized(image, maxSide: 200, opaque: true)
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

/// Caro's camera bar: ink, with Done on the left, the shutter in the middle and the last photo
/// with the count on the right.
struct CameraBar: View {
    static let height: CGFloat = 170

    let model: CameraView.Model
    let single: Bool
    let shutter: () -> Void
    let done: () -> Void

    @State private var flash = false

    var body: some View {
        VStack(spacing: 0) {
            // The camera's picture shows through here.
            Color.clear
                .overlay {
                    Color.black.opacity(flash ? 0.6 : 0)
                        .allowsHitTesting(false)
                }

            HStack {
                Button(single ? "Cancel" : "Done", action: done)
                    .font(.caroButton)
                    .foregroundStyle(Color.onInk)
                    .frame(width: 80, height: 44, alignment: .leading)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.08)) { flash = true }
                    withAnimation(.easeIn(duration: 0.25).delay(0.08)) { flash = false }
                    shutter()
                } label: {
                    Circle()
                        .fill(Color.onInk)
                        .frame(width: 62, height: 62)
                        .padding(5)
                        .overlay(Circle().strokeBorder(Color.onInk, lineWidth: 3))
                        .opacity(model.busy ? 0.5 : 1)
                }
                .disabled(model.busy)
                .accessibilityLabel("Take photo")

                Spacer()

                HStack(spacing: 8) {
                    if let last = model.last {
                        Image(uiImage: last)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                    }
                    if model.count > 0 {
                        Text("\(model.count)")
                            .font(.caroButton)
                            .foregroundStyle(Color.onInk)
                            .accessibilityLabel(model.count == 1 ? "1 photo taken" : "\(model.count) photos taken")
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 24)
            .frame(height: Self.height)
            .background(Color.ink)
        }
        .ignoresSafeArea()
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
