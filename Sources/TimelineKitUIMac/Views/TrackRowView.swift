//
//  TrackRowView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import AppKit
import TimelineKitCore
import AppKit

final class TrackRowView: BaseFlippedView {
    private var track: EditorTrack
    private var layout: TrackLayout
    private let availableWidth: CGFloat
    /// File-internal so TrackCanvasView can flash newly-appeared blocks
    /// and diff rendered segment IDs across timeline updates.
    var segmentViews: [UUID: SegmentBlockView] = [:]
    private let onTrimCommit: (UUID, TimeRange, Double?) -> Void
    /// keyed by materialID; used to enforce right-handle source-duration cap (A-05)
    var sourceDurations: [UUID: Double] = [:]
    /// keyed by asset id (= materialID); forwarded to SegmentBlockView for thumbnail generation
    private var materialAssets: [UUID: EditorAsset] = [:]

    var onTrimPreview: ((UUID, TimeRange) -> Void)?
    var onReorderCommit: ((UUID, [UUID]) -> Void)?
    var onMoveCommit: ((UUID, Double) -> Void)?
    var onScrollLock: ((Bool) -> Void)?
    var onEmptyTrackAdd: ((UUID, EditorTrack.Kind) -> Void)?
    /// Forwarded from SegmentBlockView → TrackCanvasView for edge auto-scroll.
    var onAutoScroll: ((CGPoint) -> Void)?

    // MARK: - AppKit Coordinate Alignment
    
    /// 关键适配：将 macOS 默认左下角坐标系翻转为左上角原点，与时间轴逻辑保持一致
    override var isFlipped: Bool { true }

    // MARK: Reorder state (main track)

    private var isReordering = false
    private var reorderOrder: [UUID] = []
    private var draggingID: UUID? = nil
    private var reorderCardWidth: CGFloat = 80
    private var reorderOffset: CGFloat = 0
    private let reorderGap: CGFloat = 6

    // MARK: Free-drag state (attachment tracks)

    private var isFreeDragging = false
    private var freeDragSegmentID: UUID? = nil
    private var freeDragStartTime: Double = 0
    private var freeDragStartTouchX: CGFloat = 0
    private var freeDragLastSnapTime: Double = -1

    /// V7.5: type-aware add affordance shown on an empty pendingUserCreated track.
    private var pendingHintButton: NSButton?

    init(track: EditorTrack, layout: TrackLayout, availableWidth: CGFloat,
         sourceDurations: [UUID: Double] = [:],
         materialAssets:  [UUID: EditorAsset] = [:],
         onTrimCommit: @escaping (UUID, TimeRange, Double?) -> Void) {
        self.track          = track
        self.layout         = layout
        self.availableWidth = availableWidth
        self.sourceDurations = sourceDurations
        self.materialAssets   = materialAssets
        self.onTrimCommit   = onTrimCommit
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        layer?.cornerRadius = 4
        
        buildSegments()
        refreshPendingHint()
    }

