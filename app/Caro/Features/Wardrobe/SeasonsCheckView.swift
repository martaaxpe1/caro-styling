import SwiftUI

/// New seasons to check (designed here, PRD section 8). After the member changed the number of
/// their seasons, Caro proposed new ones for every piece from its warmth. This page shows them
/// in one batch, grouped by warmth: the pieces of each group and the seasons proposed for it.
/// Change a group's seasons, then Confirm seasons saves them all at once.
struct SeasonsCheckView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var check: SeasonsCheck?
    /// The seasons chosen for each group, starting from the proposal.
    @State private var chosen: [String: [Int]] = [:]
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your year changed")
                    .caroLabelStyle()

                Text("New \(Text("seasons").italic())")
                    .font(.caroPieceTitle)
                    .caroTitleTracking()
                    .padding(.top, 6)

                Text("Caro proposed seasons for your pieces from their warmth. Change any group, then confirm them all.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 8)

                if let check {
                    if check.groups.isEmpty {
                        Text("Nothing to check.")
                            .font(.caroBody)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 24)
                    }
                    ForEach(check.groups) { group in
                        groupView(group, seasons: check.seasons)
                    }
                } else if errorMessage == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let check, !check.groups.isEmpty {
                Button("Confirm seasons") {
                    Task { await confirm() }
                }
                .buttonStyle(.pill)
                .disabled(saving)
                .bottomButtonBar()
            }
        }
        .task { await load() }
    }

    private func groupView(_ group: SeasonsCheck.Group, seasons: [NamedItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(group.warmth))
                    .font(.caroSectionTitle)
                Spacer()
                Text(countText(group.pieces.count, "piece", "pieces"))
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }

            HStack(spacing: -12) {
                ForEach(group.pieces.prefix(8)) { piece in
                    PieceImage(path: piece.thumb, isCutout: piece.hasCutout)
                        .frame(width: 48, height: 48)
                }
                if group.pieces.count > 8 {
                    Text("+\(group.pieces.count - 8)")
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                        .padding(.leading, 20)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(group.pieces.compactMap(\.name).joined(separator: ", "))

            FlowLayout(spacing: 6) {
                ForEach(seasons) { season in
                    let isOn = chosen[group.warmth, default: []].contains(season.id)
                    Chip(title: season.name, isOn: isOn) {
                        if isOn {
                            chosen[group.warmth]?.removeAll { $0 == season.id }
                        } else {
                            chosen[group.warmth, default: []].append(season.id)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .padding(.top, 8)
    }

    private func title(_ warmth: String) -> String {
        warmth == "none" ? "Pieces with no warmth" : "\(PieceWords.title(warmth)) pieces"
    }

    private func load() async {
        do {
            let loaded = try await store.seasonsCheck()
            chosen = Dictionary(uniqueKeysWithValues: loaded.groups.map { ($0.warmth, $0.seasons) })
            check = loaded
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func confirm() async {
        saving = true
        defer { saving = false }
        do {
            try await store.confirmSeasons(chosen)
            dismiss()
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}
