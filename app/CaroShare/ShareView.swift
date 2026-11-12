import SwiftUI

/// The small Caro screen in the share sheet: what was shared (the image, or the Pinterest link),
/// a note if you like, and Add. Then "Added to Get the look." and Done.
struct ShareView: View {
    let shared: SharedItem
    let done: () -> Void
    let cancel: () -> Void

    private enum Stage: Equatable {
        case reading, ready, sending, added
        case failed(String)
    }

    @State private var stage = Stage.reading
    @State private var photo: Data?
    @State private var link: String?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("Caro").caroLabelStyle()
                HStack {
                    if stage != .added {
                        Button("Cancel", action: cancel)
                            .font(.caroButton)
                            .foregroundStyle(Color.ink)
                            .frame(minHeight: CaroLayout.minTouchTarget)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: CaroLayout.minTouchTarget)
            .padding(.horizontal, CaroLayout.pageMargin)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(stage == .added ? "Added to \(Text("Get the look").italic())" : "Add to \(Text("Get the look").italic())")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()

                    preview

                    switch stage {
                    case .reading:
                        ProgressView()
                    case .added:
                        Text("Caro is reading it now. Open Caro to see your version.")
                            .font(.caroBody)
                            .foregroundStyle(Color.muted)
                    case .failed(let message):
                        Text(message)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                    case .ready, .sending:
                        if photo != nil || link != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Note").caroLabelStyle()
                                TextField("Why you like it, if you want", text: $note, axis: .vertical)
                                    .font(.caroBody)
                                    .lineLimit(1...3)
                                    .padding(.bottom, 6)
                                    .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 1) }
                            }
                        }
                    }
                }
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .safeAreaInset(edge: .bottom) {
            bottomButton
                .bottomButtonBar()
        }
        .task { await read() }
    }

    @ViewBuilder
    private var preview: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 300)
                .background(Color.photo)
                .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        } else if let link {
            VStack(alignment: .leading, spacing: 4) {
                Text(isPinterest(link) ? "A Pinterest pin" : "A link")
                    .font(.caroRowTitle)
                Text(link)
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
                    .lineLimit(2)
                Text(isPinterest(link) ? "Caro takes the image from the pin." : "Caro can take the image only from a Pinterest link. Save the image to Photos and share it from there.")
                    .font(.caroMeta)
                    .foregroundStyle(isPinterest(link) ? Color.muted : Color.terracotta)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        switch stage {
        case .added:
            Button("Done", action: done).buttonStyle(.pill)
        case .failed:
            Button("Try again") { Task { await send() } }
                .buttonStyle(.pill)
                .disabled(photo == nil && link == nil)
        default:
            Button(stage == .sending ? "Adding" : "Add") { Task { await send() } }
                .buttonStyle(.pill)
                .disabled(stage != .ready || !canSend)
        }
    }

    private var canSend: Bool {
        photo != nil || (link.map(isPinterest) ?? false)
    }

    private func isPinterest(_ link: String) -> Bool {
        guard let host = URL(string: link)?.host()?.lowercased() else { return false }
        return host == "pin.it" || host.contains("pinterest.")
    }

    private func read() async {
        photo = await shared.image()
        link = await shared.link()
        if photo == nil && link == nil {
            stage = .failed("Caro found no image to add. Share an image, or a Pinterest pin.")
        } else if Keychain.readToken() == nil {
            stage = .failed(ShareUpload.signIn)
        } else {
            stage = .ready
        }
    }

    private func send() async {
        stage = .sending
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = await ShareUpload.send(photo: photo, link: link, note: note.isEmpty ? nil : note) {
            stage = .failed(message)
        } else {
            stage = .added
        }
    }
}
