import SwiftUI

/// S4 Occasions, onboarding step 5 (to design, added in T4): the member's own occasions.
/// Caro proposes four, explained. The member keeps the ones that fit, edits any (name and the
/// line under it), removes any or adds their own, one to eight. Numbered like the chapters of
/// the edit. Nothing is saved until Continue (onboarding, which finishes set-up) or Save (Settings).
struct OccasionsView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 5
    /// Runs after a save in Settings. In onboarding, the app moves on by itself.
    var onDone: () -> Void = {}

    @Environment(SetupStore.self) private var store

    @State private var occasions: [Occasion] = []
    @State private var started = false
    @State private var newName = ""
    /// The last occasion added on this screen, for the "Travel added." line.
    @State private var addedName: String?
    @State private var editing: Int?
    @State private var editName = ""
    @State private var editLine = ""
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var showingSaved = false
    @FocusState private var fieldFocused: Bool

    /// The Looks screen shows occasions as a row of words, so a member keeps at most eight.
    static let maximum = 8
    static let maximumLength = 30
    static let maximumLineLength = 80

    private var isOnboarding: Bool { step != nil }
    private var proposals: [Occasion] { store.setup?.proposedOccasions ?? [] }
    private var isFull: Bool { occasions.count >= Self.maximum }
    private var typedName: String { newName.trimmingCharacters(in: .whitespaces) }

    /// Caro's proposals the member removed, to add back with one tap.
    private var suggestions: [Occasion] {
        proposals.filter { proposal in !occasions.contains { same($0.name, proposal.name) } }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your \(Text("occasions").italic())")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()

                    Text("Caro sorts your pieces and looks by occasion. Start from these four: keep the ones that fit your life, rename any, or add your own.")
                        .font(.caroBody)
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                        .padding(.top, 10)

                    list
                        .padding(.top, 24)

                    if isFull {
                        Text("Up to eight occasions.")
                            .font(.caroNote)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 16)
                    } else {
                        addField
                            .id("addField")
                            .padding(.top, 16)

                        if let errorMessage {
                            note(errorMessage, colour: .terracotta)
                        } else if let addedName {
                            note("\(addedName) added.", colour: .muted)
                        }

                        if !suggestions.isEmpty {
                            suggestionChips
                                .padding(.top, 14)
                        }
                    }

                    if isFull, let errorMessage {
                        note(errorMessage, colour: .terracotta)
                    }

                    Text("You give each piece and each look its occasions. Caro never chooses them for you.")
                        .font(.caroBody)
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                        .padding(.top, 24)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tapping the field brings it above the keyboard, also with a long list.
            .onChange(of: fieldFocused) {
                if fieldFocused {
                    withAnimation { proxy.scrollTo("addField", anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(isOnboarding ? "Continue" : "Save") {
                Task { await save() }
            }
            .buttonStyle(.pill)
            .disabled(occasions.isEmpty && typedName.isEmpty || saving)
            .bottomButtonBar()
        }
        .onboardingStep(step)
        .alert("Edit \(editing.map { occasions[$0].name } ?? "occasion")", isPresented: isEditing) {
            TextField("Name", text: $editName)
                .textInputAutocapitalization(.sentences)
            TextField("A short line, if you like", text: $editLine)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) {}
            Button("Done") { applyEdit() }
        } message: {
            Text("The line shows under the name.")
        }
        // Settings only: a centred confirmation, then back to Settings.
        .alert("Occasions saved", isPresented: $showingSaved) {
            Button("OK") { onDone() }
        } message: {
            Text(occasions.map(\.name).joined(separator: ", "))
        }
        .onAppear {
            guard !started else { return }
            started = true
            occasions = store.setup?.occasions ?? []
        }
    }

    // MARK: Parts

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(occasions.indices, id: \.self) { index in
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caroChapterNumber)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(occasions[index].name)
                                .font(.caroChapterName)
                            if let line = occasions[index].description {
                                Text(line)
                                    .font(.caroBody)
                                    .foregroundStyle(Color.muted)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 4)

                    Button {
                        editName = occasions[index].name
                        editLine = occasions[index].description ?? ""
                        editing = index
                    } label: {
                        icon("pencil")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(occasions[index].name)")

                    // At least one occasion: the last one cannot be removed.
                    if occasions.count > 1 {
                        Button {
                            remove(at: index)
                        } label: {
                            icon("xmark", size: 14)
                                .foregroundStyle(Color.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(occasions[index].name)")
                    }
                }
                .padding(.vertical, 14)
                .frame(minHeight: 80)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    private func icon(_ name: String, size: CGFloat = 17) -> some View {
        Image(systemName: name)
            .iconFont(size, weight: .light)
            .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
            .contentShape(Rectangle())
    }

    /// "+ Add an occasion", like the store field. Return or Add puts it in the list.
    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .iconFont(17, weight: .light)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            TextField("Add an occasion", text: $newName, prompt: fieldPrompt("Add an occasion"))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { add(newName) }
                .onChange(of: newName) {
                    errorMessage = nil
                    addedName = nil
                }
            if !typedName.isEmpty {
                Button("Add") { add(newName) }
                    .font(.caroLink)
                    .foregroundStyle(Color.ink)
            }
        }
        .underlinedField()
    }

    private func note(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.caroNote)
            .foregroundStyle(colour)
            .padding(.top, 10)
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add back")
                .caroLabelStyle()
            // Wraps onto a second line when the names are long.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 4) { chips }
            }
        }
    }

    private var chips: some View {
        ForEach(suggestions, id: \.name) { proposal in
            Chip(title: proposal.name, isOn: false) {
                add(proposal.name)
            }
            .accessibilityLabel("Add \(proposal.name) back")
        }
    }

    // MARK: Changes, kept on the phone until Continue or Save

    private func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    /// Puts an occasion in the list. Returns false, with a message, when it cannot.
    @discardableResult
    private func add(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if isFull {
            errorMessage = "Up to eight occasions."
            return false
        }
        if trimmed.count > Self.maximumLength {
            errorMessage = "Keep occasion names to 30 letters."
            return false
        }
        if occasions.contains(where: { same($0.name, trimmed) }) {
            errorMessage = "\(trimmed) is already in your occasions."
            return false
        }
        // One of Caro's four comes back with its line.
        let proposal = proposals.first { same($0.name, trimmed) }
        let added = Occasion(id: nil, name: proposal?.name ?? trimmed, description: proposal?.description)
        occasions.append(added)
        newName = ""
        errorMessage = nil
        addedName = added.name
        return true
    }

    private func remove(at index: Int) {
        guard occasions.count > 1, occasions.indices.contains(index) else { return }
        occasions.remove(at: index)
        errorMessage = nil
        addedName = nil
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    /// A new name keeps the line under it, unless the member changes the line too.
    private func applyEdit() {
        guard let index = editing, occasions.indices.contains(index) else { return }
        let name = editName.trimmingCharacters(in: .whitespaces)
        let line = editLine.trimmingCharacters(in: .whitespaces)
        let taken = occasions.indices.contains { $0 != index && same(occasions[$0].name, name) }
        if name.isEmpty {
            errorMessage = "Every occasion needs a name."
        } else if name.count > Self.maximumLength {
            errorMessage = "Keep occasion names to 30 letters."
        } else if line.count > Self.maximumLineLength {
            errorMessage = "Keep the line under an occasion to 80 letters."
        } else if taken {
            errorMessage = "\(name) is already in your occasions."
        } else {
            occasions[index].name = name
            occasions[index].description = line.isEmpty ? nil : line
            errorMessage = nil
        }
    }

    // MARK: Server

    private func save() async {
        guard !saving else { return }
        // An occasion still in the field is added first, so typing and pressing Save keeps it.
        guard add(newName), !occasions.isEmpty else { return }

        saving = true
        defer { saving = false }
        let list = occasions
        if let failed = await store.save({ try await $0.saveOccasions(list) }) {
            errorMessage = failed
        } else if isOnboarding {
            onDone()
        } else {
            showingSaved = true
        }
    }
}
