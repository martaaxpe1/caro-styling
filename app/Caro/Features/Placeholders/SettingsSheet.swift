import SwiftUI

/// A small stand-in for Settings (S5) until T4 builds it: who you are, the admin area
/// for the admin, and sign out. Opened from the profile button in the masthead.
struct SettingsSheet: View {
    let member: Member

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.caroRowTitle)
                    Text(member.email)
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                .padding(.top, 20)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)

                // Only the admin sees this row. The server checks it again on every admin request.
                if member.isAdmin {
                    NavigationLink {
                        AdminView()
                    } label: {
                        HStack {
                            Text("Admin")
                                .font(.caroRowTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.muted)
                        }
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

                Spacer()
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .safeAreaInset(edge: .bottom) {
                Button("Sign out") {
                    Task { await session.signOut() }
                }
                .buttonStyle(.pillOutlined)
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.bottom, 8)
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.ink)
        .presentationBackground(Color.paper)
    }
}

#Preview {
    SettingsSheet(member: Member(id: 1, name: "Marta", email: "marta@example.com", role: .admin, status: .active, onboardingStep: 6, country: "NL"))
        .environment(Session())
}
