//
//  ClipEditorViewController.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared

/// macOS NSViewController root controller for the clip editor's track area.
/// Directs high-performance Timeline interactions, gesture recognition, and scroll synchronizations.
public final class ClipEditorViewController: NSViewController {

    // MARK: - Properties

    private var store: EditorStore?
    private var libraryStore: TimelineLibraryStore?
    private var timeline: EditorTimeline?
    private var selection: SelectionState?

    private var scrollView: NSScrollView!
    private var canvas: TrackCanvasView!
    private var labelsView: TrackLabelsView!
    private var placeholderView: ClipEditorPlaceholderView!
    private var didInitialLayout = false

    /// Guards against re-entrant scroll sync between canvas and labels scroll views.
    private var isSyncingScroll = false

    // Pinch / Magnification zoom state
    private var pinchStartPPS: CGFloat = 0
    private var pinchAnchorTime: Double = 0
    private var pinchAnchorScreenX: CGFloat = 0

    /// SwiftUI-owned route for empty-track add affordances.
    public var onEmptyTrackAdd: ((UUID, EditorTrack.Kind) -> Void)?

    // Scrub state
    private var scrubWasPlaying = false
    private var lastScrubTime: CFTimeInterval = 0
    private let scrubThrottle: CFTimeInterval = 0.033 // 33ms ≈ 30fps
    private var lastSnapTime: Double = -1
    private var isScrollScrubbing = false

    // Constraints
    private var labelsWidthConstraint: NSLayoutConstraint!

    // MARK: - Init

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    /// Update the backing EditorStore reference (active project switch creates a
    /// NEW EditorStore). Without this, canvas interactions keep mutating the old
    /// project's timeline.
    ///
    /// IMPORTANT: do NOT pre-assign `self.timeline` here — `apply` must compare
    /// against the OLD timeline (its stored value) to detect a project switch
    /// (new timeline id / new track ids) and rebuild the canvas. Pre-assigning
    /// would make `apply` see "old == new" and skip the rebuild, leaving
    /// `trackRows` keyed by stale ids (no segments visible).
    public func updateStore(_ newStore: EditorStore) {
        // `store` is read directly by gesture/drop handlers (e.g. addVisualSegment),
        // and `apply` does not set it — so update it here.
        self.store = newStore
        // `timeline` and `selection` are set inside `apply` (after the structural
        // comparison against the OLD stored timeline). Pre-assigning either here
        // would break that comparison.
        apply(timeline: newStore.timeline, selection: newStore.selection)
    }

    /// Inject the library store (needed for drag-and-drop media-file URL resolution).
    /// Called once by the shell after the VC is created; the library does not change
    /// on project switches.
    public func updateLibraryStore(_ newStore: TimelineLibraryStore) {
        self.libraryStore = newStore
    }

    // MARK: - Placeholder / editing mode

    /// Switch between the placeholder view ("创建项目" / "项目是一条时间线…")
    /// and the full editing interface (labels + scroll view + canvas).
    ///
    /// Call with `true` when no project is active, `false` once the user
    /// creates or switches to a project. Views may not be loaded yet — guard.
    public func setPlaceholderMode(_ show: Bool) {
        guard scrollView != nil, labelsView != nil, placeholderView != nil else { return }
        placeholderView.isHidden = !show
        scrollView.isHidden = show
        labelsView.isHidden = show
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    public override func loadView() {
        // macOS AppKit view coordinates start at bottom-left by default.
        // We use a custom flipped root view so 0,0 remains at top-left matching UI expectations.
        let rootView = FlippedContainerView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1.0).cgColor
        self.view = rootView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        setupTrackLabels()
        setupScrollView()
        setupCanvas()
        setupGestureRecognizers()
        setupScrollNotifications()
        setupDragAndDrop()
        setupPlaceholderView()

        // No project is active at launch — default to the placeholder view.
        setPlaceholderMode(true)
    }