    /// Create or remove the type-aware empty-track add affordance.
    private func refreshPendingHint() {
        let shouldShow = track.segments.isEmpty && track.pendingUserCreated
        if shouldShow {
            if pendingHintButton == nil {
                let btn = NSButton()
                btn.isBordered = false
                btn.imagePosition = .imageLeft
                let title = Self.pendingHintTitle(for: track.kind)
                
                // macOS 11+ 符号图片获取
                btn.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: title)
                btn.setButtonType(.momentaryPushIn)
                btn.title = title
                btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                
                btn.contentTintColor = NSColor.white.withAlphaComponent(0.45)
                btn.setAccessibilityLabel(title)
                btn.translatesAutoresizingMaskIntoConstraints = false
                
                btn.target = self
                btn.action = #selector(onEmptyTrackAddBtnAction)
                
                addSubview(btn)
                NSLayoutConstraint.activate([
                    btn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TrackCanvasView.leftPadding + 4),
                    btn.centerYAnchor.constraint(equalTo: centerYAnchor),
                    btn.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -8)
                ])
                pendingHintButton = btn
            }
        } else {
            pendingHintButton?.removeFromSuperview()
            pendingHintButton = nil
        }
    }

    private static func pendingHintTitle(for kind: EditorTrack.Kind) -> String {
        switch kind {
        case .overlay:    return "添加画中画"
        case .audio:      return "添加音频"
        case .text:       return "添加文字"
        case .subtitle:   return "添加字幕"
        case .adjustment: return "添加调节"
        case .video:      return "添加主轨素材"
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func onEmptyTrackAddBtnAction() {
        self.onEmptyTrackAdd?(self.track.id, self.track.kind)
    }

    func relayout(layout: TrackLayout) {
        guard !isReordering else { return }
        self.layout = layout
        frame.size.width = layout.totalWidth
        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        for seg in track.segments {
            guard let block = segmentViews[seg.id] else { continue }
            block.trackLayout = layout
            block.currentRange   = seg.targetRange
            block.siblingRanges  = track.segments.filter { $0.id != seg.id }.map { $0.targetRange }
            block.frame = CGRect(
                x: layout.x(for: seg.targetRange.start),
                y: TrackCanvasView.SegmentVisuals.blockVPadding,
                width: max(layout.width(for: seg.targetRange.duration), 16),
                height: blockH
            )
        }
    }

    func update(track: EditorTrack, layout: TrackLayout,
                materialAssets: [UUID: EditorAsset] = [:]) {
        self.track          = track
        self.materialAssets = materialAssets
        refreshPendingHint()
        
        for (id, asset) in materialAssets {
            if let nd = asset.nativeDuration, nd > 0 {
                sourceDurations[id] = nd
            }
        }

        for seg in track.segments {
            guard let block = segmentViews[seg.id] else {
                continue
            }
            block.updateAsset(materialAssets[seg.materialID])
            block.updateContent(from: seg)
            block.updateTrackFlags(track)
            switch seg.content {
            case .video, .audio:
                block.sourceDuration   = sourceDurations[seg.materialID]
                block.sourceRangeStart = seg.sourceRange?.start
            default:
                block.sourceDuration   = nil
                block.sourceRangeStart = nil
            }
        }
        relayout(layout: layout)
    }

    func updateSelection(ids: Set<UUID>) {
        for (id, view) in segmentViews {
            view.isSelected = ids.contains(id)
        }
    }

    func segmentID(at point: CGPoint) -> UUID? {
        for (id, view) in segmentViews {
            if view.frame.contains(point) {
                return id
            }
        }
        return nil
    }

    // MARK: - Build segments

    private func buildSegments() {
        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        for seg in track.segments {
            let x     = layout.x(for: seg.targetRange.start)
            let w     = max(layout.width(for: seg.targetRange.duration), 16)
            let block = SegmentBlockView(segment: seg, track: track, layout: layout,
                                         asset: materialAssets[seg.materialID])
            block.frame = CGRect(x: x, y: TrackCanvasView.SegmentVisuals.blockVPadding, width: w, height: blockH)

            block.onTrimCommit = { [weak self] range, newSrcStart in
                self?.onTrimCommit(seg.id, range, newSrcStart)
                self?.syncFrame(of: block, to: range)
            }

            block.onAutoScroll = { [weak self] point in
                self?.onAutoScroll?(point)
            }

            if track.isMainTrack {
                block.onTrimPreview = nil
            } else {
                block.onTrimPreview = { [weak self] range in
                    self?.onTrimPreview?(seg.id, range)
                }
            }

            block.siblingRanges = track.segments
                .filter { $0.id != seg.id }
                .map    { $0.targetRange }

            switch seg.content {
            case .video, .audio:
                block.sourceDuration    = sourceDurations[seg.materialID]
                block.sourceRangeStart  = seg.sourceRange?.start
            default:
                block.sourceDuration    = nil
                block.sourceRangeStart  = nil
            }

            if track.isMainTrack {
                block.onLongPressActivated = { [weak self, seg] touchX in
                    self?.beginReorder(draggingID: seg.id, touchX: touchX)
                }
                block.onLongPressMoved = { [weak self] touchX in
                    self?.updateReorder(touchX: touchX)
                }
                block.onLongPressEnded = { [weak self] in
                    self?.commitReorder()
                }
                block.onLongPressCancelled = { [weak self] in
                    self?.cancelReorder()
                }
            } else {
                block.onLongPressActivated = { [weak self, seg] touchX in
                    self?.beginFreeDrag(segmentID: seg.id, touchX: touchX)
                }
                block.onLongPressMoved = { [weak self] touchX in
                    self?.updateFreeDrag(touchX: touchX)
                }
                block.onLongPressEnded = { [weak self] in
                    self?.commitFreeDrag()
                }
                block.onLongPressCancelled = { [weak self] in
                    self?.cancelFreeDrag()
                }
            }

            addSubview(block)
            segmentViews[seg.id] = block
        }
    }

    private func syncFrame(of block: SegmentBlockView, to range: TimeRange) {
        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        block.frame = CGRect(
            x: layout.x(for: range.start),
            y: TrackCanvasView.SegmentVisuals.blockVPadding,
            width: max(layout.width(for: range.duration), 16),
            height: blockH
        )
    }

    // MARK: - Reorder mode

    private func beginReorder(draggingID: UUID, touchX: CGFloat) {
        guard !isReordering else { return }
        isReordering = true
        self.draggingID = draggingID

        reorderOrder = track.segments
            .sorted { $0.targetRange.start < $1.targetRange.start }
            .map { $0.id }

        let count = max(1, reorderOrder.count)
        let totalGaps = CGFloat(count - 1) * reorderGap
        let available = availableWidth - TrackCanvasView.leftPadding - TrackCanvasView.rightPadding
        reorderCardWidth = max(40, floor((available - totalGaps) / CGFloat(count)))

        let draggingIdx = reorderOrder.firstIndex(of: draggingID) ?? 0
        let defaultDraggedCenterX = TrackCanvasView.leftPadding
            + CGFloat(draggingIdx) * (reorderCardWidth + reorderGap)
            + reorderCardWidth / 2
        reorderOffset = max(0, touchX - defaultDraggedCenterX)

        segmentViews[draggingID]?.layer?.zPosition = 10

        // AppKit 动画适配：使用 NSAnimationContext 替代 UIView.animate
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            for (i, id) in self.reorderOrder.enumerated() {
                guard let block = self.segmentViews[id] else { continue }
                block.animator().frame.origin.x = self.reorderX(for: i)
                block.animator().frame.size.width = self.reorderCardWidth
                if id == draggingID {
                    // AppKit View Transform 缩放
                    block.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.0, y: 1.08))
                    block.animator().alphaValue = 0.85
                }
            }
        }
    }

    private func updateReorder(touchX: CGFloat) {
        guard isReordering, let draggingID, let block = segmentViews[draggingID] else {
            return
        }

        let minOriginX = reorderX(for: 0)
        let maxOriginX = reorderX(for: reorderOrder.count - 1)
        let originX = (touchX - reorderCardWidth / 2).clamped(to: minOriginX ... maxOriginX)
        block.frame.origin.x = originX

        let center = originX + reorderCardWidth / 2
        let baseX = TrackCanvasView.leftPadding + reorderOffset + reorderCardWidth / 2
        let rawFloat = (center - baseX) / (reorderCardWidth + reorderGap)

        guard let currentIdx = reorderOrder.firstIndex(of: draggingID) else { return }

        let rawSlot: Int
        if rawFloat > Double(currentIdx) {
            rawSlot = Int(floor(rawFloat))
        } else if rawFloat < Double(currentIdx) {
            rawSlot = Int(ceil(rawFloat))
        } else {
            rawSlot = currentIdx
        }
        let newSlot = rawSlot.clamped(to: 0 ... reorderOrder.count - 1)

        guard currentIdx != newSlot else { return }

        reorderOrder.remove(at: currentIdx)
        reorderOrder.insert(draggingID, at: newSlot)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for (i, id) in self.reorderOrder.enumerated() {
                guard id != draggingID, let b = self.segmentViews[id] else { continue }
                b.animator().frame.origin.x = self.reorderX(for: i)
            }
        }
    }

    private func commitReorder() {
        guard isReordering, let draggingID else { return }

        let finalOrder = reorderOrder
        let trackID    = track.id

        isReordering    = false
        self.draggingID = nil
        reorderOffset   = 0

        restoreNormalLayout()
        onReorderCommit?(trackID, finalOrder)
    }

    private func restoreNormalLayout() {
        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2

        for seg in track.segments {
            segmentViews[seg.id]?.layer?.setAffineTransform(.identity)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            for seg in self.track.segments {
                guard let block = self.segmentViews[seg.id] else { continue }
                block.animator().frame = CGRect(
                    x: self.layout.x(for: seg.targetRange.start),
                    y: TrackCanvasView.SegmentVisuals.blockVPadding,
                    width: max(self.layout.width(for: seg.targetRange.duration), 16),
                    height: blockH
                )
                block.animator().alphaValue = 1.0
                block.layer?.zPosition = 0
            }
        }
    }

    private func cancelReorder() {
        guard isReordering, let draggingID else { return }

        isReordering    = false
        self.draggingID = nil
        reorderOffset   = 0

        for seg in track.segments {
            segmentViews[seg.id]?.layer?.setAffineTransform(.identity)
        }

        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            for seg in self.track.segments {
                guard let block = self.segmentViews[seg.id] else { continue }
                block.animator().frame = CGRect(
                    x: self.layout.x(for: seg.targetRange.start),
                    y: TrackCanvasView.SegmentVisuals.blockVPadding,
                    width: max(self.layout.width(for: seg.targetRange.duration), 16),
                    height: blockH
                )
                block.animator().alphaValue = 1.0
                block.layer?.zPosition = 0
            }
        }
    }

    private func reorderX(for slot: Int) -> CGFloat {
        TrackCanvasView.leftPadding + reorderOffset + CGFloat(slot) * (reorderCardWidth + reorderGap)
    }

    // MARK: - Free-drag mode (attachment tracks only)

    private func beginFreeDrag(segmentID: UUID, touchX: CGFloat) {
        guard !isFreeDragging,
              let block = segmentViews[segmentID],
              let seg = track.segments.first(where: { $0.id == segmentID }) else { return }

        isFreeDragging        = true
        freeDragSegmentID     = segmentID
        freeDragStartTime     = seg.targetRange.start
        freeDragStartTouchX   = touchX
        freeDragLastSnapTime  = -1

        onScrollLock?(true)
        block.layer?.zPosition = 10
        block.alphaValue = 0.88
    }

    private func updateFreeDrag(touchX: CGFloat) {
        guard isFreeDragging, let segmentID = freeDragSegmentID,
              let block = segmentViews[segmentID],
              let seg = track.segments.first(where: { $0.id == segmentID }) else { return }

        let dx       = touchX - freeDragStartTouchX
        let rawStart = max(0, freeDragStartTime + layout.timeDelta(for: dx))
        let snapped  = freeDragSnap(rawStart, duration: seg.targetRange.duration, excludeID: segmentID)
        block.frame.origin.x = layout.x(for: snapped)
    }

    private func freeDragSnap(_ start: Double, duration: Double, excludeID: UUID) -> Double {
        let threshold = max(0.1, 8.0 / Double(layout.pixelsPerSecond))
        var edges: [Double] = [0]
        for seg in track.segments where seg.id != excludeID {
            edges.append(seg.targetRange.start)
            edges.append(seg.targetRange.end)
        }
        let checkPoints = [start, start + duration]
        for point in checkPoints {
            if let nearest = edges.min(by: { abs($0 - point) < abs($1 - point) }),
               abs(nearest - point) <= threshold {
                let offset = point - start
                let result = nearest - offset
                if abs(nearest - freeDragLastSnapTime) > 0.01 {
                    // AppKit 的触觉反馈API适配：触发 alignment 类型的吸附反馈
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    freeDragLastSnapTime = nearest
                }
                return max(0, result)
            }
        }
        freeDragLastSnapTime = -1
        return start
    }

    private func commitFreeDrag() {
        guard isFreeDragging,
              let segmentID = freeDragSegmentID,
              let block = segmentViews[segmentID],
              let seg = track.segments.first(where: { $0.id == segmentID })
        else {
            finishFreeDrag()
            return
        }

        let currentStart = layout.time(at: block.frame.origin.x)
        let siblings     = track.segments.filter { $0.id != segmentID }.map { $0.targetRange }
        let blockH       = TrackCanvasView.trackHeight - 8

        if Self.isValidPosition(currentStart, duration: seg.targetRange.duration, siblings: siblings) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                block.animator().alphaValue = 1.0
                block.layer?.zPosition = 0
            }
            onMoveCommit?(segmentID, currentStart)
        } else {
            // macOS AppKit 不支持 UIKit 的弹簧参数（usingSpringWithDamping），这里使用 easeOut 进行弹性回弹
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                
                block.animator().frame = CGRect(
                    x: self.layout.x(for: self.freeDragStartTime),
                    y: TrackCanvasView.SegmentVisuals.blockVPadding,
                    width: max(self.layout.width(for: seg.targetRange.duration), 16),
                    height: blockH
                )
                block.animator().alphaValue = 1.0
                block.layer?.zPosition = 0
            }
        }

        finishFreeDrag()
    }

    private func cancelFreeDrag() {
        guard isFreeDragging,
              let segmentID = freeDragSegmentID,
              let block = segmentViews[segmentID],
              let seg = track.segments.first(where: { $0.id == segmentID })
        else {
            finishFreeDrag()
            return
        }

        let blockH = TrackCanvasView.trackHeight - TrackCanvasView.SegmentVisuals.blockVPadding * 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            
            block.animator().frame = CGRect(
                x: self.layout.x(for: self.freeDragStartTime),
                y: TrackCanvasView.SegmentVisuals.blockVPadding,
                width: max(self.layout.width(for: seg.targetRange.duration), 16),
                height: blockH
            )
            block.animator().alphaValue = 1.0
            block.layer?.zPosition = 0
        }

        finishFreeDrag()
    }

    private func finishFreeDrag() {
        isFreeDragging       = false
        freeDragSegmentID    = nil
        freeDragLastSnapTime = -1
        onScrollLock?(false)
    }

    private static func isValidPosition(_ start: Double, duration: Double, siblings: [TimeRange]) -> Bool {
        let end = start + duration
        return !siblings.contains { $0.start < end - 0.001 && $0.end > start + 0.001 }
    }
}
