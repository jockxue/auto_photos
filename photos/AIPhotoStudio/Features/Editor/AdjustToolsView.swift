import SwiftUI

enum AdjustToolGroup: String, CaseIterable, Identifiable {
    case all, light, color, detail, effects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .light: "Light"
        case .color: "Color"
        case .detail: "Detail"
        case .effects: "Effects"
        }
    }
}

enum AdjustTool: String, CaseIterable, Identifiable {
    case exposure, contrast, saturation, highlights, shadows, whiteBalance
    case sharpness, grain, vignette, skinTone
    case brightness, whites, blacks, vibrance, clarity, noiseReduction, curves

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exposure: "Exposure"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .whiteBalance: "White Balance"
        case .sharpness: "Sharpen"
        case .grain: "Grain"
        case .vignette: "Vignette"
        case .skinTone: "Skin Tone"
        case .brightness: "Brightness"
        case .whites: "Whites"
        case .blacks: "Blacks"
        case .vibrance: "Vibrance"
        case .clarity: "Clarity"
        case .noiseReduction: "Noise Reduction"
        case .curves: "Curves"
        }
    }

    var symbol: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .contrast: "circle.lefthalf.filled"
        case .saturation: "drop.fill"
        case .highlights: "circle.tophalf.filled"
        case .shadows: "circle.bottomhalf.filled"
        case .whiteBalance: "thermometer.medium"
        case .sharpness: "triangle.lefthalf.filled"
        case .grain: "aqi.medium"
        case .vignette: "camera.metering.center.weighted"
        case .skinTone: "face.smiling"
        case .brightness: "lightbulb"
        case .whites: "sun.min"
        case .blacks: "moon"
        case .vibrance: "drop.halffull"
        case .clarity: "camera.aperture"
        case .noiseReduction: "wand.and.stars"
        case .curves: "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var group: AdjustToolGroup {
        switch self {
        case .exposure, .brightness, .contrast, .highlights, .shadows, .whites, .blacks: .light
        case .whiteBalance, .saturation, .vibrance, .skinTone: .color
        case .sharpness, .clarity, .noiseReduction: .detail
        case .grain, .vignette, .curves: .effects
        }
    }

    /// Empty for curves, which edits `EditState.curves` instead of adjustment values.
    var keys: [AdjustmentKey] {
        switch self {
        case .exposure: [.exposure]
        case .contrast: [.contrast]
        case .saturation: [.saturation]
        case .highlights: [.highlights]
        case .shadows: [.shadows]
        case .whiteBalance: [.temperature, .tint]
        case .sharpness: [.sharpness]
        case .grain: [.grain]
        case .vignette: [.vignette]
        case .skinTone: [.skinHue, .skinLuminance]
        case .brightness: [.brightness]
        case .whites: [.whites]
        case .blacks: [.blacks]
        case .vibrance: [.vibrance]
        case .clarity: [.clarity]
        case .noiseReduction: [.noiseReduction]
        case .curves: []
        }
    }

    static func tools(in group: AdjustToolGroup) -> [AdjustTool] {
        group == .all ? allCases : allCases.filter { $0.group == group }
    }

    @MainActor
    func isEdited(in session: EditorSession) -> Bool {
        if self == .curves { return !session.curves.isIdentity }
        return keys.contains { session.value(for: $0) != $0.descriptor.defaultValue }
    }
}

struct AdjustToolStrip: View {
    @ObservedObject var session: EditorSession
    let onSelect: (AdjustTool) -> Void
    @State private var group: AdjustToolGroup = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustToolGroup.allCases) { item in
                        ToolChip(title: item.title, selected: group == item) { group = item }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(AdjustTool.tools(in: group)) { tool in
                        toolButton(tool)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func toolButton(_ tool: AdjustTool) -> some View {
        let edited = tool.isEdited(in: session)
        return CircleToolButton(symbol: tool.symbol, title: tool.title, highlighted: edited, showsDot: edited) {
            onSelect(tool)
        }
    }
}

struct CircleToolButton: View {
    let symbol: String
    let title: String
    var highlighted = false
    var showsDot = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(highlighted ? FilmToneTheme.accent : FilmToneTheme.primaryText)
                    .frame(width: 48, height: 48)
                    .background(FilmToneTheme.cardBackground, in: Circle())
                    .overlay(Circle().strokeBorder(highlighted ? FilmToneTheme.accent : .clear, lineWidth: 1.5))
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle().fill(FilmToneTheme.accent).frame(width: 6, height: 6).offset(x: 2, y: -2)
                        }
                    }
                Text(L10n.text(title))
                    .font(.system(size: 11))
                    .foregroundStyle(highlighted ? FilmToneTheme.accent : FilmToneTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(title))
    }
}

