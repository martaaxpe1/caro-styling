import SwiftUI

/// Screen 01 Welcome, onboarding step 1: the wordmark, what Caro is, who invited you, your
/// name (prefilled from the invitation) and the privacy note. In Settings, only the name.
struct WelcomeView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 1
    /// Runs after a save: the next step in onboarding, back to Settings otherwise.
    let onDone: () -> Void

    @Environment(SetupStore.self) private var store
    @Environment(Session.self) private var session

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    private var isOnboarding: Bool { step != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isOnboarding {
                    Wordmark(height: 40)
                        .padding(.top, 54)

                    Text("A styling studio for the clothes you already own.")
                        .font(.caroLead)
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.horizontal, 16)

                    if let invitedBy = store.setup?.invitedBy {
                        Text("\(invitedBy) invited you.")
                            .font(.caroBody)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 18)
                    }
                } else {
                    Text("Your \(Text("name").italic())")
                        .font(.caroScreenTitle)
                        .caroTitleTracking()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("What should we call you?")
                        .caroLabelStyle()
                    TextField("Your name", text: $name, prompt: fieldPrompt("Your first name"))
                        .underlinedField(font: .display(26, relativeTo: .title))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.continue)
                        .focused($nameFocused)
                        .onSubmit { Task { await save() } }
                        .onChange(of: name) { errorMessage = nil }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isOnboarding ? 44 : 28)

                if isOnboarding {
                    NoteBox(
                        text: "Your photos are private. Caro uses an AI service to recognise your pieces in them. It never styles you: that part is yours.",
                        systemImage: "lock"
                    )
                    .padding(.top, 32)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(isOnboarding ? "Continue" : "Save") {
                Task { await save() }
            }
            .buttonStyle(.pill)
            .disabled(trimmedName.isEmpty || saving)
            .bottomButtonBar()
        }
        .onboardingStep(step)
        .toolbar {
            // Only on the first step: a way out of someone else's account while testing.
            if isOnboarding {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .font(.caroLink)
                    .foregroundStyle(Color.muted)
                }
            }
        }
        .onAppear {
            if name.isEmpty {
                name = store.setup?.member.name ?? ""
            }
        }
    }

    private func save() async {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }

        let failed = await store.save { try await $0.saveName(trimmedName) }
        if let failed {
            errorMessage = failed
        } else {
            nameFocused = false
            onDone()
        }
    }
}
