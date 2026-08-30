# Westminster Lunch

A watchOS app (plus a Smart Stack widget) that shows the day's Flik dining hall menus for Westminster on your wrist.

The app reads the same public Nutrislice/Flik JSON API that powers
`westminster.flikisdining.com` — no scraping, no API key, no backend of your own.

## Features

- **Two dining halls** — Hawkins and Malone, listed on the home screen.
- **Day browsing** — swipe through past and upcoming days. Weekends are skipped entirely: no food is served, so swiping right from Friday lands on Monday.
- **Fully dynamic categories** — sections ("Entrees", "Sandwich #1", …) come straight from Flik. Nothing is hardcoded, so a new category on Flik's side shows up automatically instead of disappearing.
- **Frugal with the network** — one response covers a whole week, and a menu already downloaded today isn't downloaded again, so paging across the week costs about one request. Pull-to-refresh and the Refresh button always fetch.
- **Offline-friendly** — the last successful download is cached in a shared App Group container, so the app and widget can render without a network round trip. Entries older than 30 days are pruned automatically.
- **Malone Smart Stack widget** — supports `accessoryRectangular`, `accessoryInline`, and `accessoryCircular`. The rectangular family shows Malone's first items alongside Hawkins's three sandwich-station items, and tapping it opens that menu in the app.
- **Honest staleness** — if the widget has to fall back to an older cached menu, it labels it with that day's weekday rather than passing it off as today's lunch.
- **Respects the watch text size** — the widget's hand-tuned layout scales with the system setting instead of ignoring it.

## Project layout

```
Shared/                        Code compiled into both the app and the widget
  AppGroup.swift               Shared App Group identifier
  NutrisliceConfig.swift       Builds the week-menu URL
  NutrisliceModels.swift       Raw JSON decoding targets
  Menu.swift                   Display models (DayMenu / MenuCategory / MenuItem)
  DiningLocation.swift         Per-hall slugs, display name, category ordering
  DeepLink.swift               Builds and parses the widget's westminsterlunch:// URL
  SchoolCalendar.swift         Weekday/weekend rules (weekends are never pages)
  MenuService.swift            Fetch + parse + cache (an actor; the only networking)
  MenuCache.swift              App Group-backed cache, keyed by location and day

WestminsterLunch Watch App/    SwiftUI watch app + deep-link router
MaloneWidget/                  WidgetKit extension (provider, views, bundle)
Tests/                         Unit tests for Shared/ (see "Tests" below)
```

Data flow:

```
Flik server → MenuService → MenuCache (App Group) → Watch app UI
                                                  ↘ Malone widget
```

## Requirements

- Xcode with a watchOS 26.5 SDK
- Swift 5
- An Apple Watch or watch simulator running watchOS 26.5+

## Building

1. Open `WestminsterLunch.xcodeproj`.
2. Set your own team and bundle identifier prefix on both the
   `WestminsterLunch Watch App` and `MaloneWidgetExtension` targets.
3. Add the **App Groups** capability to *both* targets using the same group id,
   then update `AppGroup.identifier` in [`Shared/AppGroup.swift`](Shared/AppGroup.swift)
   to match. Without this the widget can't read the app's cached menus.
4. Run the `WestminsterLunch Watch App` scheme.

## Tests

Everything in `Shared/` is plain Foundation with no watchOS dependency, so it is
unit tested on the Mac — no simulator, no device, no signing:

```
swift test
```

`Package.swift` exists only for this. It wraps the *same* files the app and the
widget compile (`path: "Shared"`) as a library, so the tests exercise the real
code rather than a copy. It does not build the app, and
`WestminsterLunch.xcodeproj` ignores it — Xcode remains the only way to build and
run the watch app itself.

Covered: `SchoolCalendar`'s weekend skipping; `MenuCache`'s keying, pruning, and
most-recent lookup; `DeepLink`'s round trip; and `MenuService`'s parsing (section
grouping, category ordering, weekend filtering, malformed payloads), request
economy, and offline fallbacks. The network is stubbed with a `URLProtocol` and
the cache points at a throwaway `UserDefaults` suite, so a run never touches the
real App Group container and leaves nothing behind.

The SwiftUI layer is not covered — the view-identity bugs described below were
found on-device, not by these tests.

## How the menu API is used

Menus come from a week-at-a-time endpoint:

```
https://westminster.api.flikisdining.com/menu/api/weeks/school/{school}/menu-type/{menuType}/{yyyy}/{MM}/{dd}/
```

`MenuService` requests the week containing the target date and picks out the
matching day. Three details are load-bearing, documented inline in the source and
pinned by tests:

- the month and day must be zero-padded (`08`, not `8`),
- the trailing slash must survive (note that `URL.path` normalizes it away, so
  assert against `absoluteString`),
- and the request needs a browser-like `User-Agent` — the server returns 400 for
  URLSession's default one.

Adding another dining hall means adding one `DiningLocation` in
[`Shared/DiningLocation.swift`](Shared/DiningLocation.swift) — nothing else changes.

## Deep linking

Tapping the widget opens the app at that hall's menu via:

```
westminsterlunch://open?location={schoolSlug}
```

[`Shared/DeepLink.swift`](Shared/DeepLink.swift) both builds and parses this URL,
from the same `schoolSlug` the app looks locations up by. That matters: the two
were once written out separately — the widget hardcoded `location=malone` while
the app resolved the value as a Nutrislice slug
(`uppermiddle-school-malone-dining-hall`) — so the lookup always failed and the
link silently did nothing but launch the app.

The other half is view identity. `AppRouter` replaces the navigation path rather
than growing it, so following the link while already viewing a *different* hall
leaves the stack one entry deep both before and after. SwiftUI then reuses the
existing screen's identity, and `MenuDayView`'s `@StateObject` — created once,
capturing the old location — keeps serving the previous hall's menu under the new
title. The `.id(location)` on the `navigationDestination` in
`WestminsterLunchApp` is what declares the two halls to be different screens.

The same reasoning is why the day pages are keyed by their `Date` rather than by
position in the array.

## Widget refresh behavior

The widget prefers cached data and requests at most one network refresh per
calendar day, since a published lunch menu doesn't change during the day. It
races the fetch against a 6-second deadline so the timeline handler always
completes — WidgetKit terminates an extension that overruns its budget, which
renders as an empty black card on real hardware.

## Notes

This is an unofficial personal project and is not affiliated with or endorsed by
Westminster Schools, Flik Hospitality Group, or Nutrislice.
