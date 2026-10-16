
#if canImport(UIKit)
import SwiftUI
import TimelineKitCore
import TimelineKitUIShared

// MARK: - ColorAdjustmentPanel

/// Slide-up panel for per-segment color, tone, and detail adjustments.
struct ColorAdjustmentPanel: View {

    let segmentID: UUID
    @Bindable var store: EditorStore
    var onDismiss: (() -> Void)? = nil

    @State private var tab: Tab = .adjust

    private var adjustment: SegmentAdjustment {
        store.timeline.segment(id: segmentID)?.adjustment ?? .identity
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()
                .background(Color.white.opacity(0.1))

            switch tab {
            case .adjust:
                adjustSliders
            case .filter:
                filterPicker
            }
        }
        .background(Color(white: 0.13))
    }

    // MARK: - Tabs

    private enum Tab: String, CaseIterable {
        case adjust = "Adjust"
        case filter = "Filters"
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        tab = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(
                            .system(
                                size: 13,
                                weight: tab == item ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(
                            tab == item
                                ? Color.white
                                : Color.white.opacity(0.5)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if tab == item {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Button {
                store.resetAdjustment(segmentID: segmentID)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        adjustment.isIdentity
                            ? Color.white.opacity(0.25)
                            : Color.white.opacity(0.8)
                    )
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(adjustment.isIdentity)
            .accessibilityLabel("Reset adjustments")

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close adjustment panel")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
    }

    // MARK: - Adjustment Sliders

    private var adjustSliders: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {

                sectionHeader("LIGHT")

                adjustRow(
                    "Exposure",
                    value: adjustment.exposure,
                    range: -2...2,
                    format: "%+.2f EV"
                ) { v in
                    preview(exposure: v)
                } onEnd: { v in
                    save(exposure: v)
                }

                adjustRow(
                    "Brightness",
                    value: adjustment.brightness,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(brightness: v)
                } onEnd: { v in
                    save(brightness: v)
                }

                adjustRow(
                    "Contrast",
                    value: adjustment.contrast - 1,
                    range: -0.5...0.5,
                    format: "%+.2f"
                ) { v in
                    preview(contrast: v + 1)
                } onEnd: { v in
                    save(contrast: v + 1)
                }

                adjustRow(
                    "Highlights",
                    value: adjustment.highlights,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(highlights: v)
                } onEnd: { v in
                    save(highlights: v)
                }

                adjustRow(
                    "Shadows",
                    value: adjustment.shadows,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(shadows: v)
                } onEnd: { v in
                    save(shadows: v)
                }

                adjustRow(
                    "Whites",
                    value: adjustment.whites,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(whites: v)
                } onEnd: { v in
                    save(whites: v)
                }

                adjustRow(
                    "Blacks",
                    value: adjustment.blacks,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(blacks: v)
                } onEnd: { v in
                    save(blacks: v)
                }

                sectionHeader("COLOR")

                adjustRow(
                    "Saturation",
                    value: adjustment.saturation - 1,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(saturation: v + 1)
                } onEnd: { v in
                    save(saturation: v + 1)
                }

                adjustRow(
                    "Vibrance",
                    value: adjustment.vibrance,
                    range: -1...1,
                    format: "%+.2f"
                ) { v in
                    preview(vibrance: v)
                } onEnd: { v in
                    save(vibrance: v)
                }

                adjustRow(
                    "Temperature",
                    value: adjustment.temperature,
                    range: 2000...9000,
                    format: "%.0f K"
                ) { v in
                    preview(temperature: v)
                } onEnd: { v in
                    save(temperature: v)
                }

                adjustRow(
                    "Tint",
                    value: adjustment.tint,
                    range: -150...150,
                    format: "%+.0f"
                ) { v in
                    preview(tint: v)
                } onEnd: { v in
                    save(tint: v)
                }

                sectionHeader("DETAIL & EFFECTS")

                adjustRow(
                    "Sharpen",
                    value: adjustment.sharpen,
                    range: 0...1,
                    format: "%.2f"
                ) { v in
                    preview(sharpen: v)
                } onEnd: { v in
                    save(sharpen: v)
                }

                adjustRow(
                    "Clarity",
                    value: adjustment.clarity,
                    range: 0...1,
                    format: "%.2f"
                ) { v in
                    preview(clarity: v)
                } onEnd: { v in
                    save(clarity: v)
                }

                adjustRow(
                    "Fade",
                    value: adjustment.fade,
                    range: 0...1,
                    format: "%.2f"
                ) { v in
                    preview(fade: v)
                } onEnd: { v in
                    save(fade: v)
                }

                adjustRow(
                    "Vignette",
                    value: adjustment.vignette,
                    range: 0...1,
                    format: "%.2f"
                ) { v in
                    preview(vignette: v)
                } onEnd: { v in
                    save(vignette: v)
                }

                adjustRow(
                    "Grain",
                    value: adjustment.grain,
                    range: 0...1,
                    format: "%.2f"
                ) { v in
                    preview(grain: v)
                } onEnd: { v in
                    save(grain: v)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Section Headers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.45))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Preview and Save

    private func preview(
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        temperature: Double? = nil,
        tint: Double? = nil,
        highlights: Double? = nil,
        shadows: Double? = nil,
        exposure: Double? = nil,
        vibrance: Double? = nil,
        whites: Double? = nil,
        blacks: Double? = nil,
        sharpen: Double? = nil,
        clarity: Double? = nil,
        fade: Double? = nil,
        vignette: Double? = nil,
        grain: Double? = nil
    ) {
        store.previewAdjustment(
            segmentID: segmentID,
            adjustment: adjusted(
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                temperature: temperature,
                tint: tint,
                highlights: highlights,
                shadows: shadows,
                exposure: exposure,
                vibrance: vibrance,
                whites: whites,
                blacks: blacks,
                sharpen: sharpen,
                clarity: clarity,
                fade: fade,
                vignette: vignette,
                grain: grain
            )
        )
    }

    private func save(
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        temperature: Double? = nil,
        tint: Double? = nil,
        highlights: Double? = nil,
        shadows: Double? = nil,
        exposure: Double? = nil,
        vibrance: Double? = nil,
        whites: Double? = nil,
        blacks: Double? = nil,
        sharpen: Double? = nil,
        clarity: Double? = nil,
        fade: Double? = nil,
        vignette: Double? = nil,
        grain: Double? = nil
    ) {
        store.setAdjustment(
            segmentID: segmentID,
            adjustment: adjusted(
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                temperature: temperature,
                tint: tint,
                highlights: highlights,
                shadows: shadows,
                exposure: exposure,
                vibrance: vibrance,
                whites: whites,
                blacks: blacks,
                sharpen: sharpen,
                clarity: clarity,
                fade: fade,
                vignette: vignette,
                grain: grain
            )
        )
    }

    // MARK: - Build Updated Adjustment

    private func adjusted(
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        temperature: Double? = nil,
        tint: Double? = nil,
        highlights: Double? = nil,
        shadows: Double? = nil,
        exposure: Double? = nil,
        vibrance: Double? = nil,
        whites: Double? = nil,
        blacks: Double? = nil,
        sharpen: Double? = nil,
        clarity: Double? = nil,
        fade: Double? = nil,
        vignette: Double? = nil,
        grain: Double? = nil,
        filterIntensity: Double? = nil
    ) -> SegmentAdjustment {
        var result = adjustment

        if let value = brightness { result.brightness = value }
        if let value = contrast { result.contrast = value }
        if let value = saturation { result.saturation = value }
        if let value = temperature { result.temperature = value }
        if let value = tint { result.tint = value }
        if let value = highlights { result.highlights = value }
        if let value = shadows { result.shadows = value }
        if let value = exposure { result.exposure = value }
        if let value = vibrance { result.vibrance = value }
        if let value = whites { result.whites = value }
        if let value = blacks { result.blacks = value }
        if let value = sharpen { result.sharpen = value }
        if let value = clarity { result.clarity = value }
        if let value = fade { result.fade = value }
        if let value = vignette { result.vignette = value }
        if let value = grain { result.grain = value }
        if let value = filterIntensity { result.filterIntensity = value }

        return result
    }

    private func adjustedFilter(
        _ name: PresetFilter?,
        intensity: Double? = nil
    ) -> SegmentAdjustment {
        var result = adjustment
        result.filterName = name
        result.filterIntensity = intensity ?? result.filterIntensity
        return result
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterChip(
                        label: "Original",
                        isSelected: adjustment.filterName == nil
                    ) {
                        store.setAdjustment(
                            segmentID: segmentID,
                            adjustment: adjustedFilter(nil, intensity: 1)
                        )
                    }

                    ForEach(
                        PresetFilter.Category.allCases,
                        id: \.self
                    ) { category in
                        ForEach(
                            PresetFilter.allCases.filter {
                                $0.category == category
                            },
                            id: \.self
                        ) { preset in
                            filterChip(
                                label: preset.displayName,
                                isSelected: adjustment.filterName == preset
                            ) {
                                store.setAdjustment(
                                    segmentID: segmentID,
                                    adjustment: adjustedFilter(preset)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if adjustment.filterName != nil {
                IntensitySliderRow(
                    intensity: adjustment.filterIntensity,
                    filterName: adjustment.filterName,
                    onPreview: { value in
                        store.previewAdjustment(
                            segmentID: segmentID,
                            adjustment: adjusted(
                                filterIntensity: value
                            )
                        )
                    },
                    onEnd: { value in
                        store.setAdjustment(
                            segmentID: segmentID,
                            adjustment: adjustedFilter(
                                adjustment.filterName,
                                intensity: value
                            )
                        )
                    }
                )
            }
        }
    }

    private func filterChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(
                    .system(
                        size: 12,
                        weight: isSelected ? .semibold : .regular
                    )
                )
                .foregroundStyle(
                    isSelected ? Color.black : Color.white
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.white : Color.white.opacity(0.12)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slider Row

    private func adjustRow(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        format: String,
        onPreview: @escaping (Double) -> Void,
        onEnd: @escaping (Double) -> Void
    ) -> some View {
        AdjustSliderRow(
            label: label,
            value: value,
            range: range,
            format: format,
            onPreview: onPreview,
            onEnd: onEnd
        )
    }
}

// MARK: - AdjustSliderRow

private struct AdjustSliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let format: String
    let onPreview: (Double) -> Void
    let onEnd: (Double) -> Void

    @State private var liveValue: Double
    @State private var isDragging = false

    init(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        format: String,
        onPreview: @escaping (Double) -> Void,
        onEnd: @escaping (Double) -> Void
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.format = format
        self.onPreview = onPreview
        self.onEnd = onEnd
        _liveValue = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Slider(
                value: $liveValue,
                in: range,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        onEnd(liveValue)
                    }
                }
            )
            .tint(.white)
            .onChange(of: liveValue) { _, newValue in
                if isDragging {
                    onPreview(newValue)
                }
            }

            Text(String(format: format, liveValue))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 55, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .onChange(of: value) { _, newValue in
            if !isDragging {
                liveValue = newValue
            }
        }
    }
}

// MARK: - Filter Intensity Slider

private struct IntensitySliderRow: View {
    let intensity: Double
    let filterName: PresetFilter?
    let onPreview: (Double) -> Void
    let onEnd: (Double) -> Void

    @State private var liveIntensity: Double
    @State private var isDragging = false

    init(
        intensity: Double,
        filterName: PresetFilter?,
        onPreview: @escaping (Double) -> Void,
        onEnd: @escaping (Double) -> Void
    ) {
        self.intensity = intensity
        self.filterName = filterName
        self.onPreview = onPreview
        self.onEnd = onEnd
        _liveIntensity = State(initialValue: intensity)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Intensity")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))

            Slider(
                value: $liveIntensity,
                in: 0...1,
                step: 0.01,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        onEnd(liveIntensity)
                    }
                }
            )
            .tint(.white)
            .onChange(of: liveIntensity) { _, newValue in
                if isDragging {
                    onPreview(newValue)
                }
            }

            Text(String(format: "%.0f%%", liveIntensity * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onChange(of: intensity) { _, newValue in
            if !isDragging {
                liveIntensity = newValue
            }
        }
    }
}
#endif
