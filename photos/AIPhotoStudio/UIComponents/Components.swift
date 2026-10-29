import SwiftUI
import UIKit

struct AppButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(FilmToneTheme.button)
                .foregroundStyle(FilmToneTheme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    FilmToneTheme.accent,
                    in: RoundedRectangle(cornerRadius: FilmToneTheme.buttonRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

struct AppSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var displayValue: ((Double) -> String)?
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onReset: () -> Void = {}
    var titleResets = true
    var valueIsAccent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if titleResets {
                    Button(title, action: onReset)
                        .buttonStyle(.plain)
                } else {
                    Text(title)
                }
                Spacer()
                Text(displayValue?(value) ?? value.formatted(.number.precision(.fractionLength(2))))
                    .font(valueIsAccent ? .system(size: 14, weight: .semibold) : .body)
                    .monospacedDigit()
                    .foregroundStyle(valueIsAccent ? FilmToneTheme.accent : FilmToneTheme.secondaryText)
            }
            ThemeSlider(value: $value, range: range, onEditingChanged: onEditingChanged)
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
            .foregroundStyle(FilmToneTheme.accent)
            .frame(width: 44, height: 44)
            .background(
                FilmToneTheme.accent.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(FilmToneTheme.primaryText)
            .background(
                FilmToneTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: FilmToneTheme.cardRadius, style: .continuous)
            )
    }
}

private struct ThemeSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumTrackTintColor = UIColor(FilmToneTheme.accent)
        slider.maximumTrackTintColor = UIColor(FilmToneTheme.sliderTrack)
        slider.thumbTintColor = UIColor(FilmToneTheme.sliderThumb)
        slider.isContinuous = true
        slider.addTarget(context.coordinator, action: #selector(Coordinator.began), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.ended),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        let target = Float(value)
        if !slider.isTracking, slider.value != target {
            slider.value = target
        }
    }

    final class Coordinator: NSObject {
        var parent: ThemeSlider
        private var isEditing = false

        init(_ parent: ThemeSlider) {
            self.parent = parent
        }

        @objc func began(_ sender: UISlider) {
            guard !isEditing else { return }
            isEditing = true
            parent.onEditingChanged(true)
        }

        @objc func changed(_ sender: UISlider) {
            if !isEditing {
                isEditing = true
                parent.onEditingChanged(true)
            }
            parent.value = Double(sender.value)
        }

        @objc func ended(_ sender: UISlider) {
            parent.value = Double(sender.value)
            guard isEditing else { return }
            isEditing = false
            parent.onEditingChanged(false)
        }
    }
}
