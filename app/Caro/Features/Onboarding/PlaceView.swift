import SwiftUI

/// Screen 02 Where you live, onboarding step 2: search for your city, see what Caro works out
/// from it (country, currency, dates, sizes), Change any of those, then Looks right.
/// In Settings, a new city goes on to its year first (`onNewCity`), so nothing changes until
/// the member confirms both.
struct PlaceView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 2
    /// In Settings: the member chose another city. Its year comes next, before saving.
    var onNewCity: ((PlaceChoice) -> Void)?
    /// Runs after a save: the next step in onboarding, back to Settings otherwise.
    let onDone: () -> Void

    @Environment(SetupStore.self) private var store

    @State private var query = ""
    @State private var results: [City] = []
    @State private var searched = ""
    @State private var searchError: String?
    @State private var choice: PlaceChoice?
    @State private var changing = false
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var started = false

    private var isOnboarding: Bool { step != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Where do you \(Text("live?").italic())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text("Caro uses it for your seasons, your stores, and how dates, prices and sizes look.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                searchField
                    .padding(.top, 22)

                resultList
                    .padding(.top, 4)

                if let choice {
                    workedOut(choice)
                        .padding(.top, 26)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(isOnboarding ? "Looks right" : "Save") {
                Task { await save() }
            }
            .buttonStyle(.pill)
            .disabled(choice == nil || saving)
            .bottomButtonBar()
        }
        .onboardingStep(step)
        .sheet(isPresented: $changing) {
            if let choice {
                FormatsSheet(choice: choice, today: today) { self.choice = $0 }
            }
        }
        // Searches a moment after typing stops, so not every letter is a request.
        .task(id: query) {
            await search()
        }
        .onAppear(perform: start)
    }

    // MARK: Parts

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            TextField("Search for your city", text: $query, prompt: fieldPrompt("Search for your city"))
                .textContentType(.addressCity)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .underlinedField()
    }

    @ViewBuilder
    private var resultList: some View {
        VStack(spacing: 0) {
            ForEach(results.prefix(3)) { city in
                let isChosen = city.id == choice?.city.id
                Button {
                    choose(city)
                } label: {
                    HStack {
                        Text(city.label)
                            .font(isChosen ? .caroRowTitle : .text(15, relativeTo: .body))
                            .foregroundStyle(isChosen ? Color.ink : Color.muted)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if isChosen {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .medium))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
            }

            if let searchError {
                note(searchError, colour: .terracotta)
            } else if results.isEmpty, searched.count >= 3, searched == trimmedQuery, choice?.city.name != searched {
                note("No city called \u{201C}\(searched)\u{201D} found. Try its name in English.", colour: .muted)
            }
        }
    }

    private func note(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.caroNote)
            .foregroundStyle(colour)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    /// "What Caro worked out": the box with country, currency, dates and sizes.
    private func workedOut(_ choice: PlaceChoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("What Caro worked out")
                    .font(.caroSectionTitle)
                Spacer()
                Button("Change") {
                    changing = true
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracotta)
            }

            VStack(spacing: 0) {
                fact("Country", PlaceFormats.countryName(choice.city.country))
                fact("Currency", PlaceFormats.currencyName(choice.currency))
                fact("Dates", PlaceFormats.shortDate(today, order: choice.dateOrder))
                fact("Sizes", choice.sizeSystem.example)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: CaroLayout.tileRadius).strokeBorder(Color.ink, lineWidth: 1))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caroLabel)
                .textCase(.uppercase)
                .tracking(11 * 0.14)
                .foregroundStyle(Color.muted)
            Spacer()
            Text(value)
                .font(.text(14, relativeTo: .body))
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: Working

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The server's today, for the date example: Oct 30 with DEV_TODAY=2026-10-30.
    private var today: Date {
        store.setup.flatMap { PlaceFormats.day($0.today) } ?? Date()
    }

    /// Shows the place already saved, when coming back to this step or from Settings.
    private func start() {
        guard !started else { return }
        started = true
        guard let place = store.setup?.place else { return }
        query = place.city
        if let cityId = place.cityId {
            let city = City(id: cityId, name: place.city, region: place.region, country: place.country)
            choice = PlaceChoice(
                city: city,
                currency: place.currency ?? PlaceFormats.defaultCurrency(place.country),
                dateOrder: place.dateOrder ?? PlaceFormats.defaultDateOrder(place.country),
                sizeSystem: place.sizeSystem ?? PlaceFormats.defaultSizeSystem(place.country)
            )
        }
    }

    private func search() async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            searched = ""
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        do {
            results = try await store.api.searchCities(text)
            searched = text
            searchError = nil
        } catch {
            if !Task.isCancelled {
                searchError = store.message(for: error)
            }
        }
    }

    /// A city in the same country keeps any formats the member changed; another country
    /// starts from that country's own.
    private func choose(_ city: City) {
        errorMessage = nil
        if let current = choice, current.city.country == city.country {
            choice = PlaceChoice(city: city, currency: current.currency, dateOrder: current.dateOrder, sizeSystem: current.sizeSystem)
        } else {
            choice = PlaceFormats.defaults(for: city)
        }
    }

    private func save() async {
        guard let choice, !saving else { return }

        if !isOnboarding, choice.city.id != store.setup?.place?.cityId, let onNewCity {
            onNewCity(choice)
            return
        }

        saving = true
        defer { saving = false }
        if let failed = await store.save({ try await $0.savePlace(choice) }) {
            errorMessage = failed
        } else {
            onDone()
        }
    }
}

/// Change, from screen 02: the currency, how dates look, and the size system.
/// The country follows the city, because the store websites depend on it.
private struct FormatsSheet: View {
    @State var choice: PlaceChoice
    let today: Date
    let onSave: (PlaceChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Currency", selection: $choice.currency) {
                        ForEach(PlaceFormats.allCurrencies, id: \.self) { code in
                            Text("\(PlaceFormats.currencyName(code)) (\(code))").tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("The country follows your city: \(PlaceFormats.countryName(choice.city.country)).")
                }
                .listRowBackground(Color.tile)

                Section("Dates") {
                    Picker("Dates", selection: $choice.dateOrder) {
                        ForEach(DateOrder.allCases, id: \.self) { order in
                            Text(PlaceFormats.shortDate(today, order: order)).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Color.tile)

                Section("Sizes") {
                    Picker("Sizes", selection: $choice.sizeSystem) {
                        ForEach(SizeSystem.allCases, id: \.self) { system in
                            Text(system.example).tag(system)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Color.tile)
            }
            .font(.caroBody)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(choice)
                        dismiss()
                    }
                }
            }
        }
        .tint(Color.ink)
        .presentationBackground(Color.paper)
    }
}
