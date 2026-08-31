//
//  SegmentBlockView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit
import TimelineKitCore

// MARK: - SegmentBlockView

final class SegmentBlockView: BaseFlippedView {
    /// Stored at init so isSelected can swap between normal and brightened colors.
    private let unselectedBackgroundColor: NSColor
    private let selectedBackgroundColor: NSColor

    var isSelected: Bool = false {
        didSet {
            guard oldValue != isSelected else { return }
            updateHandles()
            // Animate border + background for a smoother transition than instant swap.
            // AppKit 动画模型适配：使用 NSAnimationContext
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                
                self.layer?.borderWidth = self.isSelected
                ? TrackCanvasView.SegmentVisuals.selectedBorderWidth
                : 0
                self.layer?.backgroundColor = self.isSelected
                ? self.selectedBackgroundColor.cgColor
                : self.unselectedBackgroundColor.cgColor
            }
            
            // Subtle scale pop on becoming selected
            if isSelected {
                // AppKit 需开启 layerTransforms 才能顺畅支持 layer.transform 动画
                self.wantsLayer = true
                let scaleTransform = CATransform3DMakeScale(1.02, 1.02, 1.0)
                self.layer?.transform = scaleTransform
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true // 开启 CoreAnimation 隐式动画捕获
                    
                    // 直接修改 CALayer 属性，系统会自动生成渐变动画
//                    self.animator().layer?.transform = CATransform3DIdentity
                    self.layer?.transform = CATransform3DIdentity
                }
            }
        }
    }

    /// Called on trim gesture end. Second arg is new sourceRange.start (non-nil only when
    /// the left handle extended outward, shifting the clip in-point leftward).
    var onTrimCommit: ((TimeRange, Double?) -> Void)?
    /// Called during drag (.changed) to update store state for live overlay preview.
    var onTrimPreview: ((TimeRange) -> Void)?
    /// Called during trim drag with the touch point in window coordinates.
    /// TrackCanvasView uses this to auto-scroll the UIScrollView when the handle
    /// reaches the visible edge of the timeline.
    var onAutoScroll: ((CGPoint) -> Void)?

    // Long-press callbacks (coordinates in superview space)
    var onLongPressActivated: ((CGFloat) -> Void)?
    var onLongPressMoved:     ((CGFloat) -> Void)?
    var onLongPressEnded:     (() -> Void)?
    var onLongPressCancelled: (() -> Void)?

    private let segment: EditorSegment
    // v4 (track-header-controls-spec rev2 — P0-2): `track` is `var` so the
    // parent row can refresh the flag state in-place when isLocked / isHidden
    // change. The reorder / trim handlers read `track.isLocked` on every event,
    // so the local copy must stay live.
    private var track: EditorTrack
    var trackLayout: TrackLayout
    private var asset: EditorAsset?

    private var trimStartRange: TimeRange = TimeRange(start: 0, duration: 0)
    private let minDuration: Double = 0.2

    /// Set by TrackRowView from the source asset duration. Guards the right handle
    /// from extending past the available source material (spec A-05).
    var sourceDuration: Double? = nil

    /// Set by TrackRowView from segment.sourceRange.start. Guards the LEFT handle from
    /// extending past the beginning of the source clip (A-05 symmetric rule).
    /// nil means no pre-roll available → left handle stays pinned.
    var sourceRangeStart: Double? = nil

    // Same-track sibling ranges — set by TrackRowView; used to clamp trim on both handles.
    var siblingRanges: [TimeRange] = []

    /// The segment's current time range — kept in sync by TrackRowView.relayout after every
    /// commit. Used in .began so that a second gesture always starts from the real current
    /// position, not the stale value baked into the immutable `segment` at init time.
    var currentRange: TimeRange
    // Cached at .began: left edge = prevSibling.end (or 0), right edge = nextSibling.start (or ∞)
    private var trimLeftBound:  Double = 0
    private var trimRightBound: Double = .infinity

    // Handle view references for dynamic visibility / sizing
    private var leadingHandle: TrimHandleView?
    private var trailingHandle: TrimHandleView?
    private var leadingHandleWidthConstraint: NSLayoutConstraint?
    private var trailingHandleWidthConstraint: NSLayoutConstraint?

    // Stored so we can exclude it when touch lands in a handle hit zone.
    private weak var longPressGesture: NSPressGestureRecognizer?

    // Thumbnail strip — shown for video/image blocks only.
    private let thumbnailStrip = ThumbnailStripView()
    // Waveform strip — shown for audio blocks only.
    private let waveformStrip = WaveformStripView()
    // Width at which thumbnails were last requested; avoids redundant reloads during layout.
    private var lastThumbLoadWidth: CGFloat = 0
    // Suppresses thumbnail reload during live trim drag to avoid thrashing the generator.
    var isTrimming = false

    // V7.5: live thumbnail scrub during a LEFT-handle trim. We keep the already
    // rendered strip content fixed and slide it under the (stationary) leading handle
    // so the leftmost visible frame tracks the new in-point — no per-frame thumbnail
    // re-fetch, no flicker. Only active while dragging the leading handle inward.
    private var isPreviewSliding = false
    private var thumbnailSlideBaseWidth: CGFloat = 0

    // Text preview label — shown for subtitle and text segments.
    private let textLabel = NSTextField(labelWithString: "")

    init(segment: EditorSegment, track: EditorTrack, layout: TrackLayout,
         asset: EditorAsset? = nil) {
        self.segment      = segment
        self.track        = track
        self.trackLayout       = layout
        self.asset        = asset
        self.currentRange = segment.targetRange

        let baseColor = TrackCanvasView.SegmentVisuals.blockColor(for: track.kind)
        let showsThumbs: Bool = {
            switch segment.content {
            case .video, .image: return true
            default: return false
            }
        }()
        if showsThumbs {
            unselectedBackgroundColor = baseColor.withAlphaComponent(0.3)
        } else {
            unselectedBackgroundColor = baseColor
        }
        let boostedAlpha = min(max(unselectedBackgroundColor.cgColor.alpha + 0.2, 0), 1.0)
        selectedBackgroundColor = baseColor.withAlphaComponent(boostedAlpha)

        super.init(frame: .zero)
        self.wantsLayer = true
        // v4 (track-header-controls-spec §2.2): both hidden AND locked tracks
        // render their segment blocks at 0.4 alpha on the timeline canvas to
        // give a clear "this is temporarily disabled, not deleted" cue. The
        // preview canvas applies the same opacity in EditorPreviewView so the
        // two surfaces stay visually in sync.
        self.alphaValue = (track.isHidden || track.isLocked) ? 0.4 : 1.0
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        guard let layer else { return }
        layer.cornerRadius = TrackCanvasView.SegmentVisuals.cornerRadius
        layer.borderColor  = TrackCanvasView.SegmentVisuals.selectedBorderColor.cgColor
        layer.backgroundColor    = unselectedBackgroundColor.cgColor
        layer.masksToBounds      = true

        // Thumbnail strip sits behind handles as the first subview.
        let showThumbs = shouldShowThumbnails
        if showThumbs {
            thumbnailStrip.frame = bounds
            thumbnailStrip.autoresizingMask = [.width, .height]
            addSubview(thumbnailStrip)
        }

        // Text preview label for subtitle and text segments.
        if shouldShowTextPreview {
            textLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            textLabel.textColor = NSColor.white.withAlphaComponent(0.9)
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.maximumNumberOfLines = 1
            textLabel.alignment = .left
            textLabel.isEditable = false
            textLabel.isSelectable = false
            textLabel.drawsBackground = false
            textLabel.isBezeled = false
            textLabel.frame = bounds.insetBy(dx: 8, dy: 4)
            textLabel.autoresizingMask = [.width, .height]
            addSubview(textLabel)
            updateTextLabel()
        }

        // Waveform strip for audio segments.
        if shouldShowWaveform {
            waveformStrip.frame = bounds.insetBy(dx: 4, dy: 8)
            waveformStrip.autoresizingMask = [.width, .height]
            addSubview(waveformStrip)
        }

        addTrimHandle(isLeading: true)
        addTrimHandle(isLeading: false)
        updateHandles()  // set initial visibility

        let lp = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.3
        lp.delegate = self
        longPressGesture = lp
        addGestureRecognizer(lp)
    }

    private var shouldShowThumbnails: Bool {
        switch segment.content {
        case .video, .image: return true
        default: return false
        }
    }

    private var shouldShowTextPreview: Bool {
        switch segment.content {
        case .text, .subtitle: return true
        default: return false
        }
    }

    private var shouldShowWaveform: Bool {
        if case .audio = segment.content { return true }
        return false
    }

    /// Extract the display text from a text or subtitle segment.
    private var segmentDisplayText: String? {
        switch segment.content {
        case .text(let c):    return c.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .subtitle(let c): return c.text.trimmingCharacters(in: .whitespacesAndNewlines)
        default:              return nil
        }
    }

    private func updateTextLabel(with text: String? = nil) {
        textLabel.stringValue = (text ?? segmentDisplayText) ?? ""
        textLabel.isHidden = textLabel.stringValue.isEmpty
        textLabel.alignment = .left
        textLabel.frame = bounds.insetBy(dx: 8, dy: 4)
    }

    override func layout() {
        super.layout()
        guard !isTrimming else { return }

        if shouldShowTextPreview {
            textLabel.frame = bounds.insetBy(dx: 8, dy: 4)
        }

        if shouldShowThumbnails {
            guard abs(bounds.width - lastThumbLoadWidth) > 1 else { return }
            lastThumbLoadWidth = bounds.width
            // Map thumbnails to the segment's LIVE source slice, not the frozen init
            // segment. After a trim the block persists (relayoutSegments — no canvas
            // rebuild) and only currentRange / sourceRangeStart are refreshed; using the
            // frozen segment would keep showing the original in/out point. Aligning the
            // strip with the live in-point + target duration also lets the post-commit
            // reload land flush with what the left-handle slide previewed.
            var liveSeg = segment
            liveSeg.sourceRange = TimeRange(
                start:    sourceRangeStart ?? segment.sourceRange?.start ?? 0,
                duration: currentRange.duration
            )
            liveSeg.targetRange = currentRange
            thumbnailStrip.load(asset: asset, segment: liveSeg)
        }

        if shouldShowWaveform, let url = asset?.bestURL {
            waveformStrip.frame = bounds.insetBy(dx: 4, dy: 8)
            guard abs(bounds.width - lastThumbLoadWidth) > 1 else { return }
            lastThumbLoadWidth = bounds.width
            waveformStrip.load(url: url)
        }
    }

    /// Update text label from a new segment's content (text/subtitle edits).
    func updateContent(from seg: EditorSegment) {
        switch seg.content {
        case .text(let c):
            updateTextLabel(with: c.text)
        case .subtitle(let c):
            updateTextLabel(with: c.text)
        default:
            break
        }
    }

    /// v4 (track-header-controls-spec rev2 — P0-2): refresh the block's view
    /// of the parent track's flags. Called from `TrackRowView.update(track:…)`
    /// whenever isLocked / isHidden / isMuted change, so the gesture guard +
    /// alpha + trim-handle visibility reflect the new state without the
    /// expensive full canvas rebuild.
    func updateTrackFlags(_ newTrack: EditorTrack) {
        let alphaChanged    = (track.isHidden != newTrack.isHidden)
                           || (track.isLocked != newTrack.isLocked)
        let handlesChanged  = (track.isLocked != newTrack.isLocked)
                           || (track.isMainTrack != newTrack.isMainTrack)
        self.track = newTrack
        if alphaChanged {
            self.alphaValue = (newTrack.isHidden || newTrack.isLocked) ? 0.4 : 1.0
        }
        if handlesChanged {
            updateHandles()
        }
    }

    /// Called by TrackRowView when the underlying material is restored.
    /// Forces a thumbnail/waveform reload if the asset URL changed.
    func updateAsset(_ newAsset: EditorAsset?) {
        let oldURL = asset?.bestURL
        let newURL = newAsset?.bestURL
        guard oldURL != newURL else { return }
        asset = newAsset
        lastThumbLoadWidth = 0   // invalidate so layoutSubviews triggers reload
        switch segment.content {
        case .audio: waveformStrip.cancelLoading()
        default:     thumbnailStrip.cancelLoading()
        }
        needsLayout = true
    }

    // MARK: - Trim Handles

    private func addTrimHandle(isLeading: Bool) {
        let handle = TrimHandleView(isLeading: isLeading)
        handle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(handle)

        let edgeAnchor: NSLayoutConstraint = isLeading
            ? handle.leadingAnchor.constraint(equalTo: leadingAnchor)
            : handle.trailingAnchor.constraint(equalTo: trailingAnchor)

        let widthConstraint = handle.widthAnchor.constraint(equalToConstant: TrimHandleView.hitWidthNormal)

        NSLayoutConstraint.activate([
            widthConstraint,
            handle.topAnchor.constraint(equalTo: topAnchor),
            handle.bottomAnchor.constraint(equalTo: bottomAnchor),
            edgeAnchor
        ])

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleTrimPan(_:)))
//        pan.maximumNumberOfTouches = 1
        handle.addGestureRecognizer(pan)

        if isLeading {
            leadingHandle = handle
            leadingHandleWidthConstraint = widthConstraint
        } else {
            trailingHandle = handle
            trailingHandleWidthConstraint = widthConstraint
        }
    }

    // MARK: - Handle Visibility

    private func updateHandles() {
        let show     = (track.isMainTrack || isSelected) && !track.isLocked
        let hitWidth = isSelected ? TrimHandleView.hitWidthSelected : TrimHandleView.hitWidthNormal

        for (handle, wc) in [(leadingHandle,  leadingHandleWidthConstraint),
                              (trailingHandle, trailingHandleWidthConstraint)] {
            guard let handle else { continue }
            handle.isHidden = !show
            handle.setSelected(isSelected)
            wc?.constant = hitWidth
        }
    }

    // MARK: - Trim Gesture

    @objc private func handleTrimPan(_ gr: NSPanGestureRecognizer) {
        // v4 (audio-track-controls-spec §3.4): locked tracks reject all gestures.
        guard !track.isLocked else { return }
        // Only process trim on the selected segment.  This prevents accidentally
        // triggering a neighbouring segment's handle when both are visible.
        guard isSelected else { return }
        guard let handleView = gr.view as? TrimHandleView else { return }
        let isLeading = handleView.isLeading
        switch gr.state {
        case .began:
            isTrimming = true
            trimStartRange = currentRange
            let sorted = siblingRanges.sorted { $0.start < $1.start }

            if track.isMainTrack {
                // Right handle: unlimited — successors ripple rightward on commit.
                trimRightBound = .infinity

                // Left handle: pre-roll consumption model.
                // Drag left → block's right edge extends rightward (start anchored).
                // Drag right → inward trim from left (start moves right).
                // The constraint on pre-roll extension is sourceRangeStart (available
                // seconds before the current in-point).  Images have no cap.
                // trimLeftBound is used only for inward trim; try to keep it as wide
                // as possible so the gesture isn't artificially constrained.
                let srcPreRoll: Double = sourceDuration != nil ? (sourceRangeStart ?? 0) : Double.infinity
                trimLeftBound = max(0, trimStartRange.start - srcPreRoll)
            } else {
                // Attachment track: no ripple — adjacent segments are hard blockers.
                // Left: blocked by nearest left sibling, or source pre-roll cap (audio/video only).
                // Right: blocked by nearest right sibling.
                let predecessorEnd = sorted
                    .filter { $0.end <= trimStartRange.start + 0.001 }
                    .map    { $0.end }
                    .max()  ?? 0
                if sourceDuration != nil {
                    // Audio/video on attachment track: limited by available source pre-roll.
                    let backRoom = sourceRangeStart ?? 0
                    trimLeftBound = max(predecessorEnd, trimStartRange.start - backRoom)
                } else {
                    // Text/subtitle/overlay/adjustment: no source cap, only blocked by siblings.
                    trimLeftBound = max(0, predecessorEnd)
                }
                trimRightBound = sorted
                    .filter { $0.start >= trimStartRange.end - 0.001 }
                    .map    { $0.start }
                    .min()  ?? .infinity
            }
            // Left handle: freeze the strip's current content and take manual control
            // of its frame so we can slide it under the leading handle during the drag.
            if isLeading, shouldShowThumbnails {
                isPreviewSliding        = true
                thumbnailSlideBaseWidth = thumbnailStrip.bounds.width
                thumbnailStrip.autoresizingMask = []
            }
        case .changed:
            let translation = gr.translation(in: superview)
            let dt = trackLayout.timeDelta(for: translation.x)
            let range = clampedRange(isLeading: isLeading, dt: dt)
            applyTrimPreview(range: range)
            if isPreviewSliding { slideThumbnailPreview(to: range) }
            onTrimPreview?(range)
            
            // 触摸/鼠标位置计算在 AppKit 中取 Window ContentView 空间
            if let windowPoint = window?.contentView?.convert(gr.location(in: nil), from: nil) {
                onAutoScroll?(windowPoint)
            }
        case .ended:
            isTrimming = false
            endThumbnailSlide()
            let translation = gr.translation(in: superview)
            let dt = trackLayout.timeDelta(for: translation.x)
            let newRange = clampedRange(isLeading: isLeading, dt: dt)
            
            var newSourceStart: Double? = nil
            if isLeading, let srcStart = sourceRangeStart {
                let inPointShift: Double
                if track.isMainTrack {
                    inPointShift = newRange.duration - trimStartRange.duration
                } else {
                    inPointShift = trimStartRange.start - newRange.start
                }
                if abs(inPointShift) > 0.001 {
                    newSourceStart = max(0, srcStart - inPointShift)
                }
            }
            onTrimCommit?(newRange, newSourceStart)
        case .cancelled, .failed:
            isTrimming = false
            endThumbnailSlide()
            let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
            frame = CGRect(
                x: trackLayout.x(for: trimStartRange.start),
                y: TrackCanvasView.SegmentVisuals.blockVPadding,
                width: max(trackLayout.width(for: trimStartRange.duration), 16),
                height: blockH
            )
            onTrimPreview?(trimStartRange)
        default: break
        }
    }

    private func applyTrimPreview(range: TimeRange) {
        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        frame = CGRect(
            x: trackLayout.x(for: range.start),
            y: TrackCanvasView.SegmentVisuals.blockVPadding,
            width: max(trackLayout.width(for: range.duration), 16),
            height: blockH
        )
    }

    /// Slide the (fixed-content) thumbnail strip so the leading handle scrubs through
    /// the source during a left-handle trim. Inward trim (start moves right) → shift the
    /// strip left by the same pixels so the leftmost visible frame becomes the new
    /// in-point; the block clips the overflow. Extend / no inward move → just fill the
    /// block (the earlier pre-roll frames aren't rendered, so there's nothing to scrub).
    private func slideThumbnailPreview(to range: TimeRange) {
        let leftShiftPx = trackLayout.x(for: range.start) - trackLayout.x(for: trimStartRange.start)
        let h = bounds.height
        if leftShiftPx > 0 {
            thumbnailStrip.frame = CGRect(x: -leftShiftPx, y: 0,
                                          width: thumbnailSlideBaseWidth, height: h)
        } else {
            thumbnailStrip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        }
    }

    /// Restore the strip to normal autoresize-to-bounds and force a reload, so the
    /// post-commit (or post-cancel) layout re-maps thumbnails to the final in/out point.
    private func endThumbnailSlide() {
        guard isPreviewSliding else { return }
        isPreviewSliding = false
        thumbnailStrip.autoresizingMask = [.width, .height]
        thumbnailStrip.frame = bounds
        lastThumbLoadWidth = 0   // invalidate so the next layout reloads the live slice
        needsLayout = true
    }

    private func clampedRange(isLeading: Bool, dt: Double) -> TimeRange {
        if isLeading {
            if track.isMainTrack, dt < 0 {
                // ── Pre-roll consumption (main track, drag left) ─────────────
                // The block's left edge stays anchored on the timeline; the right
                // edge extends rightward by up to sourceRangeStart seconds
                // (available pre-roll).  The thumbnail strip shows earlier source
                // content.  First segment works identically — start stays at 0,
                // duration grows right, successors ripple right.
                let preRollCap = sourceRangeStart ?? 0
                let ext = min(abs(dt), preRollCap)
                let newEnd = min(trimStartRange.end + ext, trimRightBound)
                let duration = max(minDuration, newEnd - trimStartRange.start)
                return TimeRange(start: trimStartRange.start, duration: duration)
            } else {
                // Inward trim (dt > 0) or attachment track: move start, end fixed.
                let newStart = (trimStartRange.start + dt)
                    .clamped(to: trimLeftBound ... (trimStartRange.end - minDuration))
                return TimeRange(start: newStart, duration: trimStartRange.end - newStart)
            }
        } else {
            // Right bound: nextSibling.start (or ∞), also capped by source asset duration (A-05).
            // Use the live `sourceRangeStart` property — `segment` is a frozen let from init
            // and its sourceRange becomes stale after material replacement.
            let srcCap: Double = {
                guard let sd = sourceDuration, sd > 0 else { return .infinity }
                let srcStart = sourceRangeStart ?? 0
                return trimStartRange.start + (sd - srcStart)
            }()
            let effectiveRightBound = min(trimRightBound, srcCap)
            let newEnd = (trimStartRange.end + dt)
                .clamped(to: (trimStartRange.start + minDuration) ... effectiveRightBound)
            return TimeRange(start: trimStartRange.start, duration: newEnd - trimStartRange.start)
        }
    }

    // MARK: - Long Press → Reorder

    @objc private func handleLongPress(_ gr: NSPressGestureRecognizer) {
        let touchX = gr.location(in: superview).x
        switch gr.state {
        case .began:     onLongPressActivated?(touchX)
        case .changed:   onLongPressMoved?(touchX)
        case .ended:     onLongPressEnded?()
        case .cancelled, .failed: onLongPressCancelled?()
        default: break
        }
    }

}

// MARK: - SegmentBlockView + UIGestureRecognizerDelegate

extension SegmentBlockView: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gr: NSGestureRecognizer) -> Bool {
        if track.isLocked {
            return false
        }
        if gr === longPressGesture {
            // macOS AppKit 的坐标原点位于左下角，X 轴增量向右，因此计算点击的 X 偏移量逻辑与 iOS 完全一致
            let p = gr.location(in: self)
            let w = bounds.width
            let third = w / 3.0
            
            if let lead = leadingHandle, !lead.isHidden,
               p.x < min(lead.frame.width, third) {
                return false
            }
            
            if let trail = trailingHandle, !trail.isHidden,
               p.x > w - min(trail.frame.width, third) {
                return false
            }
        }
        return true
    }
}

#endif
