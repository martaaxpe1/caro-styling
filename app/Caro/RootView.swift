import SwiftUI

/// The first view in the window. It chooses what to show from who is signed in:
/// sign in, onboarding, or the app.
struct RootView: View {
    // @State: the root owns the one Session. .environment() below hands it to every screen.
    @State private var session = Session()

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
                    OnboardingPlaceholderView(member: member)
                } else {
                    HomePlaceholderView(member: member)
                }
            }
        }
        .environment(session)
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
