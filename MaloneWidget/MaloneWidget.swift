import SwiftUI
import WidgetKit

struct MaloneWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MaloneEntry

    private var deepLinkURL: URL? {
        URL(string: "westminsterlunch://open?location=malone")
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
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(entry.errorMessage == nil ? "No menu today" : "Unavailable")
                        .font(.system(size: 12))
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

    private var maloneColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("MALONE")
                .font(.system(size: 11, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            columnOfItems(maloneItemNames.prefix(2))
            if maloneItemNames.count > 2 {
                Text("+\(maloneItemNames.count - 2) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sandwichesColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SANDWICHES")
                .font(.system(size: 11, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            columnOfItems(hawkinsSandwichNames)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if !maloneItemNames.isEmpty {
            parts.append("Malone lunch: \(maloneItemNames.joined(separator: ", "))")
        }
        if !hawkinsSandwichNames.isEmpty {
            parts.append("Hawkins sandwiches: \(hawkinsSandwichNames.joined(separator: ", "))")
        }
        return parts.isEmpty ? "No menu available" : parts.joined(separator: ". ")
    }

    private func columnOfItems<S: Sequence>(_ names: S) -> some View where S.Element == String {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(names), id: \.self) { name in
                Text(name)
                    .font(.system(size: 11))
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
                .font(.system(size: 14, weight: .bold))
            Text(maloneItemNames.first ?? "Malone")
                .font(.system(size: 9))
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
