import SwiftUI

/// The sheets that change a piece's details in the review, one per row of screen 07.
/// Native iOS sheets with lists, in Caro's type and colours. Every choice comes from the fixed
/// lists the server sends, so it is always a word the server accepts.
enum DetailSheet: String, Identifiable {
    case category, colour, material, formality
    var id: String { rawValue }
}

struct DetailPicker: View {
    let sheet: DetailSheet
    let lists: PieceLists
    @Binding var details: PieceDetails
    /// Runs when the warmth changes, so the seasons can be proposed again.
    let warmthChanged: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch sheet {
                case .category: categories
                case .colour: colours
                case .material: materials
                case .formality: formality
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .font(.caroBody)
            .foregroundStyle(Color.ink)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.caroButton)
                }
            }
        }
        .tint(Color.ink)
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch sheet {
        case .category: "Category"
        case .colour: "Colour and pattern"
        case .material: "Material and warmth"
        case .formality: "Formality"
        }
    }

    // Kind by chapter: "Dresses and skirts", then dress, jumpsuit, skirt.
    private var categories: some View {
        ForEach(lists.chapters) { chapter in
            Section {
                ForEach(chapter.kinds) { kind in
                    choice(PieceWords.title(kind.name), isOn: details.kind == kind.name) {
                        details.kind = kind.name
                        dismiss()
                    }
                }
            } header: {
                header("\(ChapterWords.number(chapter.number)) \(ChapterWords.title(chapter.name))")
            }
        }
    }

    // Up to three colours, main colour first, in the order tapped. Then the pattern.
    private var colours: some View {
        Group {
            Section {
                ForEach(lists.colours, id: \.self) { colour in
                    Button {
                        toggle(colour)
                    } label: {
                        HStack(spacing: 10) {
                            ColourSwatch(colour: colour, size: 14)
                            Text(PieceWords.title(colour))
                            Spacer()
                            if let position = details.colours.firstIndex(of: colour) {
                                Text(position == 0 ? "Main" : "\(position + 1)")
                                    .font(.caroMeta)
                                    .foregroundStyle(Color.muted)
                                Image(systemName: "checkmark")
                                    .iconFont(13, weight: .semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.paper)
                    .disabled(details.colours.count >= 3 && !details.colours.contains(colour))
                }
            } header: {
                header("Colours, up to three, main first")
            }

            Section {
                ForEach(lists.patterns, id: \.self) { pattern in
                    choice(PieceWords.title(pattern), isOn: details.pattern == pattern) {
                        details.pattern = pattern
                    }
                }
            } header: {
                header("Pattern")
            }
        }
    }

    private var materials: some View {
        Group {
            Section {
                ForEach(lists.warmth, id: \.self) { warmth in
                    choice(PieceWords.title(warmth), isOn: details.warmth == warmth) {
                        details.warmth = warmth
                        warmthChanged(warmth)
                    }
                }
            } header: {
                header("Warmth")
            }

            Section {
                ForEach(lists.materials, id: \.self) { material in
                    choice(PieceWords.title(material), isOn: details.material == material) {
                        details.material = material
                    }
                }
            } header: {
                header("Material")
            }
        }
    }

    private var formality: some View {
        ForEach(lists.formality, id: \.self) { level in
            choice(PieceWords.title(level), isOn: details.formality == level) {
                details.formality = level
                dismiss()
            }
        }
    }

    private func toggle(_ colour: String) {
        if let index = details.colours.firstIndex(of: colour) {
            details.colours.remove(at: index)
        } else if details.colours.count < 3 {
            details.colours.append(colour)
        }
    }

    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .iconFont(13, weight: .semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.paper)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .caroLabelStyle()
    }
}
