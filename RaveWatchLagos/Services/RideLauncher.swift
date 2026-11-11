import Foundation
import UIKit

/// Ride buttons, ported from `lib/services/ride_launcher.dart` and
/// `lib/services/ride_app_icons.dart`.
///
/// Android deliberately does NOT deep-link a destination — Bolt
/// publishes no rider deep-link docs and inDrive offers nothing
/// public — so the tap copies the venue address to the clipboard,
/// shows "Address copied — paste it in <name>", waits 650 ms, then
/// launches the app by package, falling back to its Play Store page
/// when it isn't installed.
///
/// iOS, same shape: copy the address, show the same message, then
/// open the app by its URL scheme (`indriver://` is documented in
/// inDrive's own web-to-app links; `bolt://` is a best-effort attempt
/// — Bolt publishes no rider deep-link docs either) and fall back to
/// its App Store page when the app isn't installed. The address is
/// copied either way, so pasting it as the destination always works.
/// Brand colours: Bolt #2A9C64, inDrive #C1F21D (dark text #0C0E0A).
enum RideLauncher {
    enum RideApp {
        case bolt
        case inDrive

        var name: String {
            switch self {
            case .bolt: return "Bolt"
            case .inDrive: return "inDrive"
            }
        }

        /// Best-effort app URL (opens the app's home screen when installed).
        var appURL: URL? {
            switch self {
            case .bolt: return URL(string: "bolt://")
            case .inDrive: return URL(string: "indriver://")
            }
        }

        /// App Store page, opened when the app isn't installed.
        var storeURL: URL {
            switch self {
            case .bolt:
                return URL(string: "https://apps.apple.com/us/app/bolt-request-a-ride/id675033630")!
            case .inDrive:
                return URL(string: "https://apps.apple.com/us/app/indrive-save-on-city-rides/id780125801")!
            }
        }

        var iconName: String {
            switch self {
            case .bolt: return "BoltIcon"
            case .inDrive: return "InDriveIcon"
            }
        }
    }

    /// Copies `rideAddress` to the clipboard, then — after the same
    /// 650 ms beat Android uses — opens the ride app, or its App Store
    /// page when it isn't installed. The `onCopied` callback fires
    /// immediately so the UI can show "Address copied — paste it in
    /// <name>" while the app opens.
    static func launch(_ app: RideApp, rideAddress: String, onCopied: @escaping (String) -> Void) {
        UIPasteboard.general.string = rideAddress
        onCopied("Address copied — paste it in \(app.name)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            if let appURL = app.appURL {
                UIApplication.shared.open(appURL, options: [:]) { opened in
                    if !opened {
                        UIApplication.shared.open(app.storeURL)
                    }
                }
            } else {
                UIApplication.shared.open(app.storeURL)
            }
        }
    }
}
