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
    /// The screens pushed on top of Looks: a look, its pieces.
    @State private var looksPath = NavigationPath()
    /// The screens pushed on top of Get the look: an inspiration and your version of it.
    @State private var getPath = NavigationPath()

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
                            openChapter: { editPath.append(WardrobeRoute.chapter(name: $0.name, number: $0.number)) },
                            open: { editPath.append($0) }
                        )
                        .navigationDestination(for: WardrobeRoute.self) { route in
                            destination(route)
                        }
                    }
                    .tint(Color.ink)
                case .looks:
                    NavigationStack(path: $looksPath) {
                        LooksView(member: member)
                            .navigationDestination(for: WardrobeRoute.self) { route in
                                WardrobeDestination(route: route)
                            }
                    }
                    .tint(Color.ink)
                case .getTheLook:
                    NavigationStack(path: $getPath) {
                        GetTheLookView(member: member) { id in
                            getPath.append(GetTheLookRoute.inspiration(id: id))
                        }
                        .navigationDestination(for: GetTheLookRoute.self) { route in
                            switch route {
                            case .inspiration(let id):
                                InspirationView(inspirationID: id)
                            }
                        }
                    }
                    .tint(Color.ink)
                }
            }
            .frame(maxHeight: .infinity)

            // The tab bar shows on the first screen of each section, not over adding pieces.
            if (tab == .edit && editPath.isEmpty) || (tab == .looks && looksPath.isEmpty) || (tab == .getTheLook && getPath.isEmpty) {
                TextTabBar(selection: $tab, unlocked: member.unlocked)
            }
        }
        .background(Color.paper)
        .environment(\.closeToEdit) {
            editPath = NavigationPath()
        }
        // "Style your first look" on screen 09 opens Looks.
        .onChange(of: store.openLooksNext, initial: true) { _, open in
            guard open else { return }
            store.openLooksNext = false
            editPath = NavigationPath()
            tab = .looks
        }
        // An inspiration from a look's page or the overview: show it in Get the look.
        .onChange(of: store.inspirationToOpen, initial: true) { _, inspirationID in
            guard let inspirationID else { return }
            store.inspirationToOpen = nil
            tab = .getTheLook
            var path = NavigationPath()
            path.append(GetTheLookRoute.inspiration(id: inspirationID))
            getPath = path
        }
        // A look saved from a photo, or "Open No. 12" after the same look rule: show its page.
        .onChange(of: store.lookToOpen, initial: true) { _, lookID in
            guard let lookID else { return }
            store.lookToOpen = nil
            editPath = NavigationPath()
            tab = .looks
            var path = NavigationPath()
            path.append(WardrobeRoute.look(id: lookID))
            looksPath = path
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

/// The screens pushed from the edit, and adding pieces (the same from onboarding).
struct WardrobeDestination: View {
    let route: WardrobeRoute

    var body: some View {
        switch route {
        case .adding:
            AddingPiecesView()
        case .chapter(let name, let number):
            ChapterView(name: name, number: number)
        case .review:
            ReviewView()
        case .piece(let id):
            PieceView(pieceID: id)
        case .editPiece(let piece):
            ReviewView(editing: piece)
        case .overview:
            OverviewView()
        case .seasonsCheck:
            SeasonsCheckView()
        case .look(let id):
            LookView(lookID: id)
        case .looksWith(let pieceID, let name):
            PieceLooksView(pieceID: pieceID, name: name)
        case .addPieces:
            EmptyView()
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
