import SwiftUI

/// Sign in, from email to code. A NavigationStack lets Enter code (S2) slide in on top
/// of Sign in (S1), with the iPhone's own back button.
struct SignInFlow: View {
    var body: some View {
        NavigationStack {
            SignInView()
        }
        .tint(Color.ink)
    }
}

/// S1 Sign in: your email, then Send code. Only invited emails get one.
struct SignInView: View {
    @Environment(Session.self) private var session

    @State private var email = ""
    @State private var errorMessage: String?
    @State private var sending = false
    /// Set once a code is sent. That opens Enter code for this email.
    @State private var codeSentTo: String?

    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Wordmark(height: 40)
                    .padding(.top, 64)

                Text("A styling studio for the clothes you already own.")
                    .font(.caroLead)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your email")
                        .caroLabelStyle()
                    TextField("Your email", text: $email, prompt: fieldPrompt("name@example.com"))
                        .underlinedField()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit { Task { await sendCode() } }
                        .onChange(of: email) { errorMessage = nil }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                    }

                    Text("Caro is invite only. Use the email your invitation was sent to.")
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                        .padding(.top, errorMessage == nil ? 12 : 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 44)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(sending ? "Sending code" : "Send code") {
                Task { await sendCode() }
            }
            .buttonStyle(.pill)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.paper)
        .toolbar(.hidden, for: .navigationBar)
        // Enter code shows only a back arrow, no "Back" text.
        .toolbarRole(.editor)
        .navigationDestination(item: $codeSentTo) { address in
            EnterCodeView(email: address)
        }
    }

    private func sendCode() async {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !address.isEmpty, !sending else { return }

        sending = true
        errorMessage = nil
        defer { sending = false }

        do {
            try await api.requestCode(email: address)
            codeSentTo = address
        } catch {
            errorMessage = session.message(for: error)
        }
    }
}

#Preview {
    SignInFlow()
        .environment(Session())
}
