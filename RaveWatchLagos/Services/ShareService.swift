import Foundation
import UIKit

/// Share text, ported from `lib/services/share_event.dart`.
///
/// Single event:
///   name
///   "<date> <year> · <doors> · <venue> · <area>"
///   "Entry: <price>"
///   "Tickets: <link>" or the ticket note
///   "— via RaveWatchLagos"
///   "Get the app to see more events"
///   <Play store URL>
///
/// Picks (Attending / Following list):
///   "I'm attending/following this/these N event(s) in Lagos:"
///   signature + app lines, a blank line, then numbered picks each
///   with its ticket route.
/// Sharing counts a metric per event; sharing an empty list is a no-op.
enum ShareService {
    static let playStoreURL = "https://play.google.com/store/apps/details?id=com.ravewatchlagos.ravewatchlagos"

    /// The "<date> <year> · <doors> · <venue> · <area>" line.
    static func eventLine(_ event: Event) -> String {
        var parts: [String] = []
        var datePart = event.dateLabel
        if let start = event.startDate {
            let year = Event.lagosCalendar.component(.year, from: start)
            datePart += " \(year)"
        }
        parts.append(datePart)
        if let doors = event.doorsTime, !doors.isEmpty { parts.append(doors) }
        if let venue = event.venueName, !venue.isEmpty { parts.append(venue) }
        if let area = event.area, !area.isEmpty { parts.append(area) }
        return parts.joined(separator: " · ")
    }

    static func shareText(for event: Event) -> String {
        var lines: [String] = [event.name, eventLine(event)]
        lines.append("Entry: \(event.entryPriceDisplay)")
        if let link = event.ticketLink, !link.isEmpty {
            lines.append("Tickets: \(link)")
        } else if let note = event.ticketNote, !note.isEmpty {
            lines.append(note)
        }
        lines.append("— via RaveWatchLagos")
        lines.append("Get the app to see more events")
        lines.append(playStoreURL)
        return lines.joined(separator: "\n")
    }

    /// One message for a whole list of picks. Returns nil for an empty list.
    static func sharePicksText(_ events: [Event], attending: Bool) -> String? {
        guard !events.isEmpty else { return nil }
        let verb = attending ? "attending" : "following"
        let count = events.count
        var lines: [String] = [
            "I'm \(verb) \(count == 1 ? "this" : "these \(count)") event\(count == 1 ? "" : "s") in Lagos:",
            "— via RaveWatchLagos",
            "Get the app to see more events",
            playStoreURL,
            "",
        ]
        for (index, event) in events.enumerated() {
            lines.append("\(index + 1). \(event.name) — \(eventLine(event))")
            if let link = event.ticketLink, !link.isEmpty {
                lines.append("   Tickets: \(link)")
            } else if let note = event.ticketNote, !note.isEmpty {
                lines.append("   \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Presents the iOS share sheet for already-built share text.
    static func presentShareSheet(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}
