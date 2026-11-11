import SwiftUI

/// In-app privacy policy, faithfully mirroring the data repo's
/// privacy-policy.html (last updated 22 October 2026).
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy — RaveWatchLagos")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Last updated: 22 October 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("RaveWatchLagos (“the app”) is an event-discovery app for raves and DJ-led nightlife in Lagos, Nigeria. This policy explains what information the app does and does not handle.")

                Group {
                    Text("What the app does NOT collect")
                        .font(.headline)
                    bullet("No user accounts, names, email addresses or phone numbers.")
                    bullet("No advertising identifiers, and no advertising or analytics SDKs.")
                    bullet("No location data (the app never asks for location permission).")
                    bullet("No contacts, photos, or any other personal files.")
                    bullet("No payment information (ticket purchases happen on the organiser’s or ticketing provider’s own website, outside the app).")
                }

                Group {
                    Text("What the app does handle")
                        .font(.headline)
                    Text("Anonymous attending counts. ")
                        .fontWeight(.semibold)
                        + Text("On an event page you can tap “Yes” or “No” to say whether you’re attending. That tap sends only the event’s ID and a +1/−1 change to our counter service (Supabase), which keeps a single running total per event. No identifier of any kind — no name, account, device ID or IP-based profile — is attached to or stored with your tap. The totals are anonymous aggregates shown to all users as an estimate of attendance.")
                    Text("Note: in this first iOS build the attending count is kept on your device only — the Supabase sync is not wired up yet, so no count leaves your phone at all. See the README for details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("On-device preferences. ")
                        .fontWeight(.semibold)
                        + Text("The app stores your followed events, theme choice (night/light) and similar settings in local storage on your phone only. Counts of your own in-app actions (for example, which events you opened or shared) are also kept on your phone only, for a usage summary shown on the device. None of this leaves your phone.")
                    Text("Event feed. ")
                        .fontWeight(.semibold)
                        + Text("The app downloads a public list of events (names, dates, venues, prices, ticket links) from a public file host (GitHub). Downloading that list does not send any personal information about you.")
                }

                Group {
                    Text("Data sharing")
                        .font(.headline)
                    Text("We do not sell, rent or share personal information with anyone — we do not hold any. The anonymous attending totals are public aggregates visible to every user of the app.")
                }

                Group {
                    Text("Children")
                        .font(.headline)
                    Text("The app lists nightlife events, many of which are 18+. It is intended for adults and is not directed at children.")
                }

                Group {
                    Text("Changes")
                        .font(.headline)
                    Text("If this policy changes, the updated version will be posted at this same address with a new “last updated” date.")
                }

                Group {
                    Text("Contact")
                        .font(.headline)
                    Text("Questions about this policy: via Instagram @ravewatchlagos.")
                    if let url = URL(string: "https://github.com/fabat01/ravewatchlagos-data/blob/main/privacy-policy.html") {
                        Link("View the original policy in the data repo",
                             destination: url)
                    }
                    if let url = URL(string: "https://www.instagram.com/ravewatchlagos") {
                        Link("Instagram @ravewatchlagos",
                             destination: url)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
