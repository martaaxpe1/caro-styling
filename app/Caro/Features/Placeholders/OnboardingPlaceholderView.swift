import SwiftUI

/// Where a new member lands after the first sign-in.
/// T4 replaces it with onboarding, starting at Welcome (screen 01).
struct OnboardingPlaceholderView: View {
    let member: Member

    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            StepProgress(step: member.onboardingStep)
                .padding(.top, 10)

            Spacer()

            Wordmark(height: 40)

            Text("Welcome, \(Text(member.name).italic())")
                .font(.caroScreenTitle)
                .caroTitleTracking()
                .padding(.top, 28)

            Text("Onboarding comes in T4.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .padding(.top, 12)

            Spacer()
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button("Sign out") {
                Task { await session.signOut() }
            }
            .buttonStyle(.pillOutlined)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 8)
        }
        .background(Color.paper)
    }
}

#Preview {
    OnboardingPlaceholderView(member: Member(id: 2, name: "Sara", email: "sara@example.com", role: .member, status: .onboarding, onboardingStep: 1, country: nil))
        .environment(Session())
}
