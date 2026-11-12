import PhotosUI
import SwiftUI

/// One photo of you wearing a look: Take a photo or Choose from library, asked in a small menu
/// from the bottom of the screen (a confirmation dialog). Used by From a photo on Looks and by
/// Add a photo on a look's page.
///
/// The camera is the one adding pieces uses, taking one photo. The library is the iPhone's own
/// photo picker, one photo, no permission needed. Either way the photo is drawn again upright
/// and at most 2000 pixels as JPEG, so it carries no location or camera notes.
struct LookPhotoSource: ViewModifier {
    @Binding var isAsking: Bool
    let title: String
    let chosen: (Data) -> Void

    @State private var showingLibrary = false
    @State private var item: PhotosPickerItem?
    @State private var cameraOpen = false
    @State private var showingNoCamera = false
    @State private var showingCameraRefused = false
    @State private var showingUnreadable = false
    /// A photo from the camera, handed on once the camera has closed.
    @State private var taken: Data?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isAsking, titleVisibility: .visible) {
                Button("Take a photo") { Task { await openCamera() } }
                Button("Choose from library") { showingLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showingLibrary, selection: $item, matching: .images, preferredItemEncoding: .compatible)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task {
                    guard let data = try? await picked.loadTransferable(type: Data.self),
                          let photo = await Self.photoFile(from: data)
                    else {
                        showingUnreadable = true
                        return
                    }
                    // The next screen opens once the photo picker has finished closing: opened
                    // while it closes, a full-screen cover gets no room for the status bar.
                    try? await Task.sleep(for: .milliseconds(600))
                    chosen(photo)
                }
            }
            .fullScreenCover(isPresented: $cameraOpen, onDismiss: {
                // Handed on once the camera has closed, for the same reason as above.
                if let taken {
                    self.taken = nil
                    chosen(taken)
                }
            }) {
                CameraView(single: true) { file in
                    taken = file
                } done: { _ in
                    cameraOpen = false
                }
                .ignoresSafeArea()
            }
            .alert("No camera here", isPresented: $showingNoCamera) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This iPhone has no camera. Choose from library instead.")
            }
            .alert("Caro could not read this photo", isPresented: $showingUnreadable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try another one.")
            }
            .cameraRefusedAlert(isPresented: $showingCameraRefused)
    }

    private func openCamera() async {
        switch await CameraAccess.ask() {
        case .allowed: cameraOpen = true
        case .refused: showingCameraRefused = true
        case .noCamera: showingNoCamera = true
        }
    }

    /// A library photo as a JPEG file: upright, at most 2000 pixels.
    @concurrent nonisolated static func photoFile(from data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return PhotoPrep.resized(image, maxSide: PhotoPrep.photoSide, opaque: true)?.jpegData(compressionQuality: 0.9)
    }
}

extension View {
    func lookPhotoSource(isAsking: Binding<Bool>, title: String, chosen: @escaping (Data) -> Void) -> some View {
        modifier(LookPhotoSource(isAsking: isAsking, title: title, chosen: chosen))
    }
}
