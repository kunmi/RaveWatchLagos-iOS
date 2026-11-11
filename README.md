# RaveWatchLagos — iOS

Native iOS (SwiftUI) port of the **RaveWatchLagos** Android app — event discovery
for raves and DJ-led nightlife in Lagos, Nigeria. Instagram: [@ravewatchlagos](https://www.instagram.com/ravewatchlagos).

> **Honest port note.** This is a fresh SwiftUI implementation built from the
> app's public data feed and privacy policy. **No Android source code was
> available**: the data repo (`fabat01/ravewatchlagos-data`) is data-only (its
> README is one line), and the invited repo `fabat01/RaveWatchLagosR` returns
> 404 — it appears to have been deleted or renamed by its owner. So nothing
> here was translated line-by-line from Android source; behaviour was rebuilt
> from the documented feed format and the privacy policy, and it consumes the
> same live feed the Android app uses.

## What it does

- **Discover** — Lagos raves and club nights grouped by day, with search
  (name, organiser, venue, area, genre, DJ) and filters (Rave/Club, genre,
  area, free entry, tickets on sale). Pull to refresh.
- **Event pages** — flyer, date/doors, venue with Apple Maps link, genres,
  DJs, age limit, price tiers in ₦, ticket status, ticket link (opens in
  Safari — purchases happen outside the app), unproven-promoter warning,
  anonymous attending Yes/No with an estimated count, follow, share, source
  links, last-verified date and change log.
- **Following** — events you've hearted, in date order.
- **You** — on-device usage summary (viewed / followed / going / shared),
  Night/Light/System theme (Night is the default), data-source credit,
  privacy policy, Instagram link.
- **Privacy, as documented** — no accounts, no location, no ads or analytics
  SDKs. Followed events, theme and usage counts live on-device only
  (UserDefaults). The event feed downloads the public events list from
  GitHub. Attending taps send only an event ID and a +1/−1 change — see
  "Attending counts" below.

## Data source

- Live feed: <https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json>
- Data repo: <https://github.com/fabat01/ravewatchlagos-data> (events, flyers,
  privacy policy — all credit belongs to the RaveWatchLagos team / fabat01)
- Bundled fallback: `RaveWatchLagos/Resources/events.json`, a snapshot of the
  feed generated **2026-11-10**. The app shows it immediately (including
  offline), then replaces it with the live feed when the network is available.

## Attending counts — Supabase stubbed in v1

The privacy policy says attending taps go to a Supabase counter service.
This first port has **no Supabase project or credentials**, so v1 ships with
`LocalAttendingService` (`Services/AttendingService.swift`): the tap is
recorded on-device only and the UI shows the feed's base `attendingCount`
plus the local delta. Nothing is sent anywhere. The file contains a
clearly-marked TODO with the suggested shape of a `SupabaseAttendingService`
(protocol `AttendingService`, inject it in `RaveWatchLagosApp`) for when
credentials exist.

## Requirements

- Xcode 15+, Swift 5, iOS 17.0+
- No external dependencies — SwiftUI + Foundation only. No CocoaPods, SPM
  packages, UIKit or storyboards.

## Run it

1. Open `RaveWatchLagos.xcodeproj` in Xcode.
2. Select an iPhone simulator (iOS 17+) and press Run (⌘R).
3. No signing setup is needed for the simulator. For a device, set your own
   development team in the target's Signing & Capabilities.

## File map

```
RaveWatchLagos.xcodeproj/            Xcode project (hand-written, no SPM deps)
RaveWatchLagos/
  RaveWatchLagosApp.swift            @main, night theme default, store injection
  Models/Event.swift                 Codable Event/PriceTier/ChangeLog + ₦ + Lagos dates
  Services/EventStore.swift          Bundled snapshot -> live GitHub feed, 30s timeout
  Services/UserStore.swift           Follows, attending answers, theme, stats (UserDefaults)
  Services/AttendingService.swift    Protocol + local-only v1 + Supabase TODO
  Views/ContentView.swift            TabView: Discover / Following / You
  Views/DiscoverView.swift           Day-grouped list, search, filters, pull-to-refresh
  Views/EventRow.swift               Flyer thumb, name, date, place, genres, price, badge
  Views/EventDetailView.swift        Full event page (see "What it does")
  Views/FollowingView.swift          Followed events
  Views/ProfileView.swift            "You": stats, theme, data credit, links
  Views/PrivacyPolicyView.swift      In-app privacy text (mirrors privacy-policy.html)
  Resources/events.json              Bundled feed snapshot (2026-11-10, 110 events)
  Assets.xcassets/                   AppIcon (from the repo's "App icon.png") + AccentColor
  Preview Content/                   Minimal preview assets
```

## Design

- Dark-first "night" theme (near-black background, white text), light theme
  supported via the picker.
- Accent: neon pink **#FF2E88** (matches the app icon).
- Bundle ID: `app.ravewatchlagos.ios`; display name `RaveWatchLagos`;
  deployment target iOS 17.0.
- Prices in ₦, dates in the Africa/Lagos timezone.

## Roadmap

- Wire up the Supabase attending counter (see TODO in
  `Services/AttendingService.swift`).
- Push notifications for followed events (would need a backend + permission).
- Add to Calendar export.
- Offline flyer caching (currently `AsyncImage` with in-memory caching only).

## Known limitations

- **Not compiled on this machine**: the project was built on a Linux VM
  with no Xcode or Swift toolchain, so it has not been compiled yet. Open it
  in Xcode and fix any issues the compiler reports — the project file and
  source were validated structurally (see below), but only Xcode can verify
  the build.
- The feed's `flyerImageUrl` is always null, so flyers come from
  `flyerDetailImageUrl` only (105 of 110 events have one; the rest get a
  placeholder).
- Feed quirks handled: dates may be `yyyy-MM-dd` or ISO-8601 datetimes;
  `instagram` is an object (`{"organiser": "@handle"}`); `unprovenPromoter`
  is null for some events; two events have no price tiers; stray `_cl` keys
  are ignored.
