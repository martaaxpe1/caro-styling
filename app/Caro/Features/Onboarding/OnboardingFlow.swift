import SwiftUI

/// Onboarding steps 1 to 5, one screen each, in a NavigationStack: a stack of screens with
/// the iPhone's own back arrow and swipe back.
///
/// Resume: the server remembers the furthest step reached. When the app opens, the stack is
/// rebuilt up to that step (for step 4: Welcome, then 2, 3 and 4 on top), so it opens where
/// the member stopped and the back arrow still works.
///
/// After step 5 the server makes the member active, and RootView shows the app instead.
struct OnboardingFlow: View {
    @Environment(SetupStore.self) private var store

    /// The steps on top of Welcome, like [2, 3, 4].
    @State private var path: [Int]

    init(member: Member) {
        let step = min(max(member.onboardingStep, 1), 5)
        _path = State(initialValue: step >= 2 ? Array(2...step) : [])
    }

    var body: some View {
        Group {
            if store.setup != nil {
                NavigationStack(path: $path) {
                    screen(1)
                        .navigationDestination(for: Int.self) { step in
                            screen(step)
                        }
                }
                .tint(Color.ink)
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
        default:
            OccasionsView(step: 5)
        }
    }

    private func next(after step: Int) {
        path.append(step + 1)
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
