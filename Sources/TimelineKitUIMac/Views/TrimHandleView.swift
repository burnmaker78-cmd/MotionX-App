//
//  TrimHandleView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit

// MARK: - TrimHandleView

/// Transparent hit zone for a trim handle.
/// Normal state  : hitWidth = 24 pt, visualWidth = 6 pt (main track always visible).
/// Selected state: hitWidth = 32 pt, visualWidth = 9 pt (attachment track after tap).
/// Being a subview of SegmentBlockView, UIKit hitTest naturally routes edge
/// touches here before reaching the block's long-press gesture.
final class TrimHandleView: BaseFlippedView {
    static let hitWidthNormal:      CGFloat = 32
    static let hitWidthSelected:    CGFloat = 44
    static let visualWidthNormal:   CGFloat = 8
    static let visualWidthSelected: CGFloat = 12

    private let bar: BaseFlippedView
    private var barWidthConstraint: NSLayoutConstraint!
    
    let isLeading: Bool

    init(isLeading: Bool) {
        bar = BaseFlippedView()
        self.isLeading = isLeading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        let barWidth = bar.widthAnchor.constraint(equalToConstant: Self.visualWidthNormal)
        barWidthConstraint = barWidth

        let edgeAnchor: NSLayoutConstraint = isLeading
            ? bar.leadingAnchor.constraint(equalTo: leadingAnchor)
            : bar.trailingAnchor.constraint(equalTo: trailingAnchor)

        NSLayoutConstraint.activate([
            barWidth,
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            edgeAnchor
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        barWidthConstraint.constant   = selected ? Self.visualWidthSelected : Self.visualWidthNormal
        bar.layer?.backgroundColor = selected
        ? NSColor.white.withAlphaComponent(0.9).cgColor
        : NSColor.white.withAlphaComponent(0.5).cgColor
    }
}

#endif
