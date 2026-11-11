import Foundation

/// Reports anonymous attending counts.
///
/// Per the privacy policy, an attending tap sends ONLY the event's ID and a
/// +1/−1 change to the counter service. No identifier of any kind — no name,
/// account, device ID or IP-based profile — is attached to or stored with
/// the tap. The totals are anonymous aggregates shown to all users as an
/// estimate of attendance.
protocol AttendingService {
    /// Reports a change for an event. `delta` is +1 (now attending), −1
    /// (now not attending), or a net change when a previous answer changes.
    func sendAttendingChange(eventID: String, delta: Int) async
}

// MARK: - Local-only implementation (v1)

/// v1 implementation: records the change on-device only and reports nothing
/// to any server. The displayed count is the feed's base `attendingCount`
/// plus the local delta from `UserStore`.
///
/// This is intentional, not an oversight: the iOS port has no Supabase
/// project or credentials yet, and inventing a network call to a service
/// that does not exist would be worse than a clearly-marked stub.
final class LocalAttendingService: AttendingService {
    func sendAttendingChange(eventID: String, delta: Int) async {
        // Local-only: nothing to send. The delta is already persisted in
        // UserStore.attendingState and reflected in the UI immediately.
    }
}

// MARK: - TODO: Supabase implementation (roadmap)

/*
 TODO (Supabase): implement a `SupabaseAttendingService` conforming to
 `AttendingService`, and inject it in `RaveWatchLagosApp` once the project
 has credentials. Suggested shape — do NOT ship with placeholder keys:

     final class SupabaseAttendingService: AttendingService {
         private let url: URL        // e.g. https://<project>.supabase.co/rest/v1/rpc/attending_delta
         private let anonKey: String // Supabase anon key, from the app config — never hard-coded
         func sendAttendingChange(eventID: String, delta: Int) async {
             // POST {"event_id": eventID, "delta": delta} with
             // `apikey` / `Authorization: Bearer <anonKey>` headers.
             // The server-side function must apply the delta to a single
             // running total per event and store NO identifier with it.
             // On failure, swallow the error: the local delta in UserStore
             // is the source of truth for this device, and a failed count
             // sync must never block the UI.
         }
     }

 The feed's `attendingCount` remains the base total; the Supabase aggregate
 replaces it once the live feed starts publishing server totals.
 */
