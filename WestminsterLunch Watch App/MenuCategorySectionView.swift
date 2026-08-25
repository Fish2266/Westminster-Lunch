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

            ForEach(category.items) { item in
                Text(item.name)
                    .font(.system(.body, design: .rounded))
                    .accessibilityLabel(item.name)
            }
        }
    }
}
