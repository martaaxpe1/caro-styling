import Foundation

/// Settings that depend on where the app runs.
enum AppConfig {
    /// The address of the Caro server.
    /// - In the Simulator: the server on this Mac.
    /// - On the iPhone: the same server, found over wifi by the Mac's name.
    /// T8 adds the online server on Render.
    static let serverURL: URL = {
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "http://Martas-MacBook-Pro-2.local:3000")!
        #endif
    }()
}
