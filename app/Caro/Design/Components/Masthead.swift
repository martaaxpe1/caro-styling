import SwiftUI

/// The top of the main screens (screen 10): the profile button with your initial, the CARO
/// wordmark, the add button, a double rule and the dateline in label style.
struct Masthead: View {
    let initial: String
    var dateline: String = ""
    var datelineRight: String = ""
    /// The plus on the right, for adding pieces. No plus when there is nothing to add.
    var add: (() -> Void)?
    /// What the plus says to VoiceOver: "Add pieces" on the edit, "Style a look" on Looks.
    var addLabel = "Add pieces"
    let openProfile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Wordmark(height: 28)

                HStack {
                    Button(action: openProfile) {
                        ProfileCircle(initial: initial)
                    }
                    .accessibilityLabel("Profile and settings")
                    .accessibilityShowsLargeContentViewer()

                    Spacer()

                    if let add {
                        Button(action: add) {
                            Image(systemName: "plus")
                                .iconFont(20, weight: .light)
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(addLabel)
                        .accessibilityShowsLargeContentViewer()
                    }
                }
            }
            .frame(minHeight: 44)
            // Like the iPhone's own bars: the buttons grow with the text up to the largest
            // standard size; beyond it, touching and holding shows them large.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

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

/// The initial in its circle: 34 points at the normal text size, growing with the initial, up to
/// the masthead's largest text size.
private struct ProfileCircle: View {
    let initial: String
    @ScaledMetric(relativeTo: .footnote) private var circle: CGFloat = 34

    var body: some View {
        Text(initial)
            .font(.text(13, weight: .medium, relativeTo: .footnote))
            .frame(width: circle, height: circle)
            .overlay(Circle().strokeBorder(Color.ink, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        Masthead(initial: "M", dateline: "The autumn edit", datelineRight: "96 pieces", add: {}) {}
        Spacer()
    }
    .background(Color.paper)
}
