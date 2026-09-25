import SwiftUI

struct AppButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
    }
}

struct AppSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .tint(.indigo)
        }
    }
}

struct AppToolbar<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 16) { content }
            .padding()
            .background(.ultraThinMaterial)
    }
}

struct AppSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            content
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}

struct AppIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .frame(width: 44, height: 44)
            .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}
