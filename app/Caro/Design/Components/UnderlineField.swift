import SwiftUI

extension View {
    /// Text fields as in the design (screens 01 and 02): Bodoni on a thin ink line, no box.
    /// Use on a TextField, with a label above it in `.caroLabelStyle()`:
    ///
    ///     Text("Your email").caroLabelStyle()
    ///     TextField("Your email", text: $email).underlinedField()
    func underlinedField(font: Font = .caroField) -> some View {
        self
            .font(font)
            .foregroundStyle(Color.ink)
            .tint(Color.ink)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.ink)
                    .frame(height: 1)
            }
    }
}

/// The light text shown in an empty field, like name@example.com.
func fieldPrompt(_ text: String) -> Text {
    Text(text).foregroundStyle(Color.outline)
}

#Preview {
    @Previewable @State var email = ""
    VStack(alignment: .leading, spacing: 6) {
        Text("Your email").caroLabelStyle()
        TextField("Your email", text: $email, prompt: fieldPrompt("name@example.com"))
            .underlinedField()
    }
    .padding(CaroLayout.pageMargin)
    .background(Color.paper)
}
