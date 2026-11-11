import SwiftUI

/// S2 Enter code: the 6 digits from the email. It signs in by itself once all 6 are there.
/// The iPhone offers to fill the code from Mail, because the field is marked as a one-time code.
struct EnterCodeView: View {
    let email: String

    @Environment(Session.self) private var session

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var checking = false
    @State private var newCodeSent = false
    @FocusState private var codeFocused: Bool

    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Check your \(Text("email").italic())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text("Caro sent a 6-digit code to \(email). It works for 15 minutes.")
                    .font(.caroBody)
                    .lineSpacing(3)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Code")
                        .caroLabelStyle()
                    TextField("Code", text: $code, prompt: fieldPrompt("000000"))
                        .underlinedField(font: .caroCode)
                        .tracking(10)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .onChange(of: code) { _, typed in
                            codeChanged(to: typed)
                        }
                }
                .padding(.top, 28)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 8)
                }

                Button("Send a new code") {
                    Task { await sendNewCode() }
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracotta)
                .frame(minHeight: CaroLayout.minTouchTarget)
                .padding(.top, 10)

                if newCodeSent {
                    Text("A new code is on its way. Earlier codes no longer work.")
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                }

                #if DEBUG
                NoteBox(text: "In development the code is not emailed. It is in the terminal where npm run dev runs.", systemImage: "terminal")
                    .padding(.top, 24)
                #endif
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(checking ? "Signing in" : "Sign in") {
                Task { await verify() }
            }
            .buttonStyle(.pill)
            .disabled(code.count < 6 || checking)
            .bottomButtonBar()
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { codeFocused = true }
    }

    /// Keeps only digits, at most 6, and signs in once there are 6.
    private func codeChanged(to typed: String) {
        let digits = String(typed.filter(\.isNumber).prefix(6))
        if digits != typed {
            code = digits  // This runs codeChanged again with the clean value.
            return
        }
        if !digits.isEmpty {
            errorMessage = nil
        }
        if digits.count == 6 {
            Task { await verify() }
        }
    }

    private func verify() async {
        guard code.count == 6, !checking else { return }

        checking = true
        errorMessage = nil
        defer { checking = false }

        do {
            let result = try await api.verifyCode(email: email, code: code)
            // This switches the whole app to onboarding or the app (RootView).
            session.signedIn(token: result.token, member: result.member)
        } catch {
            errorMessage = session.message(for: error)
            code = ""
        }
    }

    private func sendNewCode() async {
        errorMessage = nil
        newCodeSent = false
        do {
            try await api.requestCode(email: email)
            code = ""
            newCodeSent = true
            codeFocused = true
        } catch {
            errorMessage = session.message(for: error)
        }
    }
}

#Preview {
    NavigationStack {
        EnterCodeView(email: "sara@example.com")
    }
    .environment(Session())
}
