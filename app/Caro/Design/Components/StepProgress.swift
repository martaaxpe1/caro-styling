import SwiftUI

/// Onboarding's "Step N of 6" and its progress line: 6 segments, 2 points high, ink when done.
/// Screens 01 to 05.
struct StepProgress: View {
    let step: Int
    var total = 6

    var body: some View {
        VStack(spacing: 8) {
            Text("Step \(step) of \(total)")
                .caroLabelStyle()
                .frame(height: 32)

            StepSegments(step: step, total: total)
        }
    }
}

/// The progress line on its own, for screens where "Step N of 6" sits in the navigation bar,
/// next to the back arrow (screens 02 to 05).
struct StepSegments: View {
    let step: Int
    var total = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { segment in
                Rectangle()
                    .fill(segment <= step ? Color.ink : Color.hairline)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, CaroLayout.pageMargin)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The top of an onboarding step: "Step N of 6" in the navigation bar and the progress line
    /// under it. With no step (the same screen in Settings), neither shows.
    func onboardingStep(_ step: Int?) -> some View {
        self
            .toolbar {
                if let step {
                    ToolbarItem(placement: .principal) {
                        Text("Step \(step) of 6")
                            .caroLabelStyle()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let step {
                    StepSegments(step: step)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .background(Color.paper)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .paperBar()
            .background(Color.paper)
    }
}

#Preview {
    StepProgress(step: 2)
        .background(Color.paper)
}
