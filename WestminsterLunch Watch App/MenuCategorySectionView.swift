import SwiftUI

struct MenuCategorySectionView: View {
    let category: MenuCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.name.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            // Keyed by position rather than by `MenuItem.id` (the name):
            // nothing guarantees Flik's item names are unique within a
            // category, and a name-keyed ForEach would silently drop any
            // duplicate instead of listing it.
            ForEach(category.items.indices, id: \.self) { index in
                Text(category.items[index].name)
                    .font(.system(.body, design: .rounded))
            }
        }
    }
}
