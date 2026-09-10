//
//  TrackCanvasView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)
import AppKit
import os
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

/// The core UIKit canvas that renders all tracks, segments, and the playhead.
///
/// Architecture:
/// - Each EditorTrack → one TrackRowView (horizontal band)
/// - Each EditorSegment within a track → one SegmentBlockView (positioned by targetRange)
/// - TrackLayout converts time ↔ pixels
/// - Playhead is a CALayer for smooth animation
///
/// Gesture separation:
/// - UIScrollView handles horizontal scroll
/// - Trim handles use UIPanGestureRecognizer (high priority, narrow hit area)
/// - Pinch zoom is handled by ClipEditorViewController on the scroll view
/// - Long-press on a segment block activates compact reorder mode for that track
final class TrackCanvasView: BaseFlippedView {

    // MARK: - Layout Constants

    static let rulerHeight: CGFloat        = 36
    static let trackHeight: CGFloat        = 50
    static let trackSpacing: CGFloat       = 3
    static let leftPadding: CGFloat        = 16
    static let rightPadding: CGFloat       = 32
    static let minPixelsPerSecond: CGFloat = 20
    static let maxPixelsPerSecond: CGFloat = 600
    /// V5.1: 空 timeline 进入剪辑器时的初始 pps。
    /// 1s ≈ 60pt（剪映 / CapCut 风格），3s 图片 ≈ 180pt，约半屏宽，避免空 timeline
    /// 被 fittedPPS 算成 availableWidth/0.1 的巨大值导致新增素材爆缩略图。
    static let defaultPixelsPerSecond: CGFloat = 60

    /// Standard segment block visual parameters.
    enum SegmentVisuals {
        static let cornerRadius: CGFloat = 4
        static let selectedBorderWidth: CGFloat = 2
        static let blockVPadding: CGFloat = 4     // vertical padding inside track row
        static let handleBarInset: CGFloat = 4     // top/bottom inset of the handle bar

        static func blockColor(for kind: EditorTrack.Kind) -> NSColor {
            // Opacity gradient: main video stays heaviest, audio raised for
            // visual hierarchy, overlay/text/subtitle/adjustment unified as
            // lighter auxiliary tracks so the main video reads as primary.
            switch kind {
            case .video:      return NSColor.systemPurple.withAlphaComponent(0.75)
            case .overlay:    return NSColor.systemOrange.withAlphaComponent(0.55)
            case .text:       return NSColor.systemGreen.withAlphaComponent(0.55)
            case .subtitle:   return NSColor.systemBlue.withAlphaComponent(0.55)
            case .audio:      return NSColor.systemTeal.withAlphaComponent(0.65)
            case .adjustment: return NSColor.systemYellow.withAlphaComponent(0.55)
            }
        }

        static let selectedBorderColor = NSColor.systemYellow

        /// Fixed canvas display order: video → overlay → text → subtitle → audio → adjustment.
        static let trackDisplayOrder: [EditorTrack.Kind] = [
            .video, .overlay, .text, .subtitle, .audio, .adjustment
        ]

        /// Sort tracks by the fixed display order.
        static func sortedTracks(_ tracks: [EditorTrack]) -> [EditorTrack] {
            tracks.sorted { a, b in
                let ai = trackDisplayOrder.firstIndex(of: a.kind) ?? 99
                let bi = trackDisplayOrder.firstIndex(of: b.kind) ?? 99
                if ai == bi { return a.id.uuidString < b.id.uuidString }
                return ai < bi
            }
        }
    }

    // MARK: - Properties

    private var timeline: EditorTimeline?
    private(set) var layout: TrackLayout = .empty
    private(set) var currentPixelsPerSecond: CGFloat = minPixelsPerSecond
    /// Last known visible width of the scroll view's clip view. The canvas must
    /// be at least this wide so an empty timeline still fills the editor instead
    /// of showing only a sliver (~76pt from TrackLayout's 1s minimum).
    private var availableWidth: CGFloat = 0

    private var rulerView: RulerView!
    var trackRows: [UUID: TrackRowView] = [:]
    private var playheadLayer: CALayer!
    /// Empty-state guide ("将媒体拖到此以开始") shown when the main track has no clips.
    private var emptyGuideLabel: NSTextField?

    /// Transition badges: keyed by "leadingID–trailingID" string for fast lookup.
    private var transitionBadges: [String: TransitionBadgeView] = [:]

