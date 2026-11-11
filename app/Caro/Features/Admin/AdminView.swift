import SwiftUI

/// S3 Admin: members, invitations and add person (PRD section 4). Only the admin reaches it,
/// from settings, and the server refuses everyone else anyway. People and totals only:
/// nothing from anyone's wardrobe.
struct AdminView: View {
    @Environment(Session.self) private var session

    @State private var overview: AdminOverview?
    @State private var errorMessage: String?
    /// A short line after an action, like "Invitation sent again to ana@example.com."
    @State private var doneMessage: String?
    @State private var addingPerson = false
    @State private var memberToRemove: AdminMember?
    @State private var invitationToCancel: Invitation?

    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Admin")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 12)
                } else if let doneMessage {
                    Text(doneMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 12)
                }

                if let overview {
                    sectionHeader("Members", count: overview.members.count)
                        .padding(.top, 28)
                    ForEach(overview.members) { member in
                        memberRow(member)
                    }

                    sectionHeader("Invitations", count: overview.invitations.count)
                        .padding(.top, 40)
                    if overview.invitations.isEmpty {
                        Text("No invitations waiting.")
                            .font(.caroBody)
                            .foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .overlay(alignment: .bottom) { hairline }
                    }
                    ForEach(overview.invitations) { invitation in
                        invitationRow(invitation)
                    }

                    Button("Add person") {
                        addingPerson = true
                    }
                    .buttonStyle(.pillOutlined)
                    .padding(.top, 24)
                } else if errorMessage == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $addingPerson) {
            AddPersonView { email in
                doneMessage = "Invitation sent to \(email)."
                await load()
            }
        }
        // Centred system alerts: ask first before removing access or cancelling an invitation.
        .alert(
            "Remove access for \(memberToRemove?.name ?? "")?",
            isPresented: isShowing($memberToRemove),
            presenting: memberToRemove
        ) { member in
            Button("Keep access", role: .cancel) {}
            Button("Remove access", role: .destructive) {
                Task { await removeAccess(member) }
            }
        } message: { member in
            Text("\(member.name) can no longer sign in. Everything in this account is kept for 30 days, so you can restore access, then deleted.")
        }
        .alert(
            "Cancel the invitation for \(invitationToCancel?.name ?? "")?",
            isPresented: isShowing($invitationToCancel),
            presenting: invitationToCancel
        ) { invitation in
            Button("Keep invitation", role: .cancel) {}
            Button("Cancel invitation", role: .destructive) {
                Task { await cancel(invitation) }
            }
        } message: { invitation in
            Text("\(invitation.email) can no longer sign in with it.")
        }
    }

    // MARK: Rows

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }

    /// "MEMBERS" on the left, the count on the right, over an ink rule.
    private func sectionHeader(_ title: String, count: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
            }
            .caroLabelStyle()
            Rectangle()
                .fill(Color.ink)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func memberRow(_ member: AdminMember) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(member.name)
                        .font(.caroRowTitle)
                        .foregroundStyle(member.isRemoved ? Color.muted : Color.ink)
                    if member.isAdmin {
                        Text("Admin")
                            .caroLabelStyle()
                    }
                }
                Text(member.email)
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
                if member.isRemoved, let deletedOn = member.deletedOn {
                    Text("Access removed. Deleted on \(day(deletedOn)).")
                        .font(.caroMeta)
                        .foregroundStyle(Color.terracotta)
                } else {
                    Text(details(of: member))
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The admin's own row has no actions: the admin's access cannot be removed.
            if !member.isAdmin {
                Menu {
                    if member.isRemoved {
                        Button("Restore access") {
                            Task { await restoreAccess(member) }
                        }
                    } else {
                        Button("Remove access", role: .destructive) {
                            memberToRemove = member
                        }
                    }
                } label: {
                    moreIcon
                }
                .accessibilityLabel("Options for \(member.name)")
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { hairline }
    }

    private func invitationRow(_ invitation: Invitation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invitation.name)
                    .font(.caroRowTitle)
                Text(invitation.email)
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
                Text("Sent \(day(invitation.sentAt)) · Open until \(day(invitation.expiresAt))")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Resend") {
                    Task { await resend(invitation) }
                }
                Button("Cancel invitation", role: .destructive) {
                    invitationToCancel = invitation
                }
            } label: {
                moreIcon
            }
            .accessibilityLabel("Options for the invitation to \(invitation.name)")
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { hairline }
    }

    private var moreIcon: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17))
            .foregroundStyle(Color.ink)
            .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
            .contentShape(Rectangle())
    }

    // MARK: Words and dates

    /// "Rotterdam, Netherlands · Joined 10 Nov · Active today · 0 AI actions this month"
    private func details(of member: AdminMember) -> String {
        var parts: [String] = []

        if let city = member.city {
            let country = member.country.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) }
            parts.append([city, country].compactMap { $0 }.joined(separator: ", "))
        } else {
            parts.append("Place not set yet")
        }

        parts.append("Joined \(day(member.joinedAt))")

        if let lastActive = member.lastActiveAt {
            if Calendar.current.isDateInToday(lastActive) {
                parts.append("Active today")
            } else if Calendar.current.isDateInYesterday(lastActive) {
                parts.append("Active yesterday")
            } else {
                parts.append("Active \(day(lastActive))")
            }
        } else {
            parts.append("Not active yet")
        }

        let actions = member.aiActionsThisMonth
        parts.append("\(actions) AI \(actions == 1 ? "action" : "actions") this month")

        return parts.joined(separator: " · ")
    }

    /// A day as the admin's country writes it: 10 Nov in the Netherlands, Nov 10 in the US.
    private func day(_ date: Date) -> String {
        let locale = session.member?.country.map { Locale(identifier: "en_\($0)") } ?? .current
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// Turns "a member is chosen" into the yes or no an alert needs to show itself.
    private func isShowing<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
    }

    // MARK: Talking to the server

    private func load() async {
        do {
            overview = try await api.adminOverview()
            errorMessage = nil
        } catch {
            errorMessage = session.message(for: error)
        }
    }

    /// Runs one admin action, then reloads the lists.
    private func act(done: String, _ action: () async throws -> Void) async {
        errorMessage = nil
        doneMessage = nil
        do {
            try await action()
            doneMessage = done
        } catch {
            errorMessage = session.message(for: error)
        }
        await load()
    }

    private func removeAccess(_ member: AdminMember) async {
        await act(done: "Access removed for \(member.name).") {
            try await api.removeAccess(memberID: member.id)
        }
    }

    private func restoreAccess(_ member: AdminMember) async {
        await act(done: "Access restored for \(member.name).") {
            try await api.restoreAccess(memberID: member.id)
        }
    }

    private func resend(_ invitation: Invitation) async {
        await act(done: "Invitation sent again to \(invitation.email).") {
            try await api.resendInvitation(id: invitation.id)
        }
    }

    private func cancel(_ invitation: Invitation) async {
        await act(done: "Invitation for \(invitation.name) cancelled.") {
            try await api.cancelInvitation(id: invitation.id)
        }
    }
}

#Preview {
    NavigationStack {
        AdminView()
    }
    .environment(Session())
}
