import UIKit

/// Loads the pictures of pieces from the server and keeps them on the iPhone, so browsing
/// stays fast (PRD section 14).
///
/// The photos are private: each request carries the session token, which the iPhone's ready-made
/// image view (AsyncImage) cannot send. So Caro loads them itself, here.
/// - In memory: the pictures shown recently, for scrolling.
/// - On disk: every picture already seen, in the app's own caches folder. The server's addresses
///   change when a photo is retaken (?v=), so a kept copy is never out of date.
/// At sign-out everything is wiped, so the next person on this iPhone never sees them.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskCache: URLCache
    private let session: URLSession
    private let api = APIClient()

    private init() {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "piece-pictures")
        diskCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024, directory: folder)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = diskCache
        // A kept copy is used without asking the server again.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 300
    }

    /// The picture at a server address, or nil if it cannot be loaded.
    func image(for path: String) async -> UIImage? {
        if let image = memory.object(forKey: path as NSString) {
            return image
        }
        guard let request = api.imageRequest(for: path) else { return nil }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
            let prepared = await image.byPreparingForDisplay() ?? image
            memory.setObject(prepared, forKey: path as NSString)
            return prepared
        } catch {
            return nil
        }
    }

    /// A picture the app already has (it just made the cut-out), so it is not downloaded again.
    func keep(_ image: UIImage, for path: String) {
        memory.setObject(image, forKey: path as NSString)
    }

    /// At sign-out: forget every picture, in memory and on disk.
    func removeAll() {
        memory.removeAllObjects()
        diskCache.removeAllCachedResponses()
    }
}