    /// Called when user finishes trimming a segment.
    /// `newSourceRangeStart` is non-nil only when the left handle extended outward.
    var onTrimCommit: ((UUID, TimeRange, Double?) -> Void)?

    /// Called during a trim drag for overlay/subtitle tracks to update preview in real-time.
    var onTrimPreview: ((UUID, TimeRange) -> Void)?

    /// Called when long-press reorder finishes — store should reorder and re-pack.
    var onReorderCommit: ((UUID, [UUID]) -> Void)?

    /// Called when a non-main-track segment is dragged to a new start time.
    var onMoveCommit: ((UUID, Double) -> Void)?

    /// Lock/unlock the scroll view during a free-pan drag so the timeline doesn't drift.
    var onScrollLock: ((Bool) -> Void)?

    /// Called when user taps a cut-point badge (leadingID, trailingID, existing transition or nil).
    var onTransitionTap: ((UUID, UUID, EditorTransition?) -> Void)?

        /// Called when the user taps the empty-state affordance on a user-created empty track.
    var onEmptyTrackAdd: ((UUID, EditorTrack.Kind) -> Void)?

    /// Called when a media entry is dropped onto the canvas: entry, drop time, drop y (canvas coords).
    var onDropMedia: ((LibraryMediaEntry, Double, CGFloat) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        let darkColor = NSColor(white: 0.1, alpha: 1.0)
        layer?.backgroundColor = darkColor.cgColor

        rulerView = RulerView()
        addSubview(rulerView)

        playheadLayer = CALayer()
        playheadLayer.backgroundColor = NSColor.systemRed.cgColor
        playheadLayer.frame = CGRect(x: 0, y: 0, width: 2, height: 1000)
        layer?.addSublayer(playheadLayer)
    }

    // MARK: - Public API

    func configure(timeline: EditorTimeline, availableWidth: CGFloat) {
        self.timeline       = timeline
        self.availableWidth = availableWidth
        // V5.1 BUG 2: 空 timeline 走默认 pps，避免 fittedPPS 把 duration=0 膨胀为 0.1s
        // 导致 availableWidth/0.1 算出数千 pps，新增素材瞬间生成海量缩略图。
        if currentPixelsPerSecond == Self.minPixelsPerSecond {
            if timeline.duration < 0.5 {
                currentPixelsPerSecond = Self.defaultPixelsPerSecond
            } else {
                currentPixelsPerSecond = TrackLayout.fittedPPS(duration: timeline.duration, availableWidth: availableWidth)
            }
        }
        layout = TrackLayout(duration: timeline.duration, pixelsPerSecond: currentPixelsPerSecond)
        applyLayout(timeline: timeline)
        rebuildTrackRows(timeline: timeline, availableWidth: availableWidth)
        rebuildTransitionBadges(timeline: timeline)
    }

    @discardableResult
    func zoom(to pixelsPerSecond: CGFloat, playheadTime: Double) -> Void {
        guard let timeline else { return }
        currentPixelsPerSecond = pixelsPerSecond.clamped(to: Self.minPixelsPerSecond...Self.maxPixelsPerSecond)
        layout = TrackLayout(duration: timeline.duration, pixelsPerSecond: currentPixelsPerSecond)
        applyLayout(timeline: timeline)
        for (_, row) in trackRows {
            row.relayout(layout: layout)
        }
        updatePlayhead(time: playheadTime)
    }

    /// Lightweight update for trim/move changes: repositions blocks without
    /// rebuilding gesture recognizers or destroying active gestures.
    func relayoutSegments(timeline: EditorTimeline) {
        self.timeline = timeline
        layout = TrackLayout(duration: timeline.duration, pixelsPerSecond: currentPixelsPerSecond)
        applyLayout(timeline: timeline)
        let assetByID = Dictionary(uniqueKeysWithValues: timeline.materials.all.map { ($0.id, $0) })
        for track in timeline.tracks {
            if let row = trackRows[track.id] {            
                row.update(track: track, layout: layout, materialAssets: assetByID)
            }
        }
        rebuildTransitionBadges(timeline: timeline)
    }

    func updatePlayhead(time: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playheadLayer.frame.origin.x = layout.x(for: time)
        CATransaction.commit()
    }

    func updateSelection(ids: Set<UUID>) {
        for (_, row) in trackRows { row.updateSelection(ids: ids) }
    }

