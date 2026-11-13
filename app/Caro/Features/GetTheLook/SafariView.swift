import SafariServices
import SwiftUI

/// A store's product page in Safari, inside the app (SFSafariViewController, part of iOS).
/// The member stays in Caro and closes it with Done. Caro never sees what happens in it.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(Color.ink)
        safari.dismissButtonStyle = .done
        return safari
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A web address that can be shown with .sheet(item:).
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
