import Foundation

/// Flyer image cache, ported from `lib/services/flyer_image_cache.dart`.
///
/// Disk cache keyed by URL: 30-day stale period, max 300 objects. The
/// detail page and the full-screen viewer share the same cache, keyed
/// by the same URL — opening the viewer downloads nothing a second time.
/// Fail-quiet like the detail page: an image that cannot load simply
/// occupies no space.
final class FlyerImageCache {
    static let shared = FlyerImageCache()

    private static let staleInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private static let maxObjects = 300

    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSData>()
    private let queue = DispatchQueue(label: "app.ravewatchlagos.flyer-cache", attributes: .concurrent)

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("ravewatchFlyerImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for url: URL) -> URL {
        // Stable filename: a hash of the URL string, so the cache key is
        // the URL itself and nothing about the file leaks the address.
        let digest = "\(url.absoluteString.hashValue)"
        let safe = digest.replacingOccurrences(of: "-", with: "n")
        return cacheDirectory.appendingPathComponent(safe)
    }

    /// Returns cached data when it exists and is not stale, else nil.
    func cachedData(for url: URL) -> Data? {
        let key = url.absoluteString as NSString
        if let data = memoryCache.object(forKey: key) {
            return data as Data
        }
        let file = fileURL(for: url)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.staleInterval,
              let data = try? Data(contentsOf: file) else {
            return nil
        }
        memoryCache.setObject(data as NSData, forKey: key)
        return data
    }

    /// Downloads the image (or returns the cached copy) — nil on failure.
    func data(for url: URL) async -> Data? {
        if let cached = cachedData(for: url) { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            store(data, for: url)
            return data
        } catch {
            return nil
        }
    }

    private func store(_ data: Data, for url: URL) {
        memoryCache.setObject(data as NSData, forKey: url.absoluteString as NSString)
        queue.async(flags: .barrier) {
            let file = self.fileURL(for: url)
            try? data.write(to: file, options: .atomic)
            self.pruneIfNeeded()
        }
    }

    /// Keeps at most 300 files, dropping the oldest first.
    private func pruneIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        guard files.count > Self.maxObjects else { return }
        let sorted = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
        for file in sorted.prefix(files.count - Self.maxObjects) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
