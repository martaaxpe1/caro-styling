import SwiftUI

/// S4 Occasions, onboarding step 5 (to design, added in T4): the four occasions, explained,
/// numbered like the chapters of the edit. The same four for everyone in version one.
/// Continue finishes set-up. In Settings it is read only.
struct OccasionsView: View {
    /// The onboarding step to show, or nil in Settings.
    var step: Int? = 5
    /// Runs after Continue.
    var onDone: () -> Void = {}

    @Environment(SetupStore.self) private var store

    @State private var errorMessage: String?
    @State private var saving = false

    private var isOnboarding: Bool { step != nil }

    static let occasions = [
        ("Office", "Workdays with colleagues or clients."),
        ("Working from home", "Days at your own desk, calls included."),
        ("Night out", "Dinners, drinks and evenings out."),
        ("Day out", "Weekends, errands and lunches with friends."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your \(Text("occasions").italic())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text("Caro sorts your pieces and looks by occasion. For now, everyone has the same four.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(Self.occasions.indices, id: \.self) { index in
                        let (name, line) = Self.occasions[index]
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caroChapterNumber)
                                .frame(minWidth: 40, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.caroChapterName)
                                Text(line)
                                    .font(.caroBody)
                                    .foregroundStyle(Color.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 16)
                        .frame(minHeight: 80)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.hairline).frame(height: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .padding(.top, 24)

                Text("You give each piece and each look its occasions. Caro never chooses them for you.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 20)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if isOnboarding {
                Button("Continue") {
                    Task { await finish() }
                }
                .buttonStyle(.pill)
                .disabled(saving)
                .bottomButtonBar()
            }
        }
        .onboardingStep(step)
    }

    /// Set-up is done: the server makes the member active, and the app shows itself.
    private func finish() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        if let failed = await store.save({ try await $0.finishOnboarding() }) {
            errorMessage = failed
        } else {
            onDone()
        }
    }
}
