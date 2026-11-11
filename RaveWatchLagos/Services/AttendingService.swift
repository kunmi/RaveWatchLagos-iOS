import Foundation

/// Reports anonymous attending counts, and returns the new total.
///
/// Per the privacy policy, an attending tap sends ONLY the event's ID
/// and a +1/−1 change to the counter service. No identifier of any kind
/// — no name, account, device ID or IP-based profile — is attached to
/// or stored with the tap. The totals are anonymous aggregates shown to
/// all users as an estimate of attendance.
///
/// The return value is the new total from the backend, or nil when the
/// backend is unreachable — callers treat nil as "count unknown" and
/// fall back to local arithmetic (the locally-applied tap on a failed
/// bump is acceptable, per the Flutter app's v1.9 audit note).
protocol AttendingService {
    /// Reports a change for an event. `delta` is +1 (now attending) or
    /// −1 (no longer attending). Returns the new total, or nil.
    func sendAttendingChange(eventID: String, delta: Int) async -> Int?
}

// MARK: - Local-only implementation (offline fallback)

/// Records the change on-device only and reports nothing to any
/// server. Used when the Supabase backend is unreachable: the displayed
/// count is the feed's base `attendingCount` plus the local delta, and
/// a failed count sync must never block the UI.
final class LocalAttendingService: AttendingService {
    func sendAttendingChange(eventID: String, delta: Int) async -> Int? {
        // Local-only: nothing to send. The delta is already persisted
        // in UserStore.attendingIDs and reflected in the UI immediately.
        nil
    }
}

// MARK: - Live Supabase implementation

/// The live implementation: POSTs the +1/−1 bump to the Supabase
/// `bump_attending` RPC (a security-definer function, so anonymous
/// users can only move a counter by ±1 per call) and returns the new
/// total. On any failure it returns nil and the caller falls back to
/// local arithmetic — the tap itself is never lost.
final class SupabaseAttendingService: AttendingService {
    private let counts = SupabaseAttendingCounts()

    func sendAttendingChange(eventID: String, delta: Int) async -> Int? {
        await counts.bump(eventID: eventID, delta: delta)
    }
}
