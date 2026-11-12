import Foundation

/// Settings that depend on where the app runs.
enum AppConfig {
    /// The online server on Render (T8), over https. If Render gave the service another
    /// address, change it here.
    static let onlineURL = URL(string: "https://caro-styling.onrender.com")!

    /// The address of the Caro server.
    /// - TestFlight builds (Release): the online server.
    /// - Run from Xcode (Debug), in the Simulator: the server on this Mac.
    /// - Run from Xcode (Debug), on the iPhone: the same server, found over wifi by the Mac's name.
    static let serverURL: URL = {
        #if DEBUG
        // For testing against another copy of the server: launch the app with
        // -serverURL http://localhost:3100, or -serverURL https://caro-styling.onrender.com
        // (an Xcode scheme argument, or simctl launch).
        if let address = UserDefaults.standard.string(forKey: "serverURL"), let url = URL(string: address) {
            return url
        }

        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "http://Martas-MacBook-Pro-2.local:3000")!
        #endif

        #else
        return onlineURL
        #endif
    }()
}
