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

            HStack(spacing: 4) {
                ForEach(1...total, id: \.self) { segment in
                    Rectangle()
                        .fill(segment <= step ? Color.ink : Color.hairline)
                        .frame(height: 2)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, CaroLayout.pageMargin)
    }
}

#Preview {
    StepProgress(step: 2)
        .background(Color.paper)
}
