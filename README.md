# RaveWatchLagos — iOS

Native iOS (SwiftUI) port of the **RaveWatchLagos** Android app — event discovery
for raves and DJ-led nightlife in Lagos, Nigeria. Instagram: [@ravewatchlagos](https://www.instagram.com/ravewatchlagos).

> **Exact port.** This build (5.0.8, build 97) is a behaviour-for-behaviour port
> of the real Android (Flutter) app, v5.0.8+97, translated from its source
> code — `lib/config.dart`, `lib/main.dart`, `lib/models/event.dart`,
> `lib/data/event_repository.dart`, `lib/screens/*.dart`, `lib/services/*.dart`,
> `lib/widgets/*.dart` and `test/*.dart`. The Android README is outdated
> Phase-1 text; where it conflicts with the code, the code wins. The app
> consumes the same live feed the Android app uses, and the same Supabase
> counter service, with the same endpoints, timeouts and failure contract.

## What it does

- **Feed (home tab)** — Lagos raves and club nights grouped by day
  (Tonight / Tomorrow / This Weekend / Next Weekend / plain date /
  Further Out), entry price on every card, search (name, organiser, venue,
  area, genre, DJ), Area and Genre multi-select sheets (checkboxes, faceted
  counts, "Show N events"), Type menu (All types / Rave / Club Party),
  calendar sheet (Tonight, Tomorrow, This/Next weekend, Weekend after next,
  This/Next week, This/Next month, Custom dates…), Just added pill, live
  attending + following counts overlaid on the feed-published counts,
  violet "new" bar on events you haven't opened yet, and a resume refetch
  when more than 15 minutes passed since the last fetch. No price filter —
  by design, as on Android.
- **Card swipes** — swipe right = Follow (tick sound, purple), swipe left =
  Attend (click sound, green); the card springs back. The destination tab's
  icon + label then blinks once in the action colour.
- **Event pages** — flyer (tap for a full-screen pinch-to-zoom viewer;
  dog-ear fold flips it to the DJ lineup when a lineup exists), date/doors,
  venue + address, Directions (Google Maps) and Bolt / inDrive ride buttons
  (address copied to the clipboard, then the ride app opens — the app
  deliberately does **not** deep-link a destination, as on Android), venues
  by day, description, price tiers in ₦, ticket status + "Get tickets"
  (opens via the leave-app interstitial), follow ("Following — alerts on" /
  "Follow for alerts"), attending Yes/No with a live count, share, age
  limit, unproven-promoter warning, last-verified date, source links
  (each via the leave-app interstitial) and change history.
- **Following** — followed events in date order, plus the alert inbox built
  from followed events' change logs (grouped by event, newest first, max 3
  per event, starts collapsed). List swipes: right = Share, left = Delete
  (with Undo).
- **Attending** — events you said Yes to, in date order, plus share picks.
- **Settings** — theme (Night / Light / System), swipe sounds on/off,
  version label, replay the tutorial, send feedback, report a bug
  (diagnostics: iPhone model + iOS version), privacy policy.
- **First-launch tour** — interactive spotlight walkthrough (11 steps,
  verbatim from Android), Next/Back/Skip, live demo events to swipe on,
  replayable from Settings.
- **Privacy, as documented** — no accounts, no location, no ads or analytics
  SDKs. Followed events, theme and usage counts live on-device only
  (UserDefaults + a JSON file mirror). The event feed downloads the public
  events list from GitHub. Attending/following taps send only an event ID
  and a +1/−1 change to Supabase — see "Attending counts" below.

## Data source

- Live feed: <https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json>
- Data repo: <https://github.com/fabat01/ravewatchlagos-data> (events, flyers,
  privacy policy — all credit belongs to the RaveWatchLagos team / fabat01)
- Bundled fallback: `RaveWatchLagos/Resources/events.json`, a snapshot of the
  feed generated **2026-11-10** (110 events). The app shows it immediately
  (including offline), then replaces it with the live feed when the network
  is available. Source label: Live / Saved copy / Built-in.

## Attending counts — live via Supabase

Attending and following counts are **live**, wired to the same Supabase
project the Android app uses (`Services/SupabaseCounts.swift`, project URL
and publishable anon key taken from the Android app's `lib/config.dart` and
embedded exactly as Android embeds them — the key is a *publishable* key by
design; row-level security restricts it to the counts tables and the bump
RPCs).

