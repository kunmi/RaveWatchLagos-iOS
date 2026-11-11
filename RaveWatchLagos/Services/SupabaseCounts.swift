import Foundation

/// Supabase configuration, mirroring `lib/config.dart` in the Flutter app.
///
/// The attending-counts backend is Supabase (free tier). The URL and the
/// anon key are the same values the Android app embeds in its config: the
/// anon key is a PUBLISHABLE key by design — row-level security restricts
/// it to the counts tables and the bump RPCs, so anonymous users can only
/// move a counter by ±1 per call and read counts, nothing else. It is not
/// a secret key (there is no service_role key anywhere in the source).
/// While unconfigured, the app runs fully — attending works on-device and
/// counts are hidden.
enum SupabaseConfig {
    static let url = "https://vcnrhitqpdhlknqmxvkh.supabase.co"
    static let anonKey = "sb_publishable_5hRCqSYu5wG2NzrHlSBFpw_TYK34myo"

    static var countsEnabled: Bool { !url.isEmpty && !anonKey.isEmpty }
}

/// Cross-user attending counts, backed by Supabase (Postgres) over its
/// REST API — no SDK, just HTTP. Two operations:
///  - fetch:  GET  /rest/v1/attending_counts?event_id=eq.<id>&select=count
///  - bump:   POST /rest/v1/rpc/bump_attending {eid, delta} → new count
/// The bump is a security-definer RPC, so anonymous users can only move
/// a counter by ±1 per call and read counts — nothing else. Returns
/// nil whenever the backend is unconfigured or unreachable; callers
/// treat nil as "count unknown" and simply hide it.
/// Ported line-for-line from `lib/services/attending_counts.dart`.
final class SupabaseAttendingCounts {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        session = URLSession(configuration: configuration)
    }

    var enabled: Bool { SupabaseConfig.countsEnabled }

    private var headers: [String: String] {
        [
            "apikey": SupabaseConfig.anonKey,
            "Authorization": "Bearer \(SupabaseConfig.anonKey)",
            "Content-Type": "application/json",
        ]
    }

    func fetchCount(eventID: String) async -> Int? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/attending_counts?event_id=eq.\(eventID)&select=count") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first else { return 0 }
            if rows.isEmpty { return 0 }
            return (first["count"] as? NSNumber)?.intValue
        } catch {
            return nil
        }
    }

    /// All counters in one request — the feed cards overlay these live
    /// totals on the feed-published counts, so a Yes tap shows on cards
    /// within one app refresh instead of waiting for the next daily
    /// sweep publish. Returns nil when unconfigured or unreachable
    /// (callers keep the feed values then).
    func fetchAllCounts() async -> [String: Int]? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/attending_counts?select=event_id,count") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            var result: [String: Int] = [:]
            for row in rows {
                if let eventID = row["event_id"] as? String,
                   let count = row["count"] as? NSNumber {
                    result[eventID] = count.intValue
                }
            }
            return result
        } catch {
            return nil
        }
    }

    /// Moves the counter by `delta` (+1 attending, −1 not attending) and
    /// returns the new total, or nil on any failure.
    func bump(eventID: String, delta: Int) async -> Int? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/rpc/bump_attending") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["eid": eventID, "delta": delta])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return (try? JSONSerialization.jsonObject(with: data) as? NSNumber)?.intValue
        } catch {
            return nil
        }
    }
}

/// Cross-user FOLLOWING counts — the attending counter's twin, backed by
/// the same Supabase project:
///  - fetch:  GET  /rest/v1/following_counts?event_id=eq.<id>&select=count
///  - bump:   POST /rest/v1/rpc/bump_following {eid, delta} → new count
/// Same contract as attending: null whenever the backend is unconfigured,
/// the following table doesn't exist yet, or the request fails; callers
/// treat null as "count unknown" and simply hide it.
/// Ported from `lib/services/following_counts.dart`.
final class SupabaseFollowingCounts {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        session = URLSession(configuration: configuration)
    }

    var enabled: Bool { SupabaseConfig.countsEnabled }

    private var headers: [String: String] {
        [
            "apikey": SupabaseConfig.anonKey,
            "Authorization": "Bearer \(SupabaseConfig.anonKey)",
            "Content-Type": "application/json",
        ]
    }

    func fetchCount(eventID: String) async -> Int? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/following_counts?event_id=eq.\(eventID)&select=count") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first else { return 0 }
            if rows.isEmpty { return 0 }
            return (first["count"] as? NSNumber)?.intValue
        } catch {
            return nil
        }
    }

    /// All following counters in one request — the feed cards overlay
    /// these live totals on the feed-published counts.
    func fetchAllCounts() async -> [String: Int]? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/following_counts?select=event_id,count") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            var result: [String: Int] = [:]
            for row in rows {
                if let eventID = row["event_id"] as? String,
                   let count = row["count"] as? NSNumber {
                    result[eventID] = count.intValue
                }
            }
            return result
        } catch {
            return nil
        }
    }

    /// Moves the counter by `delta` (+1 follow, −1 unfollow) and returns
    /// the new total, or nil on any failure.
    func bump(eventID: String, delta: Int) async -> Int? {
        guard enabled else { return nil }
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/rpc/bump_following") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["eid": eventID, "delta": delta])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return (try? JSONSerialization.jsonObject(with: data) as? NSNumber)?.intValue
        } catch {
            return nil
        }
    }
}
