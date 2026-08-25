import SwiftUI

struct ContentView: View {
    private var todayString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("WESTMINSTER LUNCH")
                        .font(.system(.headline, design: .rounded))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(todayString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                ForEach(DiningLocation.all) { location in
                    NavigationLink(value: location) {
                        LocationCardView(location: location)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
