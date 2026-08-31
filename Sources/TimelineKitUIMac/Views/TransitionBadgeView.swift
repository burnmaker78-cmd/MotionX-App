//
//  TransitionBadgeView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import AppKit
import TimelineKitCore

// MARK: - TransitionBadgeView

/// Diamond-shaped tap target placed at each cut-point on the main track.
/// Filled (white) when a transition already exists; outlined when no transition.
final class TransitionBadgeView: BaseFlippedView {

    var onTap: (() -> Void)?

    /// The transition currently assigned to this cut-point, or nil for bare cut.
    var transition: EditorTransition? {
        didSet {
            // AppKit 刷新 View 的绘制需设属性 needsDisplay = true
            needsDisplay = true
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let clickGes = NSClickGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(clickGes)
    }

    required init?(coder: NSCoder) { fatalError() }
    

    override func draw(_ rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let s = min(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        let r = s / 2 - 1

        // Diamond path
        ctx.move(to:    CGPoint(x: cx,     y: cy - r))
        ctx.addLine(to: CGPoint(x: cx + r, y: cy))
        ctx.addLine(to: CGPoint(x: cx,     y: cy + r))
        ctx.addLine(to: CGPoint(x: cx - r, y: cy))
        ctx.closePath()

        if transition != nil {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }

    @objc private func didTap() { onTap?() }
}

