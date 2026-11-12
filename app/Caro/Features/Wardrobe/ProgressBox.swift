import SwiftUI

/// The progress box on the edit while Looks and Get the look are locked (screen 08):
/// "12 of 20", how many to go, the bar, the three checks, and Add pieces.
struct ProgressBox: View {
    let progress: WardrobeProgress
    let addPieces: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.pieces) \(Text("of").italic()) \(progress.needed)")
                    .font(.display(30, relativeTo: .title))
                Spacer()
                Text("\(progress.toGo) to go")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            .accessibilityElement(children: .combine)

            ProgressBar(fraction: Double(progress.pieces) / Double(max(progress.needed, 1)))
                .padding(.top, 12)

            UnlockChecks(progress: progress)
                .padding(.top, 12)

            HStack(spacing: 12) {
                Text(openLine)
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Add pieces", action: addPieces)
                    .font(.text(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.onInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Capsule())
                    .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .foregroundStyle(Color.ink)
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: CaroLayout.tileRadius).strokeBorder(Color.ink, lineWidth: 1)
        }
    }
}

extension ProgressBox {
    /// "Looks and Get the look open at 20." Once there are 20 but something is missing, it
    /// says what: "Looks and Get the look open with a pair of shoes."
    var openLine: String {
        guard progress.pieces >= progress.needed else {
            return "Looks and Get the look open at \(progress.needed)."
        }
        let missing = [
            progress.top ? nil : "a top",
            progress.bottomOrOnePiece ? nil : "a bottom or a dress",
            progress.shoes ? nil : "a pair of shoes",
        ].compactMap { $0 }
        guard !missing.isEmpty else { return "Looks and Get the look are opening." }
        let list = missing.count == 1 ? missing[0] : missing.dropLast().joined(separator: ", ") + " and " + missing.last!
        return "Looks and Get the look open with \(list)."
    }
}

/// The 4 point progress bar: ink over the hairline colour.
struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.hairline)
                Rectangle().fill(Color.ink).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The three parts of the unlock rule: a top, a bottom (or a dress), shoes. A check when the
/// wardrobe has one; "still missing" in terracotta once pieces are in and it has none.
struct UnlockChecks: View {
    let progress: WardrobeProgress

    var body: some View {
        let checks = [
            Check(done: progress.top, name: "A top", missing: "Top still missing"),
            Check(done: progress.bottomOrOnePiece, name: "A bottom", missing: "Bottom still missing"),
            Check(done: progress.shoes, name: "Shoes", missing: "Shoes still missing"),
        ]
        // On one line when it fits, one under the other when it does not.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { ForEach(checks) { row($0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(checks) { row($0) } }
        }
        .font(.caroNote)
    }

    private struct Check: Identifiable {
        let done: Bool
        let name: String
        let missing: String
        var id: String { name }
    }

    @ViewBuilder
    private func row(_ check: Check) -> some View {
        let started = progress.pieces > 0
        HStack(spacing: 5) {
            if check.done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text(check.name)
            } else {
                Circle()
                    .strokeBorder(lineWidth: 1)
                    .frame(width: 10, height: 10)
                Text(started ? check.missing : check.name)
            }
        }
        .foregroundStyle(check.done ? Color.ink : started ? Color.terracotta : Color.muted)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(check.done ? "\(check.name), done" : started ? check.missing : "\(check.name), not yet")
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressBox(progress: WardrobeProgress(pieces: 12, needed: 20, top: true, bottomOrOnePiece: true, shoes: false, unlocked: false)) {}
        ProgressBox(progress: WardrobeProgress(pieces: 0, needed: 20, top: false, bottomOrOnePiece: false, shoes: false, unlocked: false)) {}
    }
    .padding(CaroLayout.pageMargin)
    .background(Color.paper)
}
