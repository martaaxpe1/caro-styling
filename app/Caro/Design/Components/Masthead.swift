import SwiftUI

/// The top of the main screens (screen 10): the profile button with your initial, the CARO
/// wordmark, a double rule and the dateline in label style.
/// The add button on the right comes with adding pieces (T5).
struct Masthead: View {
    let initial: String
    var dateline: String = ""
    var datelineRight: String = ""
    let openProfile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Wordmark(height: 28)

                HStack {
                    Button(action: openProfile) {
                        Text(initial)
                            .font(.text(13, weight: .medium, relativeTo: .footnote))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.ink, lineWidth: 1))
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Profile and settings")

                    Spacer()
                }
            }
            .frame(height: 44)

            // The double rule: two ink lines, 3 points apart.
            VStack(spacing: 3) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .padding(.top, 10)
            .accessibilityHidden(true)

            if !dateline.isEmpty || !datelineRight.isEmpty {
                HStack {
                    Text(dateline)
                    Spacer()
                    Text(datelineRight)
                }
                .caroLabelStyle()
                .padding(.top, 9)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, CaroLayout.pageMargin)
    }
}

#Preview {
    VStack {
        Masthead(initial: "M", dateline: "The autumn edit", datelineRight: "96 pieces") {}
        Spacer()
    }
    .background(Color.paper)
}