    public override func viewDidLayout() {
        super.viewDidLayout()

        updateScrollInsets()
        guard !didInitialLayout else { return }
        didInitialLayout = true
        if let timeline, let selection {
            canvas.configure(timeline: timeline, availableWidth: scrollView.bounds.width)
            labelsView.configure(tracks: timeline.tracks)
            
            labelsView.syncContentSize(with: canvas.frame.height)
            syncLabelScrollOffset()
            scrollToPlayhead(time: selection.playheadTime, animated: false)
            syncLabelScrollOffset()
        }
    }

    // MARK: - State Application

    public func apply(timeline: EditorTimeline, selection: SelectionState) {
        var structural = false
        var tracksAdded = false
        if let oldTimeline = self.timeline {
            // 项目切换 = 新 EditorStore = 新 timeline/轨道 id。trackRows 字典仍持
            // 旧 id，relayoutSegments 用新 id 查不到旧行 → 必须全量重建画布。
            // 轨道 id 变化已含在 hasStructuralChange；timeline.id 变化再兜底一次。
            structural = oldTimeline.id != timeline.id
                || hasStructuralChange(from: oldTimeline, to: timeline)
            tracksAdded = timeline.tracks.count > oldTimeline.tracks.count
        } else {
            // 首次应用（占位模式 → 第一个项目）：self.timeline 为 nil，无法比较，
            // 直接按结构性重建（trackRows 尚未创建任何行）。
            structural = true
        }
        
        let appearedSegmentIDs: Set<UUID> = {
            guard structural else { return [] }
            let priorRendered = canvas.renderedSegmentIDs
            guard !priorRendered.isEmpty else { return [] }
            let next = Set(timeline.tracks.flatMap { $0.segments.map(\.id) })
            return next.subtracting(priorRendered)
        }()

        self.timeline  = timeline
        self.selection = selection

        if structural {
            canvas.configure(timeline: timeline, availableWidth: scrollView.bounds.width)
            labelsView.configure(tracks: timeline.tracks)
            labelsView.syncContentSize(with: canvas.frame.height)

            if tracksAdded {
                scrollToRevealNewTracks()
            }
            if !appearedSegmentIDs.isEmpty {
                canvas.flashSegments(ids: appearedSegmentIDs)
            }
        } else {
            canvas.relayoutSegments(timeline: timeline)
            labelsView.refreshTrackStates(timeline.tracks)
        }

        canvas.updatePlayhead(time: selection.playheadTime)
        canvas.updateSelection(ids: selection.selectedSegmentIDs)

        if let store, store.isPlaying && !isScrollScrubbing {
            scrollToPlayhead(time: selection.playheadTime, animated: false)
        }
    }

    private func hasStructuralChange(from old: EditorTimeline, to new: EditorTimeline) -> Bool {
        guard old.tracks.count == new.tracks.count else { return true }
        for (o, n) in zip(old.tracks, new.tracks) {
            guard o.id == n.id, o.segments.count == n.segments.count else { return true }
            if zip(o.segments, n.segments).contains(where: { $0.id != $1.id }) { return true }
        }
        return false
    }

    // MARK: - View Setups
    
    private func setupPlaceholderView() {
        placeholderView = ClipEditorPlaceholderView()
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderView)
        
