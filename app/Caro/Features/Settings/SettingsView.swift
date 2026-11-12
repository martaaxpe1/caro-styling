import SwiftUI

/// S5 Settings (to design, added in T4), opened from the profile button in the masthead.
/// Your set-up, one row per onboarding step with its current value, each opening the same
/// screen as in onboarding. Your data (T8): Download everything, a zip shared through the
/// iPhone's share sheet, and Delete account, a small terracotta link that asks first (not for
/// the admin, whose account cannot be deleted). The admin also sees the admin area. Sign out
/// at the bottom.
struct SettingsView: View {
    let member: Member

    @Environment(Session.self) private var session
    @Environment(SetupStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Page] = []
    /// Download everything: the zip being prepared, and once ready, the file to share.
    @State private var downloading = false
    @State private var download: Download?
    @State private var dataMessage: String?
    @State private var confirmingDelete = false
    @State private var deleting = false

    /// A zip on the iPhone, ready for the share sheet.
    struct Download: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// The screens Settings opens.
    enum Page: Hashable {
        case name, place, year, stores, occasions, admin
        /// The year for a city the member is moving to, saved together with the city.
        case yearFor(PlaceChoice)
    }

    /// The member as they are now, after any change made here.
    private var current: Member { session.member ?? member }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.name)
                            .font(.caroRowTitle)
                        Text(current.email)
                            .font(.caroMeta)
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.top, 20)

                    if let setup = store.setup {
                        setUpRows(setup)
                            .padding(.top, 32)
                    } else if let message = store.loadError {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(message)
                                .font(.caroNote)
                                .foregroundStyle(Color.terracotta)
                            Button("Try again") {
                                Task { await store.load() }
                            }
                            .font(.caroLink)
                        }
                        .padding(.top, 32)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    yourData
                        .padding(.top, 40)

                    // Only the admin sees this. The server checks it again on every admin request.
                    if current.isAdmin {
                        sectionHeader("Admin")
                            .padding(.top, 40)
                        row("Admin", "Members and invitations", .admin)
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Sign out") {
                    Task { await session.signOut() }
                }
                .buttonStyle(.pillOutlined)
                .bottomButtonBar()
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Page.self) { page in
                destination(page)
            }
        }
        .tint(Color.ink)
        .presentationBackground(Color.paper)
        .task {
            await store.load()
        }
        .sheet(item: $download) { download in
            ShareSheet(items: [download.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Keep account", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Your pieces, looks and photos are deleted and you are signed out. This cannot be undone. To keep a copy, use Download everything first.")
        }
    }

    // MARK: Your data

    private var yourData: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Your data")

            Button {
                Task { await downloadEverything() }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Download everything")
                            .font(.caroRowTitle)
                        Text(downloading ? "Preparing your zip file" : "Your details, pieces, looks and photos, as a zip file")
                            .font(.caroMeta)
                            .foregroundStyle(Color.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    if downloading {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.muted)
                    }
                }
                .padding(.vertical, 10)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(downloading || deleting)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
            }

            if let dataMessage {
                Text(dataMessage)
                    .font(.caroNote)
                    .foregroundStyle(Color.terracotta)
                    .padding(.top, 12)
            }

            // The server refuses it for the admin too: Caro always keeps its admin.
            if !current.isAdmin {
                Button(deleting ? "Deleting your account" : "Delete account") {
                    confirmingDelete = true
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracotta)
                .disabled(downloading || deleting)
                .padding(.top, 20)
            }
        }
    }

    private func downloadEverything() async {
        dataMessage = nil
        downloading = true
        defer { downloading = false }
        do {
            download = Download(url: try await APIClient().downloadEverything())
        } catch {
            dataMessage = session.message(for: error)
        }
    }

    private func deleteAccount() async {
        dataMessage = nil
        deleting = true
        defer { deleting = false }
        do {
            // The session ends, and the app goes back to sign in.
            try await session.deleteAccount()
        } catch {
            dataMessage = session.message(for: error)
        }
    }

    // MARK: Rows

    private func setUpRows(_ setup: Setup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Your set-up")
            row("Name", setup.member.name, .name)
            row("Where you live", placeText(setup.place), .place)
            row("Your year", SeasonCount(count: setup.seasons.count).label, .year)
            row("Your stores", storesText(setup), .stores)
            row("Occasions", setup.occasions.map(\.name).joined(separator: ", "), .occasions)
        }
    }

    private func placeText(_ place: Place?) -> String {
        guard let place else { return "Not chosen yet" }
        return "\(place.city), \(PlaceFormats.countryName(place.country))"
    }

    private func storesText(_ setup: Setup) -> String {
        let count = setup.stores.count
        let stores = count == 0 ? "No stores yet" : "\(count) \(count == 1 ? "store" : "stores")"
        return setup.sections.any ? "\(stores) · \(setup.sections.words)" : stores
    }

    /// A label in small capitals over an ink rule, as in the admin area.
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .caroLabelStyle()
            Rectangle()
                .fill(Color.ink)
                .frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ title: String, _ value: String, _ page: Page) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caroRowTitle)
                    Text(value)
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
        }
    }

    // MARK: Screens

    @ViewBuilder
    private func destination(_ page: Page) -> some View {
        switch page {
        case .name:
            WelcomeView(step: nil, onDone: back)
        case .place:
            PlaceView(step: nil, onNewCity: { path.append(.yearFor($0)) }, onDone: back)
        case .year:
            YearView(step: nil, onDone: back)
        case .yearFor(let choice):
            YearView(step: nil, newPlace: choice) { path.removeAll() }
        case .stores:
            StoresView(step: nil)
        case .occasions:
            OccasionsView(step: nil, onDone: back)
        case .admin:
            AdminView()
        }
    }

    private func back() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
}

/// The iPhone's share sheet, to save a file to Files, AirDrop it or send it.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    let session = Session()
    SettingsView(member: .preview)
        .environment(session)
        .environment(SetupStore(session: session))
}
