import SwiftUI

/// The app once set-up is done and the first pieces are in: three sections in a text tab bar,
/// The edit, Looks and Get the look (PRD section 7). Looks and Get the look open with the
/// wardrobe (20 pieces, checked on the server).
struct MainView: View {
    let member: Member

    @Environment(WardrobeStore.self) private var store
    @State private var tab: MainTab = .edit
    /// The screens pushed on top of the edit, like adding pieces or a chapter.
    @State private var editPath = NavigationPath()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .edit:
                    NavigationStack(path: $editPath) {
                        EditView(
                            member: member,
                            addPieces: { editPath.append(WardrobeRoute.addPieces) },
                            review: { editPath.append(WardrobeRoute.review) },
                            openChapter: { editPath.append(WardrobeRoute.chapter(name: $0.name, number: $0.number)) }
                        )
                        .navigationDestination(for: WardrobeRoute.self) { route in
                            destination(route)
                        }
                    }
                    .tint(Color.ink)
                case .looks:
                    ComingView(member: member, tab: .looks)
                case .getTheLook:
                    ComingView(member: member, tab: .getTheLook)
                }
            }
            .frame(maxHeight: .infinity)

            // The tab bar shows on the first screen of each section, not over adding pieces.
            if tab != .edit || editPath.isEmpty {
                TextTabBar(selection: $tab, unlocked: member.unlocked)
            }
        }
        .background(Color.paper)
        .environment(\.closeToEdit) {
            editPath = NavigationPath()
        }
        // "Style your first look" on screen 09 opens Looks (T7 builds it).
        .onChange(of: store.openLooksNext, initial: true) { _, open in
            guard open else { return }
            store.openLooksNext = false
            editPath = NavigationPath()
            tab = .looks
        }
    }

    @ViewBuilder
    private func destination(_ route: WardrobeRoute) -> some View {
        switch route {
        case .addPieces:
            YourWardrobeView(showsStep: true) {
                editPath.append(WardrobeRoute.adding)
            }
        default:
            WardrobeDestination(route: route)
        }
    }
}

/// The screens of adding pieces, the same from onboarding and from the edit.
struct WardrobeDestination: View {
    let route: WardrobeRoute

    var body: some View {
        switch route {
        case .adding:
            AddingPiecesView()
        case .chapter(let name, let number):
            ChapterPiecesView(name: name, number: number)
        case .review:
            ReviewView()
        case .piece(let piece):
            ReviewView(editing: piece)
        case .addPieces:
            EmptyView()
        }
    }
}

/// Looks and Get the look, until T7 and T10 build them.
struct ComingView: View {
    let member: Member
    let tab: MainTab

    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Masthead(initial: member.initial, dateline: tab.title) {
                showingSettings = true
            }
            .padding(.top, 6)

            Spacer()
            Text(tab == .looks ? "Styling looks comes in T7." : "Get the look comes in T10.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
            Spacer()
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .background(Color.paper)
        .sheet(isPresented: $showingSettings) {
            SettingsView(member: member)
        }
    }
}

#Preview {
    let session = Session()
    MainView(member: .preview)
        .environment(session)
        .environment(SetupStore(session: session))
        .environment(WardrobeStore(session: session))
}
