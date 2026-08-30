import SwiftUI
import WidgetKit

struct MaloneWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MaloneEntry

    // The accessory families are too small for semantic text styles — these
    // sizes are hand-tuned to fit two Malone items beside three sandwiches.
    // `@ScaledMetric` keeps that exact layout at the default text size while
    // still honouring a larger (or smaller) watch text setting; every label
    // below pairs it with `minimumScaleFactor` so growing text shrinks to fit
    // rather than truncating.
    @ScaledMetric(relativeTo: .caption) private var headerSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var itemSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var messageSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var detailSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 14

    private var deepLinkURL: URL? {
        DeepLink.url(for: .malone)
    }

    private var maloneItemNames: [String] {
        entry.maloneMenu?.categories.flatMap { $0.items.map(\.name) } ?? []
    }

    /// Hawkins's three sandwich-station items ("Sandwich #1", "Sandwich #2",
    /// "Vegetarian Sandwich"), in that order, pulled from whatever Hawkins
    /// data is cached/fetched alongside Malone's. Each of those categories
    /// normally has exactly one item, so this is usually 3 names — but it's
    /// written to tolerate a category having none or more than one.
    private var hawkinsSandwichNames: [String] {
        guard let categories = entry.hawkinsMenu?.categories else { return [] }
        let wanted = DiningLocation.hawkins.preferredCategoryOrder
        return wanted.flatMap { name in
            categories.first(where: { $0.name == name })?.items.map(\.name) ?? []
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangular
            case .accessoryInline:
                inline
            case .accessoryCircular:
                circular
            default:
                rectangular
            }
        }
        .widgetURL(deepLinkURL)
        // Declaring a container background is required, not cosmetic: since
        // watchOS 10 a widget that never declares one isn't laid out by the
        // Smart Stack the way the Simulator forgivingly renders it, and on real
        // hardware it shows up as an empty black card.
        //
        // `.fill.tertiary` is the deliberate choice here — it reads as a solid
        // system-dark fill rather than a translucent one, and that's what looks
        // right on-device. Do not "upgrade" this to a glassier material:
        //
        //  - `.ultraThinMaterial` / `.thinMaterial` are translucent, but they
        //    are NOT the backing Apple's own Smart Stack widgets (Messages,
        //    Health) use. That treatment is not reachable from public API at
        //    all — confirmed by Apple DTS on the developer forums (thread
        //    815955), tracked as feedback FB22059614. watchOS also has no
        //    `glassEffect`/`Glass` API (absent from the watchOS 26.5 SwiftUI
        //    interface; iOS/macOS only), so there is nothing else to reach for.
        //  - AccessoryWidgetBackground is built for watch-face complications
        //    and the Lock Screen; inside a rectangular Smart Stack widget it
        //    draws a stray circular disc. Verified broken on device.
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MALONE               SANDWICHES
    // [item 1]              [Hawkins Sandwich #1]
    // [item 2]              [Hawkins Sandwich #2]
    // +N more                [Hawkins Veg Sandwich]
    private var rectangular: some View {
        Group {
            if maloneItemNames.isEmpty && hawkinsSandwichNames.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MALONE")
                        .font(.system(size: headerSize, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text(entry.errorMessage == nil ? "No menu today" : "Unavailable")
                        .font(.system(size: messageSize))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    maloneColumn
                    if !hawkinsSandwichNames.isEmpty {
                        sandwichesColumn
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Abbreviated weekday of the data being shown, but only when it isn't
    /// today's — so the fallback to an older cached menu (which is what keeps
    /// the widget from rendering empty when the watch can't reach the network)
    /// is never silently passed off as today's lunch.
    private var staleDayLabel: String? {
        guard let menuDate = entry.maloneMenu?.date,
              !Calendar.current.isDate(menuDate, inSameDayAs: entry.date) else { return nil }
        return menuDate.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private var maloneColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(staleDayLabel.map { "MALONE · \($0)" } ?? "MALONE")
                .font(.system(size: headerSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            columnOfItems(Array(maloneItemNames.prefix(2)))
            if maloneItemNames.count > 2 {
                Text("+\(maloneItemNames.count - 2) more")
                    .font(.system(size: detailSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sandwichesColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SANDWICHES")
                .font(.system(size: headerSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            columnOfItems(hawkinsSandwichNames)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if !maloneItemNames.isEmpty {
            let when = staleDayLabel.map { " from \($0)" } ?? ""
            parts.append("Malone lunch\(when): \(maloneItemNames.joined(separator: ", "))")
        }
        if !hawkinsSandwichNames.isEmpty {
            parts.append("Hawkins sandwiches: \(hawkinsSandwichNames.joined(separator: ", "))")
        }
        return parts.isEmpty ? "No menu available" : parts.joined(separator: ". ")
    }

    private func columnOfItems(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Keyed by position rather than by the name itself: nothing
            // guarantees Flik's item names are unique within a day, and a
            // name-keyed ForEach would silently drop any duplicate.
            ForEach(names.indices, id: \.self) { index in
                Text(names[index])
                    .font(.system(size: itemSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Text(maloneItemNames.isEmpty ? "Malone: No menu" : "Malone: \(maloneItemNames.prefix(2).joined(separator: ", "))")
    }

    private var circular: some View {
        VStack(spacing: 1) {
            Image(systemName: "fork.knife")
                .font(.system(size: glyphSize, weight: .bold))
            Text(maloneItemNames.first ?? "Malone")
                .font(.system(size: detailSize))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Malone lunch: \(maloneItemNames.first ?? "no menu available")")
    }
}

struct MaloneWidget: Widget {
    let kind = "MaloneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MaloneWidgetProvider()) { entry in
            MaloneWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Malone Lunch")
        .description("Today's lunch menu at Malone.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
