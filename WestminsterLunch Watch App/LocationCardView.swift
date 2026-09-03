import SwiftUI

struct LocationCardView: View {
    let location: DiningLocation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: location.symbolName)
                .font(.title3)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(location.displayName)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.displayName) lunch menu")
        .accessibilityHint("Opens the lunch menu, starting with today")
    }
}
