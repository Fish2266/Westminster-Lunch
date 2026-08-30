# Westminster Lunch

A watchOS app (plus a Smart Stack widget) that shows the day's Flik dining hall menus for Westminster on your wrist.

The app reads the same public Nutrislice/Flik JSON API that powers
`westminster.flikisdining.com` — no scraping, no API key, no backend of your own.

## Features

- **Two dining halls** — Hawkins and Malone, listed on the home screen.
- **Day browsing** — swipe through past and upcoming days; each day's menu is cached separately.
- **Fully dynamic categories** — sections ("Entrees", "Sandwich #1", …) come straight from Flik. Nothing is hardcoded, so a new category on Flik's side shows up automatically instead of disappearing.
- **Offline-friendly** — the last successful download is cached in a shared App Group container, so the app and widget can render without a network round trip.
- **Malone Smart Stack widget** — supports `accessoryRectangular`, `accessoryInline`, and `accessoryCircular`. The rectangular family shows Malone's first items alongside Hawkins's three sandwich-station items, and tapping it deep-links into the app.
- **Honest staleness** — if the widget has to fall back to an older cached menu, it labels it with that day's weekday rather than passing it off as today's lunch.

## Project layout

```
Shared/                        Code compiled into both the app and the widget
  AppGroup.swift               Shared App Group identifier
  NutrisliceConfig.swift       Builds the week-menu URL
  NutrisliceModels.swift       Raw JSON decoding targets
  Menu.swift                   Display models (DayMenu / MenuCategory / MenuItem)
  DiningLocation.swift         Per-hall slugs, display name, category ordering
  MenuService.swift            Fetch + parse + cache (an actor; the only networking)
  MenuCache.swift              App Group-backed cache, keyed by location and day

WestminsterLunch Watch App/    SwiftUI watch app + deep-link router
MaloneWidget/                  WidgetKit extension (provider, views, bundle)
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

## How the menu API is used

Menus come from a week-at-a-time endpoint:

```
https://westminster.api.flikisdining.com/menu/api/weeks/school/{school}/menu-type/{menuType}/{yyyy}/{MM}/{dd}/
```

`MenuService` requests the week containing the target date and picks out the
matching day. Two details are load-bearing and documented inline in the source:
the month and day must be zero-padded, and the request needs a browser-like
`User-Agent` (the server returns 400 for URLSession's default one).

Adding another dining hall means adding one `DiningLocation` in
[`Shared/DiningLocation.swift`](Shared/DiningLocation.swift) — nothing else changes.

## Widget refresh behavior

The widget prefers cached data and requests at most one network refresh per
calendar day, since a published lunch menu doesn't change during the day. It
races the fetch against a 6-second deadline so the timeline handler always
completes — WidgetKit terminates an extension that overruns its budget, which
renders as an empty black card on real hardware.

## Notes

This is an unofficial personal project and is not affiliated with or endorsed by
Westminster Schools, Flik Hospitality Group, or Nutrislice.
