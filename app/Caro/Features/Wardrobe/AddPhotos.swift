import PhotosUI
import SwiftUI

/// The two ways to add pieces: Take photos and Choose from library. Shared by screen 05 and
/// "Add more photos" on screen 06.
///
/// - Choose from library uses the iPhone's own photo picker (PhotosPicker). It runs outside
///   the app, so Caro only ever sees the photos you pick, and it needs no permission prompt.
/// - Take photos opens the camera. The iPhone asks for camera access the first time, with the
///   line from Info.plist (NSCameraUsageDescription).
struct AddPhotosSources: ViewModifier {
    @Binding var showingLibrary: Bool
    @Binding var showingCamera: Bool
    /// Runs once photos are in line, to show the adding screen.
    let added: () -> Void

    @Environment(WardrobeStore.self) private var store
    @State private var items: [PhotosPickerItem] = []
    @State private var cameraOpen = false
    @State private var showingNoCamera = false
    @State private var showingCameraRefused = false

    /// Up to 50 at a time, so a big first batch still goes smoothly.
    static let maximumAtOnce = 50

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingLibrary,
                selection: $items,
                maxSelectionCount: Self.maximumAtOnce,
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .compatible
            )
            .onChange(of: items) { _, chosen in
                guard !chosen.isEmpty else { return }
                store.add(chosen)
                items = []
                added()
            }
            .onChange(of: showingCamera) { _, wanted in
                guard wanted else { return }
                showingCamera = false
                Task { await openCamera() }
            }
            .fullScreenCover(isPresented: $cameraOpen) {
                CameraView { file in
                    store.add(photoFile: file)
                } done: { taken in
                    cameraOpen = false
                    if taken > 0 { added() }
                }
                .ignoresSafeArea()
            }
            .alert("No camera here", isPresented: $showingNoCamera) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This iPhone has no camera. Choose from library instead.")
            }
            .cameraRefusedAlert(isPresented: $showingCameraRefused)
    }

    /// The first time, the iPhone asks for camera access with Caro's line from Info.plist.
    private func openCamera() async {
        switch await CameraAccess.ask() {
        case .allowed: cameraOpen = true
        case .refused: showingCameraRefused = true
        case .noCamera: showingNoCamera = true
        }
    }
}

extension View {
    func addPhotosSources(library: Binding<Bool>, camera: Binding<Bool>, added: @escaping () -> Void) -> some View {
        modifier(AddPhotosSources(showingLibrary: library, showingCamera: camera, added: added))
    }
}

extension View {
    /// Camera access was refused: say so, with a way to the iPhone's Settings for Caro.
    func cameraRefusedAlert(isPresented: Binding<Bool>) -> some View {
        alert("Caro cannot use the camera", isPresented: isPresented) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow the camera for Caro in Settings, or choose from library instead.")
        }
    }
}