/// Changes made here stay one undo step: ✕ restores the state from when the panel opened.
struct AdjustToolPanel: View {
    let tool: AdjustTool
    @ObservedObject var session: EditorSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                roundButton("xmark", label: "Cancel", filled: false) {
                    session.cancelToolEdit()
                    onClose()
                }
                Spacer()
                Label(L10n.text(tool.title), systemImage: tool.symbol)
                    .labelStyle(PanelTitleLabelStyle())
                Spacer()
                roundButton("checkmark", label: "Done", filled: true) {
                    session.commitToolEdit()
                    onClose()
                }
            }
            if tool == .curves {
                CurveControls(session: session)
            } else {
                ForEach(tool.keys) { key in
                    sliderRow(key)
                }
                if tool == .skinTone {
                    Text(L10n.text("Skin is detected by color, so warm backgrounds may change too."))
                        .font(.system(size: 11))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
                Button(action: reset) {
                    Label(L10n.text("Reset"), systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(!tool.isEdited(in: session))
                .opacity(tool.isEdited(in: session) ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(FilmToneTheme.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(FilmToneTheme.divider).frame(height: 1)
        }
    }

    private func sliderRow(_ key: AdjustmentKey) -> some View {
        let descriptor = key.descriptor
        let value = session.value(for: key)
        let single = tool.keys.count == 1
        return VStack(spacing: 12) {
            HStack {
                if single {
                    Text(descriptor.displayValue(descriptor.range.lowerBound))
                    Spacer()
                    Text(descriptor.displayValue(value))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.accent)
                    Spacer()
                    Text(descriptor.displayValue(descriptor.range.upperBound))
                } else {
                    Text(L10n.text(Self.rowTitle(key)))
                    Spacer()
                    Text(descriptor.displayValue(value))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.accent)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(FilmToneTheme.secondaryText)
            .monospacedDigit()
            ToolSlider(
                value: Binding(get: { session.value(for: key) }, set: { session.setValue($0, for: key) }),
                range: descriptor.range,
                defaultValue: descriptor.defaultValue,
                gradient: Self.gradient(key)
            )
            .accessibilityLabel(L10n.text(Self.rowTitle(key)))
            .accessibilityValue(descriptor.displayValue(value))
            if let ends = Self.endLabels(key) {
                HStack {
                    Text(L10n.text(ends.0))
                    Spacer()
                    Text(L10n.text(ends.1))
                }
                .font(.system(size: 11))
                .foregroundStyle(FilmToneTheme.tabInactive)
            }
        }
    }

    private func reset() {
        for key in tool.keys {
            session.setValue(key.descriptor.defaultValue, for: key)
        }
    }

    private func roundButton(_ symbol: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? FilmToneTheme.accentText : FilmToneTheme.primaryText)
                .frame(width: 36, height: 36)
                .background(filled ? FilmToneTheme.accent : FilmToneTheme.chipBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(label))
    }

    private static func rowTitle(_ key: AdjustmentKey) -> String {
        switch key {
        case .skinHue: "Hue"
        case .skinLuminance: "Brightness"
        default: key.title
        }
    }

    private static func endLabels(_ key: AdjustmentKey) -> (String, String)? {
        switch key {
        case .temperature: ("Cool", "Warm")
        case .tint: ("Green", "Magenta")
        case .skinHue: ("Rosy", "Yellowish")
        case .vignette: ("Darken Edges", "Lighten Edges")
        default: nil
        }
    }

    private static func gradient(_ key: AdjustmentKey) -> [Color]? {
        switch key {
        case .temperature:
            [Color(red: 0.29, green: 0.56, blue: 0.85), Color(white: 0.85), Color(red: 0.90, green: 0.69, blue: 0.29)]
        case .tint:
            [Color(red: 0.31, green: 0.75, blue: 0.42), Color(white: 0.85), Color(red: 0.78, green: 0.35, blue: 0.78)]
        case .skinHue:
            [Color(red: 0.90, green: 0.54, blue: 0.54), Color(red: 0.91, green: 0.76, blue: 0.63), Color(red: 0.85, green: 0.70, blue: 0.35)]
        default:
            nil
        }
    }
}

private struct PanelTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 15))
                .foregroundStyle(FilmToneTheme.accent)
            configuration.title
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilmToneTheme.primaryText)
        }
    }
}

