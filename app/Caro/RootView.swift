import SwiftUI

/// The first view in the window. It chooses what to show from who is signed in:
/// sign in, onboarding, or the app.
struct RootView: View {
    // @State: the root owns the one Session, the one SetupStore (the member's set-up) and the
    // one WardrobeStore (their pieces). .environment() below hands them to every screen.
    @State private var session: Session
    @State private var setupStore: SetupStore
    @State private var wardrobeStore: WardrobeStore

    init() {
        let session = Session()
        _session = State(initialValue: session)
        _setupStore = State(initialValue: SetupStore(session: session))
        _wardrobeStore = State(initialValue: WardrobeStore(session: session))
    }

    // Whether the app is in front, in the background, or briefly covered.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.state {
            case .starting:
                StartingView()
            case .notReachable:
                NotReachableView {
                    Task { await session.start() }
                }
            case .signedOut:
                SignInFlow()
            case .signedIn(let member):
                if member.status == .onboarding {
                    OnboardingFlow(member: member)
                } else {
                    MainView(member: member)
                }
            }
        }
        .environment(session)
        .environment(setupStore)
        .environment(wardrobeStore)
        .task {
            await session.start()
        }
        // Each time the app comes back to the front, check with the server again.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if session.state == .notReachable {
                    await session.start()
                } else {
                    await session.refresh()
                }
            }
        }
    }
}

/// While the app checks the saved session: paper and the wordmark, like the launch screen.
private struct StartingView: View {
    var body: some View {
        Wordmark(height: 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.paper)
    }
}

/// A session is saved, but the server cannot be reached to check it.
private struct NotReachableView: View {
    let tryAgain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Wordmark(height: 40)
            Text(APIError.notReachable.message)
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

#Preview {
    RootView()
}