- GET `/rest/v1/attending_counts?event_id=eq.<id>&select=count` — one
  event's count (empty rows = 0)
- GET `/rest/v1/attending_counts?select=event_id,count` — all counts in one
  request (feed overlay; same for `following_counts`)
- POST `/rest/v1/rpc/bump_attending` with JSON `{"eid": "<id>", "delta": 1}`
  (or −1) — returns the new total (same for `bump_following`)
- Headers: `apikey` + `Authorization: Bearer <anon key>` +
  `Content-Type: application/json`; 8 s timeout; **null on any failure** =
  "count unknown, hide it" — the UI then falls back to the feed-published
  count plus your own tap on this device.

`LocalAttendingService` remains only as the offline fallback when the
backend is unreachable. No other Supabase data is read or written, and no
identifier of any kind is attached to a tap.

## Requirements

- Xcode 15+, Swift 5, iOS 17.0+
- No external dependencies — SwiftUI + Foundation + AVFoundation only. No
  CocoaPods, SPM packages, UIKit views or storyboards. (A single
  `UIActivityViewController` is used for the share sheet, and
  `UIApplication.shared.open` for ride apps — both behind the SwiftUI
  surface.)
- Portrait only, as on Android.

## Run it

1. Open `RaveWatchLagos.xcodeproj` in Xcode.
2. Select an iPhone simulator (iOS 17+) and press Run (⌘R).
3. No signing setup is needed for the simulator. For a device, set your own
   development team in the target's Signing & Capabilities.

## File map

```
RaveWatchLagos.xcodeproj/            Xcode project (hand-written, no SPM deps)
RaveWatchLagos/
  RaveWatchLagosApp.swift            @main, splash gate, store injection
  Models/Event.swift                 Codable Event/PriceTier/ChangeLog + ₦ + Lagos dates
  Services/EventStore.swift          Live feed -> saved copy -> bundled seed; counts overlay
  Services/UserStore.swift           Follows + attending id sets (triple-redundant), theme
  Services/AttendingService.swift    Protocol + Supabase bump + local fallback
  Services/SupabaseCounts.swift      Raw-HTTP Supabase counts (see above)
  Services/PersistedIdSet.swift      Triple-redundant id set + settings mirror
  Services/MetricsService.swift      On-device usage counts (opens/taps/follows/shares)
  Services/NewEventsStore.swift      Known/unread/latest-adds id sets (violet bar, Just added)
  Services/DateWindow.swift          Calendar presets (Tonight…Next month, custom) + sections
  Services/SoundService.swift        Tick/click sounds (AVAudioSession .ambient, mix)
  Services/TourStore.swift           Tour persistence + the 11 verbatim tour steps
  Services/ToastCenter.swift         Snackbar host (message + optional Undo/action)
  Services/ShareService.swift        Share text builders + share-sheet presenter
  Services/RideLauncher.swift        Clipboard -> Bolt/inDrive open -> App Store fallback
  Services/BugReport.swift           Feedback + bug-report mailto (ravewatchlagos@gmail.com)
  Services/FlyerImageCache.swift     Disk flyer cache (30 days, max 300)
  Services/VersionLabel.swift        "Version 5.0.8 Beta"
  Views/ContentView.swift            Shell: Following · Feed · Attending + tab blink + toast
  Views/FeedView.swift               Feed list, search, filters, calendar, sections
  Views/EventCardView.swift          Card (no flyer) + feed/list swipes
  Views/EventDetailView.swift        Full event page (see "What it does")
  Views/FlippableFlyerView.swift     Flyer with dog-ear flip to the DJ lineup
  Views/FlyerViewerView.swift        Full-screen pinch-to-zoom flyer viewer
  Views/LeaveAppView.swift           Leave-app interstitial (tickets / sources)
  Views/FollowingView.swift          Followed events + alert inbox
  Views/AttendingView.swift          Attending events + share picks
  Views/SettingsView.swift           Appearance, sounds, version, tutorial, feedback
  Views/TourOverlay.swift            Spotlight tour overlay + anchors + demo cards
  Views/SplashView.swift             Splash (logo on black, 2 s) + brand title
  Views/PrivacyPolicyView.swift      In-app privacy text (mirrors privacy-policy.html)
  Resources/events.json              Bundled feed snapshot (2026-11-10, 110 events)
  Resources/tick.wav, click.wav      Swipe sounds (decoded from the Android assets)
  Assets.xcassets/                   AppIcon + deepPurple AccentColor + logo images
  Preview Content/                   Minimal preview assets
```

