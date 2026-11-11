import Foundation

/// Settings that depend on where the app runs.
enum AppConfig {
    /// The address of the Caro server.
    /// - In the Simulator: the server on this Mac.
    /// - On the iPhone: the same server, found over wifi by the Mac's name.
    /// T8 adds the online server on Render.
    static let serverURL: URL = {
        #if DEBUG
        // For testing against another copy of the server: launch the app with
        // -serverURL http://localhost:3100 (an Xcode scheme argument, or simctl launch).
        if let address = UserDefaults.standard.string(forKey: "serverURL"), let url = URL(string: address) {
            return url
        }
        #endif

        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "http://Martas-MacBook-Pro-2.local:3000")!
        #endif
    }()
}
