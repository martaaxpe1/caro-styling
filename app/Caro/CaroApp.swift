import SwiftUI

/// Where the app starts. It opens one window and shows the root view in it.
@main
struct CaroApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
