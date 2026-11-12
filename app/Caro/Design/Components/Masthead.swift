import SwiftUI

/// The top of the main screens (screen 10): the profile button with your initial, the CARO
/// wordmark, the add button, a double rule and the dateline in label style.
struct Masthead: View {
    let initial: String
    var dateline: String = ""
    var datelineRight: String = ""
    /// The plus on the right, for adding pieces. No plus when there is nothing to add.
    var add: (() -> Void)?
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

                    if let add {
                        Button(action: add) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .light))
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Add pieces")
                    }
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
        Masthead(initial: "M", dateline: "The autumn edit", datelineRight: "96 pieces", add: {}) {}
        Spacer()
    }
    .background(Color.paper)
}
