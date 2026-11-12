import SwiftUI

/// The app's three sections (PRD section 7).
enum MainTab: Hashable, CaseIterable {
    case edit, looks, getTheLook

    var title: String {
        switch self {
        case .edit: "The edit"
        case .looks: "Looks"
        case .getTheLook: "Get the look"
        }
    }
}

/// Caro's tab bar: three words, the current one underlined (screens 08 and 10).
/// Until the wardrobe is open, Looks and Get the look are muted, with a small lock, and
/// cannot be chosen. The unlock rule itself is checked on the server.
struct TextTabBar: View {
    @Binding var selection: MainTab
    let unlocked: Bool

    var body: some View {
        HStack(alignment: .top) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                if tab != .edit {
                    Spacer(minLength: 8)
                }
                tabButton(tab)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(Color.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let locked = tab != .edit && !unlocked
        let current = tab == selection

        return Button {
            selection = tab
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if locked {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(tab.title)
                    .font(current ? .caroTabSelected : .caroTab)
                    // The underline sits a little below the words, as in the design.
                    .overlay(alignment: .bottom) {
                        if current {
                            Rectangle().fill(Color.ink).frame(height: 1).offset(y: 5)
                        }
                    }
            }
            .foregroundStyle(current ? Color.ink : Color.muted)
            .frame(minHeight: CaroLayout.minTouchTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(locked ? "\(tab.title), opens at 20 pieces" : tab.title)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

#Preview {
    VStack {
        Spacer()
        TextTabBar(selection: .constant(.edit), unlocked: false)
        TextTabBar(selection: .constant(.looks), unlocked: true)
    }
    .background(Color.paper)
}
