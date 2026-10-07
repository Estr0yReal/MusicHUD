import Foundation

/// Keeps the last few album artwork blobs in memory.
///
/// Artwork is a 1200×1200 JPEG — around 340 KB for a typical track. Reading it
/// through Apple Events is cheap (~6 ms measured) but not free, and re-reading
/// it on every poll would be wasteful, so the provider fetches it only when the
/// track changes and the cache keeps recent covers around for skipping back and
/// forth through a few tracks.
///
/// Keyed by Music.app's `persistent ID`, which is stable across launches, with
/// an `artist|album|title` fallback for anything that lacks one.
///
/// Only successful reads are cached. Missing artwork is deliberately *not*
/// remembered, because it is usually a temporary state rather than a fact.
public final class ArtworkCache {

    /// Fallback key for tracks with no persistent ID.
    public static func fallbackKey(title: String, artist: String, album: String) -> String {
        "\(artist)\u{1F}\(album)\u{1F}\(title)"
    }

    /// The cache key for a track. Prefers the stable persistent ID.
    public static func key(for metadata: TrackMetadata) -> String {
        let id = metadata.persistentID.trimmingCharacters(in: .whitespaces)
        if !id.isEmpty { return id }
        return fallbackKey(title: metadata.title, artist: metadata.artist, album: metadata.album)
    }

    private let capacity: Int
    private var storage: [String: Data] = [:]
    /// Recency order, least recently stored first. Used to evict.
    private var order: [String] = []

    public init(capacity: Int = 6) {
        self.capacity = max(capacity, 1)
    }

    public var count: Int { storage.count }

    public func data(for key: String) -> Data? {
        storage[key]
    }

    public func store(_ data: Data, for key: String) {
        // Only real blobs are cached. An earlier design also recorded "this
        // track has no artwork" so we could stop asking, but that turns a
        // temporary condition into a permanent one: Music.app frequently has no
        // cover yet for a track that has just started streaming, and the cover
        // arrives a moment later. Recording its absence meant never noticing.
        guard !data.isEmpty else { return }

        // True LRU, not FIFO: re-storing a key makes it the most recent. This
        // matters for the case the cache exists to serve — skipping back and
        // forth between a few tracks — where FIFO would evict the cover the
        // user just came back to.
        if let existing = order.firstIndex(of: key) {
            order.remove(at: existing)
        }
        order.append(key)
        storage[key] = data
        evictIfNeeded()
    }

    public func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private func evictIfNeeded() {
        while order.count > capacity {
            let oldest = order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }
}
