//
//  RulerView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit
import TimelineKitUISharedViews

// MARK: - TrackLayout

/// Shared time ↔ pixel math (extracted to TimelineKitUISharedViews so macOS
/// and iOS render tracks with pixel-identical coordinates).
typealias TrackLayout = TimelineTrackLayout

// MARK: - RulerView

final class RulerView: BaseFlippedView {
    private var layout: TrackLayout = .empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(layout: TrackLayout) {
        self.layout = layout
        needsDisplay = true // AppKit 中重绘应该触发 needsDisplay，而不是 needsLayout
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        // 1. 获取 AppKit 的 CGContext
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // 2. 替换为 NSColor
        let tickColor  = NSColor.white.withAlphaComponent(0.3)
        let labelColor = NSColor.white.withAlphaComponent(0.6)

        let minorInterval = tickInterval(pixelsPerSecond: layout.pixelsPerSecond)
        let majorInterval = minorInterval * 5

        var t: Double = 0
        while t <= layout.duration + minorInterval {
            let x = layout.x(for: t)
            let isMajor = t.truncatingRemainder(dividingBy: majorInterval) < minorInterval * 0.5
            let tickH: CGFloat = isMajor ? 14 : 7
            
            ctx.setFillColor(tickColor.cgColor)
            ctx.fill(CGRect(x: x - 0.5, y: bounds.height - tickH, width: 1, height: tickH))

            if isMajor {
                let label = formatTime(t)
                // 3. 替换为 NSFont 和 NSColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: labelColor
                ]
                label.draw(at: CGPoint(x: x, y: 4), withAttributes: attrs)
            }
            t += minorInterval
        }
    }

    private func tickInterval(pixelsPerSecond: CGFloat) -> Double {
        let candidates: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
        for c in candidates {
            if CGFloat(c) * pixelsPerSecond >= 30 { return c }
        }
        return 60
    }

    private func formatTime(_ s: Double) -> String {
        let m   = Int(s) / 60
        let sec = Int(s) % 60
        let ms  = Int((s - Double(Int(s))) * 10)
        if s < 10 { return String(format: "%d:%02d.%d", m, sec, ms) }
        return String(format: "%d:%02d", m, sec)
    }
}

#endif