struct ToolChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.text(title))
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? FilmToneTheme.accentText : FilmToneTheme.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(selected ? FilmToneTheme.accent : FilmToneTheme.chipBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Relative drag, so touching the track never makes the value jump.
struct ToolSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var gradient: [Color]?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStart: Double?
    private let thumb: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - thumb, 1)
            let x = CGFloat(fraction(value)) * width
            let origin = CGFloat(fraction(defaultValue)) * width
            ZStack(alignment: .leading) {
                track
                    .frame(height: 4)
                    .padding(.horizontal, thumb / 2)
                if gradient == nil {
                    Capsule()
                        .fill(FilmToneTheme.accent)
                        .frame(width: abs(x - origin), height: 4)
                        .offset(x: min(x, origin) + thumb / 2)
                }
                if defaultValue > range.lowerBound {
                    Capsule()
                        .fill(Color(white: 0.36))
                        .frame(width: 2, height: 14)
                        .offset(x: origin + thumb / 2 - 1)
                }
                Circle()
                    .fill(FilmToneTheme.sliderThumb)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStart == nil { onEditingChanged(true) }
                        let start = dragStart ?? value
                        dragStart = start
                        let span = range.upperBound - range.lowerBound
                        update(start + Double(gesture.translation.width / width) * span)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 40
            onEditingChanged(true)
            update(value + (direction == .increment ? step : -step))
            onEditingChanged(false)
        }
    }

    @ViewBuilder
    private var track: some View {
        if let gradient {
            Capsule().fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
        } else {
            Capsule().fill(FilmToneTheme.sliderTrack)
        }
    }

    private func fraction(_ value: Double) -> Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func update(_ proposed: Double) {
        let snap = (range.upperBound - range.lowerBound) * 0.015
        var clamped = min(max(proposed, range.lowerBound), range.upperBound)
        if abs(clamped - defaultValue) < snap { clamped = defaultValue }
        value = clamped
    }
}

struct CurveControls: View {
    @ObservedObject var session: EditorSession
    @State private var channel: CurveChannel = .rgb

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CurveChannel.allCases) { item in
                    ToolChip(title: item.title, selected: channel == item) { channel = item }
                }
                Spacer(minLength: 0)
                Button(L10n.text("Reset")) { session.setCurvePreview(CurveAdjustment()) }
                    .font(.system(size: 13))
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .buttonStyle(.plain)
                    .disabled(session.curves.isIdentity)
            }
            CurveGraph(
                curve: Binding(
                    get: { session.curves[channel] },
                    set: { updated in
                        var curves = session.curves
                        curves[channel] = updated
                        session.setCurvePreview(curves)
                    }
                ),
                tint: tint
            )
        }
    }

    private var tint: Color {
        switch channel {
        case .rgb: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }
}

private struct CurveGraph: View {
    @Binding var curve: ChannelCurve
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                Path { path in
                    stride(from: 0.25, through: 0.75, by: 0.25).forEach { mark in
                        let x = size.width * mark
                        let y = size.height * (1 - mark)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                Path { path in
                    guard let first = curve.points.first else { return }
                    path.move(to: position(first, in: size))
                    curve.points.dropFirst().forEach { path.addLine(to: position($0, in: size)) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(curve.points.indices, id: \.self) { index in
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .position(position(curve.points[index], in: size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let y = 1 - min(max((value.location.y - 9) / max(size.height - 18, 1), 0), 1)
                                    curve.setPoint(at: index, y: y)
                                }
                        )
                }
            }
        }
        .frame(height: 160)
        .accessibilityLabel(L10n.text("Curves"))
    }

    /// Inset by the handle radius so end points stay inside the graph.
    private func position(_ point: CurvePoint, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 9
        return CGPoint(
            x: inset + (size.width - inset * 2) * point.x,
            y: inset + (size.height - inset * 2) * (1 - point.y)
        )
    }
}
