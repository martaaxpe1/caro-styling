import SwiftUI

/// Screen 05, Your wardrobe: onboarding step 6, and what the edit's add button opens.
/// The count towards 20 with the three things it needs, how to photograph a piece, and the two
/// ways to add: Take photos and Choose from library. Once Looks and Get the look are open, it
/// is simply "Add pieces", without the step line and the count.
struct YourWardrobeView: View {
    /// Shows "Step 6 of 6" while the wardrobe is still being built.
    let showsStep: Bool
    /// Runs once photos are in line: shows the adding screen.
    let added: () -> Void

    @Environment(WardrobeStore.self) private var store
    @State private var showingLibrary = false
    @State private var showingCamera = false

    private var unlocked: Bool { store.progress?.unlocked ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if unlocked {
                        Text("Add \(Text("pieces").italic())")
                    } else {
                        Text("Now, your \(Text("wardrobe").italic())")
                    }
                }
                .font(.caroScreenTitle)
                .caroTitleTracking()

                Text("Photograph the pieces you keep. Caro cuts them out and suggests the details. You confirm.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)

                if !unlocked {
                    CountBox(progress: store.progress)
                        .padding(.top, 22)
                }

                Text("How to photograph a piece")
                    .font(.caroSectionTitle)
                    .padding(.top, 22)

                HStack(alignment: .top, spacing: 10) {
                    Tip(text: "One piece per photo") {
                        ClothingShape(path: ClothingShape.tee)
                            .fill(Color.drawingNavy)
                            .frame(width: 58, height: 58)
                            .smallShadow()
                    }
                    Tip(text: "Flat, or on a hanger") {
                        VStack(spacing: -8) {
                            Image(systemName: "hanger")
                                .font(.system(size: 34, weight: .light))
                            ClothingShape(path: ClothingShape.skirt)
                                .fill(Color.seasonTerracotta)
                                .frame(width: 44, height: 44)
                        }
                    }
                    Tip(text: "Plain background, daylight") {
                        Image(systemName: "sun.max")
                            .font(.system(size: 38, weight: .ultraLight))
                    }
                }
                .padding(.top, 10)

                Text("You can stop anytime. Your progress is saved.")
                    .font(.caroNote)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take photos", systemImage: "camera")
                }
                .buttonStyle(.pill)

                Button("Choose from library") {
                    showingLibrary = true
                }
                .buttonStyle(.pillOutlined)
            }
            .bottomButtonBar()
        }
        .onboardingStep(showsStep && !unlocked ? 6 : nil)
        .addPhotosSources(library: $showingLibrary, camera: $showingCamera, added: added)
        .task { await store.load() }
    }
}

/// "12 / 20" with the three things the wardrobe needs to open.
private struct CountBox: View {
    let progress: WardrobeProgress?

    var body: some View {
        let pieces = progress?.pieces ?? 0
        let needed = progress?.needed ?? 20

        HStack(alignment: .center, spacing: 18) {
            Text("\(pieces)\(Text(" / \(needed)").font(.display(24, relativeTo: .title2)).foregroundStyle(Color.muted))")
                .font(.display(64, relativeTo: .largeTitle))
                .fixedSize()
                .accessibilityLabel("\(pieces) of \(needed) pieces")

            VStack(alignment: .leading, spacing: 8) {
                Text("Looks and Get the look open at \(needed) pieces, with at least:")
                    .font(.caroNote)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    need("A top", done: progress?.top ?? false)
                    need("A bottom or a dress", done: progress?.bottomOrOnePiece ?? false)
                    need("A pair of shoes", done: progress?.shoes ?? false)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.ink).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 1) }
    }

    private func need(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .strokeBorder(Color.muted, lineWidth: 1)
                    .frame(width: 10, height: 10)
            }
            Text(text)
        }
        .font(.caroNote)
        .foregroundStyle(done ? Color.ink : Color.muted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done ? "\(text), done" : text)
    }
}

/// One of the three tips: a drawing on the tile colour, and a line under it.
private struct Tip<Drawing: View>: View {
    let text: String
    @ViewBuilder let drawing: Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                .fill(Color.tile)
                .frame(height: 96)
                .overlay { drawing }
                .accessibilityHidden(true)
            Text(text)
                .font(.caroMeta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A clothing shape from the design canvas, drawn on a 100 by 100 square.
/// Reads simple SVG paths: M (move), L (line), Q (curve), Z (close).
struct ClothingShape: Shape {
    let path: String

    static let tee = "M32 14 L43 10 Q50 17 57 10 L68 14 L84 28 L75 38 L68 33 L68 88 L32 88 L32 33 L25 38 L16 28 Z"
    static let skirt = "M36 14 L64 14 L78 88 L22 88 Z"

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        let origin = CGPoint(x: rect.midX - 50 * scale, y: rect.midY - 50 * scale)
        let parts = path.split(separator: " ").map(String.init)
        var shape = Path()
        var index = 0

        func point() -> CGPoint {
            let x = Double(parts[index].dropFirst(parts[index].first?.isLetter == true ? 1 : 0)) ?? 0
            let y = Double(parts[index + 1]) ?? 0
            index += 2
            return CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        while index < parts.count {
            let command = parts[index].first
            switch command {
            case "M": shape.move(to: point())
            case "L": shape.addLine(to: point())
            case "Q":
                let control = point()
                shape.addQuadCurve(to: point(), control: control)
            case "Z":
                shape.closeSubpath()
                index += 1
            default:
                index += 1
            }
        }
        return shape
    }
}

#Preview {
    let session = Session()
    NavigationStack {
        YourWardrobeView(showsStep: true) {}
    }
    .environment(session)
    .environment(WardrobeStore(session: session))
}
