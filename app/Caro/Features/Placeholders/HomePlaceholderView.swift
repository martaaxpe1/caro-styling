import SwiftUI

/// Where a member who finished set-up lands. T5 replaces it with the edit, still building
/// (screen 08). The profile button opens settings, which holds the admin area for the admin.
struct HomePlaceholderView: View {
    let member: Member

    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Masthead(initial: member.initial, dateline: "The edit") {
                showingSettings = true
            }
            .padding(.top, 6)

            Spacer()

            Text("Hello, \(Text(member.name).italic())")
                .font(.caroScreenTitle)
                .caroTitleTracking()

            Text("Your wardrobe comes in T5.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .padding(.top, 12)

            Spacer()
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .background(Color.paper)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(member: member)
        }
    }
}

#Preview {
    HomePlaceholderView(member: Member(id: 1, name: "Marta", email: "marta@example.com", role: .admin, status: .active, onboardingStep: 6, country: "NL"))
        .environment(Session())
}
