import SwiftUI
import UIKit

/// Caro in the iPhone's share sheet (T10). When you share an image, or a Pinterest link, from
/// another app and choose Caro, iOS opens this small screen on top of that app. It sends the
/// image to Get the look, where Caro reads it, and closes. The app itself does not open.
///
/// A share extension is a second, small program inside the app (its own Xcode target). It
/// cannot see the app's screens or data; it reads the session from the shared Keychain.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let shared = SharedItem.from(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        let view = ShareView(shared: shared) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } cancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "com.carostyling.share", code: 0))
        }
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
