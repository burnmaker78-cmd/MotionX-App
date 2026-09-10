//
//  TrackLabelsView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit
import TimelineKitCore

// MARK: - Track Labels Sidebar (v4 collapsible with UIScrollView sync)

/// Fixed left column showing track-kind icon + name, with a tap-to-expand control panel.
///
/// v4 architecture:
/// - Wraps content in its own `UIScrollView` for native bidirectional scroll sync.
/// - **Collapsed** (default, 52pt): icon + name only — all control buttons hidden.
/// - **Expanded** (136pt): full lock / hide / mute buttons per track (per-kind rules).
/// - Toggle via tap on the chevron button at the top of the sidebar.
/// - Auto-collapses 1.5s after any control button tap.
final class TrackLabelsView: BaseFlippedView {

    // MARK: - Layout constants

    static let collapsedWidth: CGFloat = 52
    static let expandedWidth: CGFloat  = 136

    private static let multiTrackKinds: Set<EditorTrack.Kind> = [.text, .subtitle, .audio, .overlay]

    // MARK: - Subviews

    let scrollView = NSScrollView()
    private let contentContainer = BaseFlippedView()
    private let sidebarToggleButton = NSButton()
    private var trackRows: [TrackLabelRowView] = []

    // MARK: - State

    private(set) var isExpanded = false
    private var tracks: [EditorTrack] = []
    private var autoCollapseWorkItem: DispatchWorkItem?

    // MARK: - Callbacks

    var onToggleLock:   ((UUID) -> Void)?
    var onToggleHidden: ((UUID) -> Void)?
    var onToggleMute:   ((UUID) -> Void)?
    var onAddTrack:     ((EditorTrack.Kind) -> Void)?
    var onExpandStateChange: ((Bool) -> Void)?
    
    
    override var isFlipped: Bool {
        return true
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        clipsToBounds = true

        // ScrollView — vertical only, no horizontal bounce/scroll.
        scrollView.hasVerticalScroller   = false
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask               = [.width, .height]
        scrollView.drawsBackground = false
        
        // APPKit 设置DocumentView 托管内容
        contentContainer.wantsLayer = true
        scrollView.documentView = contentContainer
        addSubview(scrollView)

        // Toggle button — fixed at top edge, outside scroll area.
        // Pinned to trailing edge so it stays visible in both collapsed & expanded widths.
        sidebarToggleButton.isBordered = false
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(didTapToggle)
        sidebarToggleButton.wantsLayer = true
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false
        updateToggleIcon()
        addSubview(sidebarToggleButton)
        
        NSLayoutConstraint.activate([
            sidebarToggleButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            sidebarToggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            sidebarToggleButton.widthAnchor.constraint(equalToConstant: 22),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        // Right separator
        let sep = BaseFlippedView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
        NSLayoutConstraint.activate([
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1.0)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    // MARK: - Configure

    func configure(tracks: [EditorTrack]) {
        self.tracks = tracks
        trackRows.forEach { $0.removeFromSuperview() }
        trackRows.removeAll()

        let ordered = TrackCanvasView.SegmentVisuals.sortedTracks(tracks)

        var lastIndexByKind: [EditorTrack.Kind: Int] = [:]
        for (i, t) in ordered.enumerated() { lastIndexByKind[t.kind] = i }

        // Ruler spacer
        let rulerSpacer = BaseFlippedView()
        rulerSpacer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: TrackCanvasView.rulerHeight)
        contentContainer.addSubview(rulerSpacer)

        var yOffset = TrackCanvasView.rulerHeight
        for (i, track) in ordered.enumerated() {
            let showAdd = Self.multiTrackKinds.contains(track.kind)
                       && lastIndexByKind[track.kind] == i
            let row = TrackLabelRowView(track: track, isExpanded: isExpanded, showAddButton: showAdd)
            row.frame = CGRect(x: 0, y: yOffset, width: Self.expandedWidth, height: TrackCanvasView.trackHeight)

            row.onToggleLock   = { [weak self] in
                self?.didTapControl(); self?.onToggleLock?(track.id)
            }
            row.onToggleHidden = { [weak self] in
                self?.didTapControl(); self?.onToggleHidden?(track.id)
            }
            row.onToggleMute   = { [weak self] in
                self?.didTapControl(); self?.onToggleMute?(track.id)
            }
            row.onAddTrack     = { [weak self] in
                self?.onAddTrack?(track.kind)
            }

            contentContainer.addSubview(row)
            trackRows.append(row)
            yOffset += TrackCanvasView.trackHeight + TrackCanvasView.trackSpacing
        }

        let totalHeight = TrackCanvasView.rulerHeight
            + CGFloat(tracks.count) * (TrackCanvasView.trackHeight + TrackCanvasView.trackSpacing)
        contentContainer.frame = CGRect(x: 0, y: 0, width: Self.expandedWidth, height: totalHeight)
    }

    /// Lightweight refresh of button states without full rebuild. Called on non-structural
    /// timeline updates (lock/hide/mute toggle).
    func refreshTrackStates(_ tracks: [EditorTrack]) {
        self.tracks = tracks
        let ordered = TrackCanvasView.SegmentVisuals.sortedTracks(tracks)
        for (i, track) in ordered.enumerated() where i < trackRows.count {
            trackRows[i].update(track: track, isExpanded: isExpanded)
        }
    }

    // MARK: - Expand / Collapse

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        cancelAutoCollapse()
        updateToggleIcon()

        let changes = {
            for row in self.trackRows {
                row.setExpanded(expanded)
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                changes()
            }
        } else {
            changes()
        }
        onExpandStateChange?(expanded)
    }

    func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    @objc private func didTapToggle() {
        toggleExpanded()
    }

    private func updateToggleIcon() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let name = isExpanded ? "chevron.left.2" : "chevron.right.2"
        sidebarToggleButton.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        sidebarToggleButton.contentTintColor = NSColor.white.withAlphaComponent(0.45)
    }

    private func didTapControl() {
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        cancelAutoCollapse()
        let work = DispatchWorkItem { [weak self] in
            self?.setExpanded(false)
        }
        autoCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func cancelAutoCollapse() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
    }

    // MARK: - Scroll Sync

    /// Total content height of the label rows (including ruler spacer). Used by the
    /// view controller to keep contentSize in sync with the canvas scroll view.
    var contentHeight: CGFloat {
        contentContainer.frame.height
    }

    func syncContentSize(with canvasContentHeight: CGFloat) {
        let h = max(canvasContentHeight, contentHeight)
        contentContainer.setFrameSize(NSSize(width: Self.expandedWidth, height: h))
    }
}

#endif