    /// Briefly flashes a yellow border around the given segment blocks.
    /// Used to acknowledge newly-appeared segments (split / insert).
    /// Safe to call with IDs that don't yet exist in any row — they're skipped.
    func flashSegments(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for (_, row) in trackRows {
            for (id, view) in row.segmentViews where ids.contains(id) {
                guard let layer = view.layer else {
                    return
                }
                let savedWidth = layer.borderWidth
                let savedColor = layer.borderColor
                layer.borderWidth = 2
                layer.borderColor = NSColor.systemYellow.cgColor
             
                // 动画
                let duration: CFTimeInterval = 0.35
                let delay: CFTimeInterval = 0.10
                let beginTime = CACurrentMediaTime() + delay

                // 1. 边框宽度动画
                let borderWidthAnim = CABasicAnimation(keyPath: "borderWidth")
                borderWidthAnim.fromValue = 2.0
                borderWidthAnim.toValue = savedWidth
                borderWidthAnim.duration = duration
                borderWidthAnim.beginTime = beginTime
                borderWidthAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                borderWidthAnim.fillMode = .forwards
                borderWidthAnim.isRemovedOnCompletion = true

                // 2. 边框颜色动画
                let borderColorAnim = CABasicAnimation(keyPath: "borderColor")
                borderColorAnim.fromValue = NSColor.systemYellow.cgColor
                borderColorAnim.toValue = savedColor
                borderColorAnim.duration = duration
                borderColorAnim.beginTime = beginTime
                borderColorAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                borderColorAnim.fillMode = .forwards
                borderColorAnim.isRemovedOnCompletion = true

                // 3. 应用动画并更新最终状态
                view.layer?.add(borderWidthAnim, forKey: "borderWidth")
                view.layer?.add(borderColorAnim, forKey: "borderColor")

                view.layer?.borderWidth = savedWidth
                view.layer?.borderColor = savedColor
            }
        }
    }

    /// All segment IDs currently rendered. Used by the view controller to diff
    /// new vs. existing segments across timeline updates.
    var renderedSegmentIDs: Set<UUID> {
        var set: Set<UUID> = []
        for (_, row) in trackRows {
            for id in row.segmentViews.keys {
                set.insert(id)
            }
        }
        return set
    }

    func time(at x: CGFloat) -> Double { layout.time(at: x) }
    func x(for time: Double) -> CGFloat { layout.x(for: time) }

    func segmentID(at point: CGPoint) -> UUID? {
        for (_, row) in trackRows {
            let local = convert(point, to: row)
            if let id = row.segmentID(at: local) { return id }
        }
        return nil
    }

    /// Resolve the track row whose vertical span contains `y` (canvas coords).
    /// Returns nil if y is inside the ruler (above the first row).
    func trackID(atY y: CGFloat) -> UUID? {
        guard y > Self.rulerHeight else { return nil }
        var best: (id: UUID, distance: CGFloat)?
        for (id, row) in trackRows {
            let midY = row.frame.midY
            let d = abs(y - midY)
            if best == nil || d < best!.distance {
                best = (id, d)
            }
        }
        return best?.id
    }

    func addPlayheadGesture(_ gr: NSGestureRecognizer) {
        rulerView.addGestureRecognizer(gr)
    }

    func isMainTrackSegment(id: UUID) -> Bool {
        timeline?.mainTrack?.segment(id: id) != nil
    }

