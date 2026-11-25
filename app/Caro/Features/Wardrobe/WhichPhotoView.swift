import SwiftUI
import UIKit

/// Which of a piece's two photos to keep.
enum PhotoChoice: String {
    case old, new
}

/// One of the two photos on Which photo?: from the server, or just taken.
struct ComparePhoto: Identifiable {
    /// "In the edit", "Waiting for review" or "New".
    let title: String
    /// The server's address, for a photo that is already there.
    var path: String?
    /// A photo just taken or chosen, still on the iPhone.
    var image: UIImage?
    let isCutout: Bool

    var id: String { title }
}

/// S12, Which photo? (designed here, T14): the two photos of one piece side by side, the same size,
/// as the edit shows them, and which one to keep. Caro does not pick: both buttons weigh the same.
/// Tap a photo to see it large. Closing decides nothing.
///
/// Used for Same piece in the review, and for Retake on a piece's page.
struct WhichPhotoView: View {
    let name: String
    let old: ComparePhoto
    let new: ComparePhoto
    /// Only from the review: comparing can show that it is another piece after all.
    var different: (() -> Void)?
    /// Keeps the chosen photo. Answers with a message when it did not work.
    let choose: (PhotoChoice) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var zoomed: ComparePhoto?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Which \(Text("photo").italic())?")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()
                    Text(name)
                        .font(.caroBody)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 4)

                    // Side by side; under each other when the text is very large.
                    let layout = typeSize >= .xxxLarge
                        ? AnyLayout(VStackLayout(spacing: 24))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        side(old, button: "Keep the old photo", choice: .old)
                        side(new, button: "Use the new photo", choice: .new)
                    }
                    .padding(.top, 18)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 12)
                    }

                    if let different {
                        Button("Different piece") {
                            dismiss()
                            different()
                        }
                        .font(.caroLink)
                        .foregroundStyle(Color.terracotta)
                        .underline()
                        .frame(minHeight: CaroLayout.minTouchTarget)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .disabled(saving)
                    }
                }
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .foregroundStyle(Color.ink)
            .background(Color.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.caroButton)
                        .disabled(saving)
                }
            }
        }
        .tint(Color.ink)
        .interactiveDismissDisabled(saving)
        .fullScreenCover(item: $zoomed) { photo in
            ZoomPhotos(photos: [old, new], shown: photo.id)
        }
    }

    private func side(_ photo: ComparePhoto, button: String, choice: PhotoChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                zoomed = photo
            } label: {
                RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                    .fill(Color.tile)
                    .aspectRatio(typeSize >= .xxxLarge ? 1.2 : 0.82, contentMode: .fit)
                    .overlay {
                        picture(photo)
                            .padding(photo.isCutout ? 12 : 8)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.ink)
                            .frame(width: 28, height: 28)
                            .background(Color.paper, in: Circle())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.title)
            .accessibilityHint("Shows it large")

            Text(photo.title)
                .font(.caroNote)
                .foregroundStyle(Color.muted)

            Button(button) {
                Task { await keep(choice) }
            }
            .buttonStyle(.pillOutlined)
            .disabled(saving)
        }
    }

    @ViewBuilder
    private func picture(_ photo: ComparePhoto) -> some View {
        if let image = photo.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            PieceImage(path: photo.path, isCutout: photo.isCutout, shadow: .none)
        }
    }

    private func keep(_ choice: PhotoChoice) async {
        saving = true
        defer { saving = false }
        errorMessage = nil
        if let message = await choose(choice) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}
