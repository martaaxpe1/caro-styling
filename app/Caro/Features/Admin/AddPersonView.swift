import SwiftUI

/// Add person, a sheet over Admin: a name and an email, then Send invitation.
/// The invitation is open for 14 days.
struct AddPersonView: View {
    /// Runs after the invitation is sent, with the email it went to.
    var onSent: (String) async -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var errorMessage: String?
    @State private var sending = false

    private enum Field {
        case name, email
    }

    @FocusState private var focus: Field?

    private let api = APIClient()

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !sending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add a \(Text("person").italic())")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()

                    Text("Caro emails them the app and how to sign in.")
                        .font(.caroBody)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .caroLabelStyle()
                        TextField("Name", text: $name, prompt: fieldPrompt("Their first name"))
                            .underlinedField()
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focus, equals: .name)
                            .onSubmit { focus = .email }
                            .onChange(of: name) { errorMessage = nil }
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .caroLabelStyle()
                        TextField("Email", text: $email, prompt: fieldPrompt("name@example.com"))
                            .underlinedField()
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($focus, equals: .email)
                            .onSubmit { Task { await send() } }
                            .onChange(of: email) { errorMessage = nil }
                    }
                    .padding(.top, 24)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                    }

                    NoteBox(text: note, systemImage: "envelope")
                        .padding(.top, 28)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(sending ? "Sending" : "Send invitation") {
                    Task { await send() }
                }
                .buttonStyle(.pill)
                .disabled(!canSend)
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Color.ink)
        .presentationBackground(Color.paper)
        .onAppear { focus = .name }
    }

    private var note: String {
        #if DEBUG
        "The invitation is open for 14 days. You can resend or cancel it from Admin. In development it is printed in the terminal, not emailed."
        #else
        "The invitation is open for 14 days. You can resend or cancel it from Admin."
        #endif
    }

    private func send() async {
        guard canSend else { return }

        sending = true
        errorMessage = nil
        defer { sending = false }

        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try await api.invite(name: name.trimmingCharacters(in: .whitespaces), email: address)
            await onSent(address)
            dismiss()
        } catch {
            errorMessage = session.message(for: error)
            focus = .email
        }
    }
}

#Preview {
    AddPersonView { _ in }
        .environment(Session())
}