    // MARK: - NSDraggingDestination (media drop into timeline)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [MacMediaPanelView.mediaDragType]) != nil else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = sender.draggingPasteboard.data(forType: MacMediaPanelView.mediaDragType),
              let entry = try? JSONDecoder().decode(LibraryMediaEntry.self, from: data) else {
            return false
        }
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let time = max(0, time(at: dropPoint.x))
        onDropMedia?(entry, time, dropPoint.y)
        return true
    }

    /// Auto-scroll the timeline when a trim handle drag reaches the visible edge.
    /// Speed ramps from 0 to maxSpeed as the touch moves deeper into the edge zone.
    private func handleAutoScroll(touchInWindow: CGPoint) {
        guard let enclosingScrollView = enclosingScrollView else { return }
        let clipView = enclosingScrollView.contentView
        let touchInClipView = clipView.convert(touchInWindow, from: nil)
        let edgeZone: CGFloat = 60
        let maxSpeed: CGFloat = 8   // points per .changed tick

        let visibleRect = clipView.documentVisibleRect
        let leftEdge  = visibleRect.maxX + edgeZone
        let rightEdge = visibleRect.maxX - edgeZone
        
        var newOrigin = visibleRect.origin

        if touchInClipView.x < leftEdge {
            let speed = min(maxSpeed, (leftEdge - touchInClipView.x) / edgeZone * maxSpeed)
            newOrigin.x = max(0, newOrigin.x - speed)
            clipView.scroll(to: newOrigin)
            enclosingScrollView.reflectScrolledClipView(clipView)
        } else if touchInClipView.x > rightEdge {
            let speed = min(maxSpeed, (touchInClipView.x - rightEdge) / edgeZone * maxSpeed)
            let maxX = frame.width - visibleRect.width
            newOrigin.x = min(maxX, newOrigin.x + speed)
            clipView.scroll(to: newOrigin)
            enclosingScrollView.reflectScrolledClipView(clipView)
        }
    }

    // MARK: - Private

        private func applyLayout(timeline: EditorTimeline) {
        let totalHeight = Self.rulerHeight + CGFloat(timeline.tracks.count) * (Self.trackHeight + Self.trackSpacing)
        let totalWidth  = layout.totalWidth + Self.rightPadding
        // 空 timeline 时 canvas 至少填满可见宽度，避免只显示一小段标尺。
        let minWidth    = max(availableWidth, 0)
        let contentSize = CGSize(width: max(totalWidth, minWidth), height: max(totalHeight, 200))

        setFrameSize(contentSize)

        rulerView.frame = CGRect(x: 0, y: 0, width: contentSize.width, height: Self.rulerHeight)
        rulerView.configure(layout: layout)

        playheadLayer.frame.size = CGSize(width: 2, height: contentSize.height)
        updateEmptyGuide()
    }

    /// 空态引导：主轨无片段时在 canvas 居中显示"将媒体拖到此以开始"。
    private func updateEmptyGuide() {
        let isEmpty = timeline?.mainTrack?.segments.isEmpty ?? true
        if isEmpty {
            if emptyGuideLabel == nil {
                let label = NSTextField(labelWithString: "将媒体拖到此以开始")
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.textColor = NSColor.white.withAlphaComponent(0.45)
                label.alignment = .center
                label.isBezeled = false
                label.drawsBackground = false
                label.isEditable = false
                label.isSelectable = false
                label.translatesAutoresizingMaskIntoConstraints = false
                addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: Self.rulerHeight / 2)
                ])
                emptyGuideLabel = label
            }
            emptyGuideLabel?.isHidden = false
        } else {
            emptyGuideLabel?.isHidden = true
        }
    }

    private func rebuildTrackRows(timeline: EditorTimeline, availableWidth: CGFloat) {
        trackRows.values.forEach { $0.removeFromSuperview() }
        trackRows.removeAll()

        // Pre-compute source durations for trim handle right-cap.
        // Priority: AVURLAsset.duration (loaded file) > asset.nativeDuration (importer-set).
        // Rules:
        //   - ai_video             → nativeDuration = sceneRange.duration
        //   - image_3d / motion    → nativeDuration = sceneRange.duration
        //   - static image         → no nativeDuration, no AVURLAsset duration → no cap
        //   - text / subtitle      → placeholder asset, no URL → no cap
        let allAssets = timeline.materials.all
        let assetByID = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.id, $0) })

        var sourceDurationMap: [UUID: Double] = [:]
        for asset in allAssets {
            if let url = asset.bestURL {
                let avAsset = AssetCache.shared.asset(for: url)
                let dur = avAsset.duration
                if dur.isNumeric && dur.seconds > 0 {
                    sourceDurationMap[asset.id] = dur.seconds
                }
            }
            // Fallback: nativeDuration recorded at import time.
            // Covers: image assets (no AVURLAsset video duration) and ai_video before
            // the AVURLAsset has been loaded asynchronously.
            if sourceDurationMap[asset.id] == nil, let nd = asset.nativeDuration, nd > 0 {
                sourceDurationMap[asset.id] = nd
            }
        }
        // Static images have no nativeDuration — ensure their cap entry is nil.
        // IMPORTANT: do NOT key this on motionPreset/depthEffect being nil, because
        // image_motion and image_3d may have nil content fields when the server sends
        // an unrecognized animation type. Use nativeDuration presence instead:
        // if the asset was given a nativeDuration at import time it is a timed clip;
        // if not, it is a static image that may stretch freely.
        for track in timeline.tracks {
            for seg in track.segments {
                guard case .image = seg.content else { continue }
                let nd = assetByID[seg.materialID]?.nativeDuration
                if (nd ?? 0) <= 0 {
                    sourceDurationMap[seg.materialID] = nil
                }
            }
        }

        // Fixed track display order: video → overlay → text → subtitle → audio → adjustment.
        let orderedTracks = SegmentVisuals.sortedTracks(timeline.tracks)

        var yOffset = Self.rulerHeight
        for track in orderedTracks {
            let row = TrackRowView(
                track: track,
                layout: layout,
                availableWidth: availableWidth,
                sourceDurations: sourceDurationMap,
                materialAssets: assetByID
            ) { [weak self] segID, range, newSrcStart in
                self?.onTrimCommit?(segID, range, newSrcStart)
            }
            row.onTrimPreview = { [weak self] segID, range in
                self?.onTrimPreview?(segID, range)
            }
            row.onReorderCommit = { [weak self] trackID, newOrder in
                self?.onReorderCommit?(trackID, newOrder)
            }
            row.onMoveCommit = { [weak self] segID, newStart in
                self?.onMoveCommit?(segID, newStart)
            }
            row.onScrollLock = { [weak self] lock in
                self?.onScrollLock?(lock)
            }
            row.onAutoScroll = { [weak self] touchInWindow in
                self?.handleAutoScroll(touchInWindow: touchInWindow)
            }
            row.onEmptyTrackAdd = { [weak self] trackID, kind in
                self?.onEmptyTrackAdd?(trackID, kind)
            }
            row.frame = CGRect(x: 0, y: yOffset, width: layout.totalWidth, height: Self.trackHeight)
            addSubview(row)
            trackRows[track.id] = row
            yOffset += Self.trackHeight + Self.trackSpacing
        }
    }

    // MARK: - Transition Badges

    /// Rebuilds or repositions diamond badges at every cut-point on the main track.
    /// Badges for transitions that already exist show filled; bare cut-points show outline.
    private func rebuildTransitionBadges(timeline: EditorTimeline) {
        guard let mainTrack = timeline.mainTrack else {
            transitionBadges.values.forEach { $0.removeFromSuperview() }
            transitionBadges.removeAll()
            return
        }

        let mainTrackRow = trackRows[mainTrack.id]
        let rowY = mainTrackRow.map { convert($0.frame.origin, from: $0.superview) }.map { $0.y }
                   ?? Self.rulerHeight

        // Build the set of cut-point pairs from adjacent main-track segments.
        let segs = mainTrack.segments.sorted { $0.targetRange.start < $1.targetRange.start }
       
        var neededKeys = Set<String>()
        let transitionByLeading = Dictionary(
            uniqueKeysWithValues: timeline.transitions.map { ($0.leadingSegmentID, $0) }
        )

        let badgeSize: CGFloat = 20
        let badgeHalf = badgeSize / 2
        if !segs.isEmpty {
            for i in 0..<(segs.count - 1) {
                let leading  = segs[i]
                let trailing = segs[i + 1]
                let key      = "\(leading.id)–\(trailing.id)"
                neededKeys.insert(key)

                let cutX = layout.x(for: leading.targetRange.end)
                let existing = transitionByLeading[leading.id]

                if let badge = transitionBadges[key] {
                    // Reposition existing badge
                    badge.frame = CGRect(x: cutX - badgeHalf, y: rowY - badgeHalf,
                                         width: badgeSize, height: badgeSize)
                    badge.transition = existing
                } else {
                    // Create new badge
                    let badge = TransitionBadgeView(frame: CGRect(x: cutX - badgeHalf, y: rowY - badgeHalf,
                                                                  width: badgeSize, height: badgeSize))
                    badge.transition = existing
                    badge.onTap = { [weak self, leading, trailing, weak badge] in
                        self?.onTransitionTap?(leading.id, trailing.id, badge?.transition)
                    }
                    addSubview(badge)
//                    bringSubviewToFront(badge)
                    transitionBadges[key] = badge
                }
            }
        }

        // Remove stale badges (segments deleted or reordered)
        for key in Set(transitionBadges.keys).subtracting(neededKeys) {
            transitionBadges[key]?.removeFromSuperview()
            transitionBadges[key] = nil
        }
    }
}

#endif
