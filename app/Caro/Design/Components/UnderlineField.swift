import SwiftUI

extension View {
    /// Text fields as in the design (screens 01 and 02): the display serif on a thin ink line, no box.
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

/// The example text shown in an empty field, like name@example.com: lighter than typed text,
/// still easy to read (the placeholder colour, 4.5 to 1 on paper).
func fieldPrompt(_ text: String) -> Text {
    Text(text).foregroundStyle(Color.placeholder)
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
