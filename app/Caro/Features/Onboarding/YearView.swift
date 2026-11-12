import SwiftUI

/// Screen 03 Your year, onboarding step 3: the seasons proposed from your city's typical
/// weather. Choose four, two or no seasons, tap a month to move it to another season, rename
/// a season. The "Now:" line helps check it.
/// In Settings it shows your year, or, after choosing another city, the year for that city.
struct YearView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 3
    /// In Settings: the city the member is moving to, saved together with this year.
    var newPlace: PlaceChoice?
    /// Runs after a save: the next step in onboarding, back to Settings otherwise.
    let onDone: () -> Void

    @Environment(SetupStore.self) private var store

    @State private var proposal: YearProposal?
    @State private var loadError: String?
    @State private var count = SeasonCount.none
    @State private var seasons: [Season] = []
    @State private var renaming: Int?
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var saving = false

    private var isOnboarding: Bool { step != nil }

    private var cityName: String {
        newPlace?.city.name ?? store.setup?.place?.city ?? "your city"
    }

    var body: some View {
        Group {
            if let proposal {
                content(proposal)
            } else if let loadError {
                failed(loadError)
            } else {
                loading
            }
        }
        .onboardingStep(step)
        .task {
            if proposal == nil {
                await load()
            }
        }
    }

    // MARK: Screens

    private var loading: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Looking up the typical weather in \(cityName)")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
        .padding(CaroLayout.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        Text(message)
            .font(.caroBody)
            .foregroundStyle(Color.terracotta)
            .multilineTextAlignment(.center)
            .padding(CaroLayout.pageMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Button("Try again") {
                    Task { await load() }
                }
                .buttonStyle(.pillOutlined)
                .bottomButtonBar()
            }
    }

    private func content(_ proposal: YearProposal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your \(Text("year").italic())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text(intro(proposal))
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                SegmentedChoice(options: SeasonCount.allCases, selection: countBinding(proposal)) { $0.label }
                    .padding(.top, 20)

                MonthChart(
                    months: proposal.months,
                    seasons: seasons,
                    fahrenheit: PlaceFormats.usesFahrenheit(newPlace?.city.country ?? proposal.city.country),
                    onMove: move
                )
                .padding(.top, 24)

                if seasons.isEmpty {
                    Text("No seasons. Caro shows all your pieces all year.")
                        .font(.caroBody)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 18)
                } else {
                    seasonList
                        .padding(.top, 18)

                    if let now = nowLine(today: proposal.today) {
                        Text("\(Text("Now:").fontWeight(.semibold)) \(now)")
                            .font(.text(14, relativeTo: .body))
                            .padding(.top, 16)
                    }
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
        .safeAreaInset(edge: .bottom) {
            Button(isOnboarding ? "Continue" : "Save") {
                Task { await save() }
            }
            .buttonStyle(.pill)
            .disabled(saving)
            .bottomButtonBar()
        }
        .alert("Rename \(renaming.map { seasons[$0].name } ?? "season")", isPresented: isRenaming) {
            TextField("Season name", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
    }

    private var seasonList: some View {
        VStack(spacing: 0) {
            ForEach(seasons.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.season(index, of: seasons.count))
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(seasons[index].name)
                            .font(.display(19, relativeTo: .title3))
                        Text(Self.range(seasons[index].months))
                            .font(.caroMeta)
                            .foregroundStyle(Color.muted)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer()

                    Button {
                        newName = seasons[index].name
                        renaming = index
                    } label: {
                        Image(systemName: "pencil")
                            .iconFont(17, weight: .light)
                            .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(seasons[index].name)")
                }
                .frame(minHeight: 54)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    // MARK: Words

    private func intro(_ proposal: YearProposal) -> String {
        let city = proposal.city.name
        if proposal.saved != nil, newPlace == nil {
            return "Your year in \(city). Tap a month to move it to another season."
        }
        return "Proposed from \(city)\u{2019}s typical weather. Tap a month to move it to another season."
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private static func next(_ month: Int) -> Int { month % 12 + 1 }
    private static func previous(_ month: Int) -> Int { (month + 10) % 12 + 1 }

    /// "May to October", or "May to July, October" when a season has gaps.
    static func range(_ months: [Int]) -> String {
        let set = Set(months)
        if set.count == 12 { return "All year" }
        let starts = (1...12).filter { set.contains($0) && !set.contains(previous($0)) }
        return starts
            .map { start in
                var end = start
                while set.contains(next(end)) { end = next(end) }
                return start == end ? monthNames[start - 1] : "\(monthNames[start - 1]) to \(monthNames[end - 1])"
            }
            .joined(separator: ", ")
    }

    /// "hot and rainy, until the end of October." From the server's today, so DEV_TODAY works.
    private func nowLine(today: String) -> String? {
        guard let month = PlaceFormats.month(today),
              let season = seasons.first(where: { $0.months.contains(month) }) else { return nil }
        let set = Set(season.months)
        var end = month
        while set.contains(Self.next(end)), Self.next(end) != month {
            end = Self.next(end)
        }
        let name = season.name.prefix(1).lowercased() + season.name.dropFirst()
        return "\(name), until the end of \(Self.monthNames[end - 1])."
    }

    // MARK: Changes

    /// Switching between four, two and no seasons starts again from that proposal.
    private func countBinding(_ proposal: YearProposal) -> Binding<SeasonCount> {
        Binding(
            get: { count },
            set: { newCount in
                count = newCount
                seasons = proposal.seasons(for: newCount)
                errorMessage = nil
            }
        )
    }

    private func move(_ month: Int, to index: Int) {
        guard seasons.indices.contains(index) else { return }
        for i in seasons.indices {
            seasons[i].months.removeAll { $0 == month }
        }
        seasons[index].months.append(month)
        seasons[index].months.sort()
        errorMessage = nil
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func rename() {
        guard let index = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        let taken = seasons.indices.contains { $0 != index && seasons[$0].name.lowercased() == name.lowercased() }
        if name.isEmpty {
            return
        } else if taken {
            errorMessage = "Give each season its own name."
        } else {
            seasons[index].name = String(name.prefix(30))
            errorMessage = nil
        }
    }

    // MARK: Server

    private func load() async {
        loadError = nil
        do {
            let loaded = try await store.api.year(cityID: newPlace?.city.id)
            if let saved = loaded.saved, newPlace == nil {
                seasons = saved
                count = SeasonCount(count: saved.count)
            } else {
                count = loaded.suggested
                seasons = loaded.seasons(for: loaded.suggested)
            }
            proposal = loaded
        } catch {
            loadError = store.message(for: error)
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }

        let year = seasons
        let failed: String?
        if let newPlace {
            failed = await store.save { try await $0.savePlace(newPlace, seasons: year) }
        } else {
            failed = await store.save { try await $0.saveYear(year) }
        }
        if let failed {
            errorMessage = failed
        } else {
            onDone()
        }
    }
}

/// The 12 months as bars of their typical high, coloured by season (screen 03).
/// Tapping a month opens a menu of the seasons, to move it to another one.
private struct MonthChart: View {
    let months: [MonthWeather]
    let seasons: [Season]
    let fahrenheit: Bool
    let onMove: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(months, id: \.month) { month in
                    column(month)
                }
            }
            .frame(height: 150)

            Rectangle()
                .fill(Color.ink)
                .frame(height: 1)
                .padding(.top, 6)

            HStack(spacing: 4) {
                ForEach(months, id: \.month) { month in
                    Text(YearView.monthNames[month.month - 1].prefix(1))
                        .font(.text(12, weight: .medium, relativeTo: .caption))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true)

            Text("Typical daily high, \(fahrenheit ? "°F" : "°C")")
                .font(.text(11, relativeTo: .caption2))
                .foregroundStyle(Color.muted)
                .padding(.top, 6)
        }
    }

    private func shown(_ month: MonthWeather) -> Double {
        fahrenheit ? month.highC * 9 / 5 + 32 : month.highC
    }

    /// Bars from 56 to 120 points, from the coolest month to the warmest. A small spread of
    /// temperatures is not stretched to look large.
    private func barHeight(_ month: MonthWeather) -> CGFloat {
        let values = months.map(shown)
        let lowest = values.min() ?? 0
        let spread = max((values.max() ?? 0) - lowest, fahrenheit ? 18 : 10)
        return 56 + CGFloat((shown(month) - lowest) / spread) * 64
    }

    private func seasonIndex(_ month: Int) -> Int? {
        seasons.firstIndex { $0.months.contains(month) }
    }

    @ViewBuilder
    private func column(_ month: MonthWeather) -> some View {
        let index = seasonIndex(month.month)
        let name = YearView.monthNames[month.month - 1]
        let bar = VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(Int(shown(month).rounded()))")
                .font(.text(10, relativeTo: .caption2))
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(index.map { Color.season($0, of: seasons.count) } ?? Color.outline)
                .frame(height: barHeight(month))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if seasons.isEmpty {
            bar
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), typical high \(Int(shown(month).rounded())) degrees")
        } else {
            Menu {
                Picker(
                    "Move \(name) to",
                    selection: Binding(get: { index ?? 0 }, set: { onMove(month.month, $0) })
                ) {
                    ForEach(seasons.indices, id: \.self) { i in
                        Text(seasons[i].name).tag(i)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                bar
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(index.map { seasons[$0].name } ?? "no season")")
            .accessibilityHint("Moves the month to another season")
        }
    }
}
