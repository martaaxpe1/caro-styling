import SwiftUI

/// T0's only screen: it shows Caro's look and checks that the app can reach the server.
/// T3 replaces it with sign in, and the name comes from the signed-in member.
struct HelloView: View {
    enum ServerStatus {
        case checking, connected, unreachable
    }

    // @State is data the screen owns. When it changes, the screen redraws itself.
    @State private var status = ServerStatus.checking

    // Whether the app is in front, in the background, or briefly covered (for example by a permission alert).
    @Environment(\.scenePhase) private var scenePhase

    private let api = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Wordmark(height: 32)

            Text("Hello, \(Text("Marta").italic())")
                .font(.caroScreenTitle)
                .caroTitleTracking()
                .padding(.top, 28)

            statusLine
                .padding(.top, 16)

            Spacer()
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The button sits on top at the bottom, so the text above does not move when it appears.
        .overlay(alignment: .bottom) {
            if status == .unreachable {
                Button("Try again") {
                    Task { await checkServer() }
                }
                .buttonStyle(.pillOutlined)
            }
        }
        .padding(.horizontal, CaroLayout.pageMargin)
        .background(Color.paper)
        // Check when the app opens, and again each time it comes back to the front.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await checkServer() }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .checking:
            Text("Connecting")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
        case .connected:
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.ink)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("Server connected")
            }
            .font(.caroBody)
        case .unreachable:
            VStack(spacing: 4) {
                Text("Server not reachable")
                    .font(.caroBody)
                    .foregroundStyle(Color.terracotta)
                Text("Is npm run dev running on your Mac?")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func checkServer() async {
        status = .checking
        status = await api.checkHealth() ? .connected : .unreachable
    }
}

#Preview {
    HelloView()
}
