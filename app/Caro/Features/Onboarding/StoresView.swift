import SwiftUI

/// Screen 04 Your stores, onboarding step 4: the sections you shop in, then the stores you
/// shop at. Type a store and press return: Caro finds its site for your country and shows it
/// to confirm with Add. Remove any. Skip for now is allowed: stores and sections are only
/// needed for the store search.
/// Added in T4 (PRD v1.1): the section chips above the store field.
struct StoresView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 4
    /// Runs after Continue or Skip for now, in onboarding.
    var onDone: () -> Void = {}

    @Environment(SetupStore.self) private var store

    @State private var sections = Sections(womens: false, mens: false, unisex: false)
    @State private var query = ""
    @State private var finding = false
    @State private var found: FoundStore?
    /// A store whose site is being found again, after the member moved country.
    @State private var replacing: Store?
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var started = false
    @FocusState private var fieldFocused: Bool

    private var isOnboarding: Bool { step != nil }
    private var country: String { store.setup?.place?.country ?? "US" }
    private var stores: [Store] { store.setup?.stores ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your \(Text("stores").italic())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text("Where you shop. Caro only searches these, only when you ask, on their \(PlaceFormats.site(country, plural: true)).")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                sectionChips
                    .padding(.top, 22)

                storeField
                    .padding(.top, 22)

                card
                    .padding(.top, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 10)
                }

                if !stores.isEmpty {
                    addedList
                        .padding(.top, 24)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        // In Settings everything here saves as it is changed, so only onboarding has buttons.
        .safeAreaInset(edge: .bottom) {
            if isOnboarding {
                VStack(spacing: 4) {
                    Button("Skip for now") {
                        Task { await skip() }
                    }
                    .font(.text(14, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: CaroLayout.minTouchTarget)
                    .disabled(saving)

                    Button("Continue") {
                        Task { await continueOn() }
                    }
                    .buttonStyle(.pill)
                    .disabled(!sections.any || saving)
                }
                .bottomButtonBar()
            }
        }
        .onboardingStep(step)
        .onAppear {
            guard !started else { return }
            started = true
            if let saved = store.setup?.sections {
                sections = saved
            }
        }
    }

    // MARK: Parts

    private var sectionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The sections you shop in")
                .caroLabelStyle()
            HStack(spacing: 8) {
                Chip(title: "Women's", isOn: sections.womens) { toggle(\.womens) }
                Chip(title: "Men's", isOn: sections.mens) { toggle(\.mens) }
                Chip(title: "Unisex", isOn: sections.unisex) { toggle(\.unisex) }
            }
            Text("What you shop for, not who you are. Choose one or more.")
                .font(.caroNote)
                .foregroundStyle(Color.muted)
        }
    }

    private var storeField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .iconFont(17, weight: .light)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            TextField("Add a store", text: $query, prompt: fieldPrompt("Add a store"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit { Task { await find() } }
                .onChange(of: query) {
                    if !finding {
                        found = nil
                        errorMessage = nil
                    }
                }
        }
        .underlinedField()
    }

    /// The tile under the field: while Caro looks, what it found with Add, or not found.
    @ViewBuilder
    private var card: some View {
        if finding {
            tile {
                VStack(alignment: .leading, spacing: 2) {
                    Text(query.trimmingCharacters(in: .whitespaces))
                        .font(.caroRowTitle)
                    Text("Looking for its \(PlaceFormats.site(country))")
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                ProgressView()
            }
        } else if let found {
            if found.found {
                Button {
                    Task { await add(found) }
                } label: {
                    tile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(found.name)
                                .font(.caroRowTitle)
                            Text(foundNote(found))
                                .font(.caroMeta)
                                .foregroundStyle(found.sellsOnline == true ? Color.muted : Color.terracottaOnTile)
                        }
                        Spacer()
                        Text(replacing == nil ? "Add" : "Use this site")
                            .font(.text(13, weight: .semibold, relativeTo: .subheadline))
                    }
                }
                .buttonStyle(.plain)
                .disabled(saving)
            } else {
                tile {
                    Text("Caro could not find a store called \u{201C}\(found.name)\u{201D} online. Check the name and try again.")
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
    }

    private func foundNote(_ found: FoundStore) -> String {
        let domain = found.domain ?? ""
        if found.sellsOnline == true {
            return "\(domain) · \(PlaceFormats.site(country)) found"
        }
        return "\(domain) · No online store in \(PlaceFormats.countryInSentence(country))"
    }

    private var addedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Added")
                    .font(.caroSectionTitle)
                Spacer()
                Text("\(stores.count) \(stores.count == 1 ? "store" : "stores")")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }

            VStack(spacing: 0) {
                ForEach(stores) { item in
                    storeRow(item)
                }
            }
            .padding(.top, 8)
        }
    }

    private func storeRow(_ item: Store) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.display(19, relativeTo: .title3))
                storeNote(item)
            }
            Spacer()
            Button {
                Task { await remove(item) }
            } label: {
                Image(systemName: "xmark")
                    .iconFont(14, weight: .regular)
                    .foregroundStyle(Color.muted)
                    .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func storeNote(_ item: Store) -> some View {
        if let checkedFor = item.country, checkedFor != country {
            // Found for the country the member lived in before. Nothing changes until they confirm.
            HStack(spacing: 10) {
                Text("Checked for \(PlaceFormats.countryInSentence(checkedFor))")
                    .foregroundStyle(Color.terracotta)
                Button("Find \(PlaceFormats.site(country))") {
                    Task { await findAgain(item) }
                }
                .font(.caroLink)
                .foregroundStyle(Color.ink)
                .underline()
            }
            .font(.caroMeta)
        } else if item.sellsOnline {
            Text("\(item.domain ?? "") · \(PlaceFormats.site(country))")
                .font(.caroMeta)
                .foregroundStyle(Color.muted)
        } else {
            Text("No online store in \(PlaceFormats.countryInSentence(country)), so Caro can\u{2019}t search it")
                .font(.caroMeta)
                .foregroundStyle(Color.terracotta)
        }
    }

    // MARK: Server

    private func find() async {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !finding else { return }
        finding = true
        found = nil
        errorMessage = nil
        defer { finding = false }

        do {
            found = try await store.api.findStore(name: name)
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func findAgain(_ item: Store) async {
        replacing = item
        query = item.name
        await find()
    }

    private func add(_ found: FoundStore) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }

        let failed: String?
        if let replacing {
            failed = await store.save { try await $0.replaceWebsite(of: replacing.id, with: found) }
        } else {
            failed = await store.save { try await $0.addStore(found) }
        }
        if let failed {
            errorMessage = failed
        } else {
            self.found = nil
            replacing = nil
            query = ""
        }
    }

    private func remove(_ item: Store) async {
        if let failed = await store.save({ try await $0.removeStore(id: item.id) }) {
            errorMessage = failed
        }
    }

    /// A chip was tapped: saved at once, so it is still chosen after closing the app.
    /// Once set up (in Settings), the last section cannot be turned off.
    private func toggle(_ section: WritableKeyPath<Sections, Bool>) {
        var changed = sections
        changed[keyPath: section].toggle()
        if !isOnboarding, !changed.any { return }
        sections = changed
        Task {
            if let failed = await store.save({ try await $0.saveSections(changed) }) {
                errorMessage = failed
            }
        }
    }

    private func continueOn() async {
        guard sections.any, !saving else { return }
        saving = true
        defer { saving = false }
        if let failed = await store.save({ try await $0.storesDone() }) {
            errorMessage = failed
        } else {
            onDone()
        }
    }

    private func skip() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        if let failed = await store.save({ try await $0.skipStores() }) {
            errorMessage = failed
        } else {
            onDone()
        }
    }
}
