import SwiftUI

/// Onboarding steps 1 to 6, one screen each, in a NavigationStack: a stack of screens with
/// the iPhone's own back arrow and swipe back.
///
/// Resume: the server remembers the furthest step reached. When the app opens, the stack is
/// rebuilt up to that step (for step 4: Welcome, then 2, 3 and 4 on top), so it opens where
/// the member stopped and the back arrow still works.
///
/// After step 5 the server makes the member active, and step 6, Your wardrobe, follows. Once
/// the first pieces are in, RootView shows the app (the edit) instead.
struct OnboardingFlow: View {
    @Environment(SetupStore.self) private var store
    @Environment(Session.self) private var session

    /// The screens on top of Welcome: steps like 2, 3, 4, then adding pieces and the review.
    @State private var path: NavigationPath

    init(member: Member) {
        let step = min(max(member.onboardingStep, 1), 6)
        _path = State(initialValue: NavigationPath(step >= 2 ? Array(2...step) : []))
    }

    var body: some View {
        Group {
            if store.setup != nil {
                NavigationStack(path: $path) {
                    screen(1)
                        .navigationDestination(for: Int.self) { step in
                            screen(step)
                        }
                        .navigationDestination(for: WardrobeRoute.self) { route in
                            WardrobeDestination(route: route)
                        }
                }
                .tint(Color.ink)
                .environment(\.closeToEdit) {
                    Task { await closeToEdit() }
                }
            } else if let message = store.loadError {
                LoadFailedView(message: message) {
                    Task { await store.load() }
                }
            } else {
                Wordmark(height: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.paper)
            }
        }
        .task {
            await store.load()
        }
    }

    @ViewBuilder
    private func screen(_ step: Int) -> some View {
        switch step {
        case 1:
            WelcomeView(step: 1) { next(after: 1) }
        case 2:
            PlaceView(step: 2) { next(after: 2) }
        case 3:
            YearView(step: 3) { next(after: 3) }
        case 4:
            StoresView(step: 4) { next(after: 4) }
        case 5:
            OccasionsView(step: 5) { next(after: 5) }
        default:
            YourWardrobeView(showsStep: true) {
                path.append(WardrobeRoute.adding)
            }
        }
    }

    private func next(after step: Int) {
        path.append(step + 1)
    }

    /// "Close and keep your progress" while adding the first pieces: the server is asked again,
    /// and once it has pieces, RootView opens the app on the edit. If none arrived yet, back to
    /// step 6.
    private func closeToEdit() async {
        await session.refresh()
        if session.member?.showsOnboarding == true {
            path = NavigationPath(Array(2...6))
        }
    }
}

/// The set-up could not be loaded, usually because the server cannot be reached.
struct LoadFailedView: View {
    let message: String
    let tryAgain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Wordmark(height: 40)
            Text(message)
                .font(.caroBody)
                .foregroundStyle(Color.terracotta)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Spacer()
        }
        .padding(.horizontal, CaroLayout.pageMargin)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button("Try again", action: tryAgain)
                .buttonStyle(.pillOutlined)
                .bottomButtonBar()
        }
        .background(Color.paper)
    }
}
