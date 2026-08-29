#if canImport(AppKit)
import AppKit
import AVFoundation
import TimelineKitCore
import TimelineKitUIShared
import TimelineKitUISharedViews

// MARK: - MacEditorShellView

/// AppKit root container for the macOS editor shell (FCP style).
///
/// Layout:
///   - top toolbar (MacEditorToolbar)
///   - vertical split (NSSplitViewController):
///       - top area (MacEditorTopAreaView: Browser | Viewer | Inspector)
///       - timeline area (MacTimelineCanvasHost + control bar)
///
/// NSSplitViewController + NSSplitViewItem provide the initial proportions
/// (`preferredThicknessFraction`) and min/max pane sizes (`minimumThickness`)
/// natively — no manual divider math, no setPosition timing issues.
@MainActor
final class MacEditorShellView: NSView {

    // MARK: - Minimum heights

    static let topAreaMinHeight: CGFloat = 240
    static let timelineMinHeight: CGFloat = 140

    // MARK: - Subviews

    private let toolbar = MacEditorToolbar(frame: .zero)
    private let splitController = NSSplitViewController()
    private let topArea: MacEditorTopAreaView
    private let timelineHost: MacTimelineCanvasHost
    private let store: EditorStore

    /// Forwarded to the demo / host so it can present the system file picker.
    var onImportMedia: (() -> Void)? {
        get { toolbar.onImportMedia }
        set { toolbar.onImportMedia = newValue }
    }

    // MARK: - Init

    init(store: EditorStore, compositionPlayer: AVPlayer?, timelinePreviewView: TimelinePreviewView?) {
        self.store = store
        self.topArea = MacEditorTopAreaView(
            store: store,
            compositionPlayer: compositionPlayer,
            timelinePreviewView: timelinePreviewView
        )
        self.timelineHost = MacTimelineCanvasHost(store: store)
        super.init(frame: .zero)
        // 强制深色外观：编辑器整体是深色主题（与 iOS 端 Color(white:0.08) 一致）。
        // 不设置时系统浅色外观会让 windowBackgroundColor 等语义色解析为白色，
        // 与时间线/预览的硬编码深色背景不一致。
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// preferredThicknessFraction does not apply when the NSSplitViewController
    /// is embedded as a plain view (not a real VC hierarchy). Set the initial
    /// split position once the window is available instead.
    private var didSetInitialSplit = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didSetInitialSplit else { return }
        didSetInitialSplit = true
        let split = splitController.splitView
        guard split.bounds.height > 0 else { return }
        split.setPosition(split.bounds.height * 2.0 / 3.0, ofDividerAt: 0)
    }

    private func setupViews() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        // Top area pane.
        let topVC = NSViewController()
        topVC.view = topArea
        let topItem = NSSplitViewItem(viewController: topVC)
        topItem.minimumThickness = Self.topAreaMinHeight
        topItem.preferredThicknessFraction = 2.0 / 3.0
        splitController.addSplitViewItem(topItem)

        // Timeline pane.
        let timelineVC = NSViewController()
        timelineVC.view = timelineHost
        let timelineItem = NSSplitViewItem(viewController: timelineVC)
        timelineItem.minimumThickness = Self.timelineMinHeight
        timelineItem.preferredThicknessFraction = 1.0 / 3.0
        splitController.addSplitViewItem(timelineItem)

        // Access .view first: it triggers viewDidLoad, which is what populates
        // splitView.arrangedSubviews from splitViewItems. Reading .splitView
        // alone leaves arrangedSubviews empty (lazy load).
        _ = splitController.view

        // Vertical split: top area above timeline.
        let splitView = splitController.splitView
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: MacEditorToolbar.height),

            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Timeline state push (called by the SwiftUI shell)

    func apply(timeline: EditorTimeline, selection: SelectionState) {
        timelineHost.apply(timeline: timeline, selection: selection)
    }
}

#endif
