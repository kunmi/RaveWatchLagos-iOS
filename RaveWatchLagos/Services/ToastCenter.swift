import Foundation

/// A snackbar, as the Flutter app shows it: a short message at the
/// bottom of the screen, optionally with one action (Undo). The ride
/// buttons show theirs for 2 seconds; card deletes show theirs for 3.
@MainActor
final class ToastCenter: ObservableObject {
    struct Toast {
        let message: String
        let actionLabel: String?
        let action: (() -> Void)?
    }

    @Published private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: TimeInterval = 3,
              actionLabel: String? = nil, action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        current = Toast(message: message, actionLabel: actionLabel, action: action)
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