        placeholderView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        placeholderView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }

    private func setupTrackLabels() {
        labelsView = TrackLabelsView()
        labelsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(labelsView)

        labelsWidthConstraint = labelsView.widthAnchor.constraint(equalToConstant: TrackLabelsView.collapsedWidth)
        NSLayoutConstraint.activate([
            labelsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            labelsView.topAnchor.constraint(equalTo: view.topAnchor),
            labelsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            labelsWidthConstraint
        ])

        labelsView.onAddTrack = { [weak self] kind in
            if let store = self?.store {
                store.addTrack(kind: kind, pendingUserCreated: true)
            }
        }

        labelsView.onExpandStateChange = { [weak self] expanded in
            guard let self else { return }
            if let labelsWidthConstraint = self.labelsWidthConstraint {
                labelsWidthConstraint.constant = expanded
                    ? TrackLabelsView.expandedWidth
                    : TrackLabelsView.collapsedWidth
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.view.layoutSubtreeIfNeeded()
            }
        }

        labelsView.onToggleLock = { [weak self] id in
            guard let store = self?.store else {
                return
            }
            guard let t = store.timeline.track(id: id) else {
                return
            }
            store.setTrackLocked(id: id, isLocked: !t.isLocked)
        }

        labelsView.onToggleHidden = { [weak self] id in
            guard let store = self?.store else {
                return
            }
            guard let t = store.timeline.track(id: id), !t.isMainTrack else { return }
            store.setTrackHidden(id: id, isHidden: !t.isHidden)
        }

        labelsView.onToggleMute = { [weak self] id in
            guard let store = self?.store else {
                return
            }
            guard let t = store.timeline.track(id: id) else { return }
            store.muteTrack(id: id, isMuted: !t.isMuted)
        }
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: labelsView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCanvas() {
        canvas = TrackCanvasView()
        canvas.frame = CGRect(x: 0, y: 0, width: 100, height: 200)

        // Set AppKit document view
        let clipView = FlippedClipView()
        scrollView.contentView = clipView
        scrollView.documentView = canvas

        canvas.onTrimCommit = { [weak self] segID, range, newSrcStart in
            guard let self, let store = self.store else { return }
            store.trimSegment(id: segID, newTargetRange: range, newSourceRangeStart: newSrcStart)
            self.canvas.relayoutSegments(timeline: store.timeline)
        }

        canvas.onTrimPreview = { [weak self] segID, range in
            guard let store = self?.store else {
                return
            }
            store.previewTrimRange(segmentID: segID, range: range)
        }

        canvas.onReorderCommit = { [weak self] trackID, newOrder in
            guard let store = self?.store else {
                return
            }
            store.reorderSegments(trackID: trackID, newOrder: newOrder)
        }

        canvas.onMoveCommit = { [weak self] segID, newStart in
            guard let store = self?.store else {
                return
            }
            store.moveSegment(id: segID, to: newStart)
        }

        canvas.onTransitionTap = { [weak self] leadingID, trailingID, existing in
            guard let store = self?.store else {
                return
            }
            store.selection.editingTransitionContext =
                TransitionEditContext(leadingID: leadingID, trailingID: trailingID,
                                     existingTransition: existing)
        }

        canvas.onEmptyTrackAdd = { [weak self] trackID, kind in
            self?.onEmptyTrackAdd?(trackID, kind)
        }

        // Media dropped from the Browser onto the canvas.
        canvas.onDropMedia = { [weak self] entry, time, y in
            self?.insertDroppedMedia(entry: entry, time: time, dropY: y)
        }
    }

    private func setupGestureRecognizers() {
        // Direct Playhead Pan on Ruler
        let playheadPan = NSPanGestureRecognizer(target: self, action: #selector(handlePlayheadPan(_:)))
        canvas.addPlayheadGesture(playheadPan)

        // Single Click Select
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        canvas.addGestureRecognizer(click)

        // Trackpad Pinch Zooming
        let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        scrollView.addGestureRecognizer(magnification)
    }

    private func setupScrollNotifications() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        labelsView.scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: labelsView.scrollView.contentView
        )
    }

    // MARK: - Drag & Drop (media from the Browser into the timeline)

    private func setupDragAndDrop() {
        view.registerForDraggedTypes([MacMediaPanelView.mediaDragType])
        canvas.registerForDraggedTypes([MacMediaPanelView.mediaDragType])
    }

    // MARK: - Scroll Sync & Scrubbing

    @objc private func handleScrollViewBoundsDidChange(_ notification: Notification) {
        guard let sourceClipView = notification.object as? NSClipView, !isSyncingScroll else { return }

        isSyncingScroll = true
        defer { isSyncingScroll = false }
        
        guard let timeline, let store else { return }

        let currentY = sourceClipView.bounds.origin.y

        if sourceClipView === scrollView.contentView {
            // Synchronize vertical scroll to track labels
            labelsView.scrollView.contentView.scroll(to: NSPoint(x: labelsView.scrollView.contentView.bounds.origin.x, y: currentY))
            labelsView.scrollView.reflectScrolledClipView(labelsView.scrollView.contentView)

            // Canvas horizontal scrubbing logic
            if isScrollScrubbing {
                let centerX = sourceClipView.bounds.origin.x + sourceClipView.bounds.width / 2
                let newTime = max(0, min(canvas.time(at: max(0, centerX)), timeline.duration))
                store.selection.playheadTime = newTime

                let now = CACurrentMediaTime()
                if now - lastScrubTime >= scrubThrottle {
                    lastScrubTime = now
                    store.seek(to: newTime)
                }
            }
        } else if sourceClipView === labelsView.scrollView.contentView {
            // Synchronize vertical scroll to main timeline canvas
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: currentY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Gesture Handlers

    @objc private func handlePlayheadPan(_ gr: NSPanGestureRecognizer) {
        
        guard let store else { return }
        
        let location = gr.location(in: canvas)

        switch gr.state {
        case .began:
            scrubWasPlaying = store.isPlaying
            store.pause()
            lowerResolution()
            lastScrubTime = 0

        case .changed:
            let now = CACurrentMediaTime()
            guard now - lastScrubTime >= scrubThrottle else { return }
            lastScrubTime = now
            let rawTime = canvas.time(at: location.x)
            let snapped = snapToEdge(rawTime)
            store.seek(to: snapped)

        case .ended, .cancelled:
            if scrubWasPlaying { store.play() }
            restoreResolution()

        default:
            break
        }
    }

    @objc private func handleClick(_ gr: NSClickGestureRecognizer) {
        guard let store else { return }
        
        let point = gr.location(in: canvas)
        if let segID = canvas.segmentID(at: point) {
            store.selection.selectedSegmentIDs = [segID]
            store.selection.editingSegmentID   = nil
        } else {
            store.selection.deselect()
        }
    }

    /// AppKit pinch-to-zoom using macOS touchpad native magnification gesture.
    @objc private func handleMagnification(_ gr: NSMagnificationGestureRecognizer) {
        guard let store, let timeline = timeline, let selection else { return }
        switch gr.state {
        case .began:
            pinchStartPPS      = canvas.currentPixelsPerSecond
            pinchAnchorScreenX = gr.location(in: scrollView).x
            let canvasX        = scrollView.contentView.bounds.origin.x + pinchAnchorScreenX
            pinchAnchorTime    = canvas.time(at: max(0, canvasX))

        case .changed:
            // Magnification scale defaults around 0.0 (+0.5 means zooming in, -0.5 means zooming out)
            let factor = 1.0 + gr.magnification
            let newPPS = pinchStartPPS * factor

            canvas.zoom(to: newPPS, playheadTime: selection.playheadTime)

            let anchorCanvasX = canvas.x(for: pinchAnchorTime)
            let targetOffsetX = anchorCanvasX - pinchAnchorScreenX

            let minX = -scrollView.contentInsets.left
            let maxX = max(minX, canvas.frame.width - scrollView.bounds.width + scrollView.contentInsets.right)
            let clampedX = min(max(targetOffsetX, minX), maxX)

            let targetPoint = NSPoint(x: clampedX, y: scrollView.contentView.bounds.origin.y)
            scrollView.contentView.scroll(to: targetPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)

        default:
            break
        }
    }

    // MARK: - Helpers

    private func syncLabelScrollOffset() {
        isSyncingScroll = true
        let currentY = scrollView.contentView.bounds.origin.y
        labelsView.scrollView.contentView.scroll(to: NSPoint(x: labelsView.scrollView.contentView.bounds.origin.x, y: currentY))
        labelsView.scrollView.reflectScrolledClipView(labelsView.scrollView.contentView)
        isSyncingScroll = false
    }

    private func scrollToPlayhead(time: Double, animated: Bool) {
        let targetX = canvas.x(for: time) - scrollView.bounds.width / 2
        let minX    = -scrollView.contentInsets.left
        let maxX    = max(minX, canvas.frame.width - scrollView.bounds.width + scrollView.contentInsets.right)
        let clamped = min(max(targetX, minX), maxX)

        let targetPoint = NSPoint(x: clamped, y: scrollView.contentView.bounds.origin.y)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                scrollView.contentView.animator().scroll(to: targetPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            scrollView.contentView.scroll(to: targetPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func updateScrollInsets() {
        let half = scrollView.bounds.width / 2
        guard scrollView.contentInsets.left != half else { return }
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: half, bottom: 0, right: half)
    }

    private func scrollToRevealNewTracks() {
        let maxY = canvas.frame.height - scrollView.bounds.height
        guard maxY > 0 else { return }

        let targetPoint = NSPoint(x: scrollView.contentView.bounds.origin.x, y: maxY)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            scrollView.contentView.animator().scroll(to: targetPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.syncLabelScrollOffset()
        }
    }

    private func snapToEdge(_ time: Double) -> Double {
        guard let timeline else {
            return 0.0
        }
        let pps = Double(canvas.currentPixelsPerSecond)
        let threshold = max(0.1, 8.0 / pps)
        let edges: [Double] = timeline.tracks
            .flatMap { $0.segments }
            .flatMap { [$0.targetRange.start, $0.targetRange.end] }
            + [0, timeline.duration]

        guard let nearest = edges.min(by: { abs($0 - time) < abs($1 - time) }),
              abs(nearest - time) <= threshold else {
            lastSnapTime = -1
            return time
        }

        if abs(nearest - lastSnapTime) > 0.01 {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            lastSnapTime = nearest
        }
        return nearest
    }

    private func lowerResolution() {
        guard let store else {
            return
        }
        store.coordinatorPlayer?.currentItem?.preferredMaximumResolution = CGSize(width: 960, height: 540)
    }

    private func restoreResolution() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let store = self?.store else {
                return
            }
            store.coordinatorPlayer?.currentItem?.preferredMaximumResolution = .zero
        }
    }

    // MARK: - Media drop handling

    /// P0 drop semantics:
    ///   - main-track drop beyond the last clip end  → append to main-track end
    ///   - main-track drop between clips             → insert at snapped drop time
    ///   - non-main track drop                       → insert onto that track (by kind)
    private func insertDroppedMedia(entry: LibraryMediaEntry, time: Double, dropY: CGFloat) {
        guard let store, let libraryStore else {
            return
        }
        guard let url = libraryStore.library?.mediaFileURL(for: entry) else { return }
        let trackID = canvas.trackID(atY: dropY)

        if let trackID, let track = store.timeline.track(id: trackID), !track.isMainTrack {
            // Non-main track: insert at drop time (audio → audio track, others → overlay).
            let snap = snapToEdge(time)
            switch entry.kind {
            case .audio:
                _ = store.addAudioSegment(localURL: url, nativeDuration: entry.duration ?? 0, startTime: snap, targetTrackID: trackID)
            case .video, .image:
                _ = store.insertVisualSegment(localURL: url, nativeDuration: entry.kind == .video ? entry.duration : nil, at: snap, targetTrackID: trackID)
            case .other:
                break
            }
            return
        }

        // Main track: append if drop time is at/after the end of the last clip;
        // otherwise insert at the snapped drop time (between clips).
        let mainEnd = store.timeline.mainTrack?.segments.last?.targetRange.end ?? 0
        if time >= mainEnd - 0.001 {
            switch entry.kind {
            case .video, .image:
                _ = store.addVisualSegment(localURL: url, nativeDuration: entry.kind == .video ? entry.duration : nil)
            case .audio:
                _ = store.addAudioSegment(localURL: url, nativeDuration: entry.duration ?? 0, startTime: mainEnd)
            case .other:
                break
            }
        } else {
            let snap = snapToEdge(time)
            switch entry.kind {
            case .video, .image:
                _ = store.insertVisualSegment(localURL: url, nativeDuration: entry.kind == .video ? entry.duration : nil, at: snap)
            case .audio:
                _ = store.addAudioSegment(localURL: url, nativeDuration: entry.duration ?? 0, startTime: snap)
            case .other:
                break
            }
        }
    }
}

// MARK: - Custom Flipped Views

/// Flipped NSView providing standard top-left coordinate origins.
private final class FlippedContainerView: BaseFlippedView {}

/// Flipped NSClipView for scrolling canvas documents from top to bottom.
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

#endif
