import SwiftUI

/// Sara Caro's CARO wordmark. Never redrawn or recoloured.
/// 28 points high in the masthead; other screens pass their own height.
struct Wordmark: View {
    var height: CGFloat = 28

    var body: some View {
        Image(.wordmark)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Caro")
    }
}

#Preview {
    Wordmark()
        .padding()
        .background(Color.paper)
}