## Design

- Material 3, deepPurple seed — **the accent changed from v1's neon pink
  #FF2E88 to deep purple #6750A4 (light) / #D0BCFF (dark)** to match the
  Android app's `ColorScheme.fromSeed(deepPurple)`. Night theme is the
  default; Light and System are also offered (System is the one iOS extra).
- Bundle ID: `app.ravewatchlagos.ios`; display name `RaveWatchLagos`;
  deployment target iOS 17.0; version **5.0.8 (build 97)** — the same as
  the Android app.
- Prices in ₦, dates in the Africa/Lagos timezone.
- Sounds: the Android app's own `tick.wav` (right swipe, high click) and
  `click.wav` (left swipe, low click), decoded from its base64 assets and
  bundled here; the logo, splash art and ride-app icons are likewise
  decoded from the Android source's embedded base64.

## Gaps — Android behaviours deliberately not ported

- **Play In-App Updates** — no iOS equivalent; the App Store handles
  updates. Nothing was faked in its place.
- **Android back-button handling** — iOS has no system back button; the
  system back gesture / navigation bar back button is used instead.
- **Leave-app screen** — Android's `leave_app_screen.dart` is an exit
  interstitial ("You're on your own now"); iOS has no programmatic exit,
  so it is an info screen with the same copy and the same Continue / "Let
  me double-check first" choice, and the app stays open.
- **Bolt deep link** — the `bolt://` scheme is best-effort and unverified
  (Bolt publishes no rider deep-link documentation); the App Store page is
  the fallback. inDrive's `indriver://` scheme is verified from inDrive's
  own web-to-app links. Neither app is deep-linked to a destination —
  Android deliberately does not do that either.
- **Feed search vs DJs** — the iOS feed search also matches DJs (per the
  port brief); the Android feed filter matches name/organiser/series/venue/
  area/genres only, not DJs. (Android's `search_screen.dart` is dead code
  and was not ported.)
- **Tour caption placement** — Android docks the caption by measured
  height; iOS uses a simple fit heuristic (below/above/centred, never
  covering a live control).
- **Settings theme** — iOS adds a third "System" option; Android toggles
  night/light only.
- **Metrics** — usage counts are collected on-device but shown nowhere,
  exactly as on Android (the v1 "You" tab's usage summary had no Android
  counterpart and was removed).

## Known limitations

- **Not compiled on this machine**: the project was built on a Linux VM
  with no Xcode or Swift toolchain, so it has not been compiled yet. Open it
  in Xcode and fix any issues the compiler reports — the project file and
  source were validated structurally (see below), but only Xcode can verify
  the build.
- **Supabase live reachability unverified from this machine**: the Supabase
  host answers (unauthenticated requests get the expected 401), but the
  counts-table GETs timed out at 8 s and at 15 s from this VM. The iOS
  implementation uses the exact endpoints with the 8 s timeout and the
  null-on-failure contract, so on a real phone it behaves exactly like
  Android and degrades gracefully to feed counts + local deltas.
- The feed's `flyerImageUrl` is always null, so flyers come from
  `flyerDetailImageUrl` only (105 of 110 events have one; the rest get a
  placeholder).
- Feed quirks handled: dates may be `yyyy-MM-dd` or ISO-8601 datetimes;
  `instagram` is an object (`{"organiser": "@handle"}`); `unprovenPromoter`
  is null for some events; two events have no price tiers; stray `_cl` keys
  are ignored.

## Validation (run on the Linux VM, no Xcode)

1. Python check: every file referenced in `project.pbxproj` exists; object
   IDs unique; build files resolve.
2. Python check: balanced braces/parens/brackets in every `.swift` file.
3. Bundled `Resources/events.json` parses (110 events).
4. AppIcon set complete.
5. `git log --oneline` + `git status` clean; commits pushed to
   `kunmi/RaveWatchLagos-iOS` (verified via `gh api`).
