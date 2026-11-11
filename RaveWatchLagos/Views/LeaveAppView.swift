import SwiftUI

/// Leave-app interstitial, ported from
/// `lib/screens/leave_app_screen.dart`.
///
/// Tapping "Get tickets" no longer drops the user straight out of the
/// app. Like Instagram's external-link page, this screen says plainly
/// that they're leaving, names where they're going, and lets them
/// continue or stay. The copy differs by errand: paying for tickets
/// calls for a due-diligence warning; opening a source is a fact-check
/// the app itself encourages, so it gets directions, not a warning.
///
/// The caller records the tap metric and opens the URL externally only
/// after Continue — `onContinue` fires after the screen is dismissed.
struct LeaveAppView: View {
    enum Kind {
        case tickets
        case source
    }

    let eventName: String
    let url: URL
    let kind: Kind
    let onContinue: () -> Void
    let onStay: () -> Void

    private var domain: String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("🪩")
                .font(.system(size: 44))
                .padding(.top, 24)

            Text("You're on your own now")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 16)

            Text(bodyCopy)
                .font(.body)
                .padding(.top, 12)

            Text("Don't worry, we'll keep your spot warm. The rave will still be here when you get back.")
                .font(.body)
                .padding(.top, 8)

            Spacer()

            Button(action: onContinue) {
                Text("Continue to \(domain)")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: onStay) {
                Text(kind == .tickets ? "Let me double-check first" : "Stay in the app")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .navigationTitle("You're leaving the app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bodyCopy: String {
        switch kind {
        case .tickets:
            return "Tickets for \(eventName) live on \(domain), which is outside RaveWatchLagos. From here on it's their turf — their prices, their fees, their rules. So do your due diligence: give the date, the tiers and the total one last look before you pay."
        case .source:
            return "This source for \(eventName) lives on \(domain), which is outside RaveWatchLagos — it's the original announcement this listing was built from. If anything there disagrees with what's shown here, the source is the organiser's own word."
        }
    }
}
