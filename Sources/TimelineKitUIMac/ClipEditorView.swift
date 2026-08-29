#if canImport(AppKit)
import SwiftUI
import AVFoundation
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

/// Public entry point for the macOS clip editor (FCP-style four-zone layout).
///
/// Layout:
///   - Top toolbar (MacEditorToolbar): import / title / export placeholder
///   - Vertical split: top area (Browser | Viewer | Inspector) over Timeline
///   - Viewer reuses the shared SwiftUI preview + playback controls
///   - Timeline uses the AppKit track canvas (scroll/select/scrub/zoom)
///
/// The whole shell is an AppKit container (NSSplitView) hosted via
/// NSViewRepresentable — draggable dividers and native split behavior come from
/// AppKit, mirroring the rationale of iOS using UIKit for TrackCanvasView.
public struct ClipEditorView: View {
    @State private var store: EditorStore
    @State private var coordinator = CompositionCoordinator()
    @State private var draftStore  = DraftStore()
    private let onDraftSave: ((UUID, EditorTimeline) -> Void)?

    public init(
        store: EditorStore,
        onDraftSave: ((UUID, EditorTimeline) -> Void)? = nil
    ) {
        _store = State(initialValue: store)
        self.onDraftSave = onDraftSave
    }

    public var body: some View {
        MacEditorShellRepresentable(
            store: store,
            compositionPlayer: coordinator.player,
            timelinePreviewView: coordinator.timelinePreviewView
        )
        // NSView default intrinsicContentSize is noIntrinsicMetric; SwiftUI would
        // otherwise size the AppKit shell to 0 height. Force it to fill.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .onAppear {
            coordinator.attach(to: store)
            store.coordinatorPlayer = coordinator.player
            store.coordinator       = coordinator
            coordinator.scheduleRebuild(timeline: store.timeline, immediate: true)
            draftStore.bind(to: store)
        }
        .onDisappear {
            saveDraftAndNotify()
        }
    }

    // MARK: - Draft persistence

    private func saveDraftAndNotify() {
        let draftID = store.document.id
        let timeline = store.timeline
        _ = DraftStore.save(timeline)
        onDraftSave?(draftID, timeline)
    }
}

// MARK: - SwiftUI bridge

/// Embeds the AppKit editor shell (NSSplitView four-zone layout) into SwiftUI.
struct MacEditorShellRepresentable: NSViewRepresentable {
    let store: EditorStore
    let compositionPlayer: AVPlayer?
    let timelinePreviewView: TimelinePreviewView?

    func makeNSView(context: Context) -> MacEditorShellView {
        MacEditorShellView(
            store: store,
            compositionPlayer: compositionPlayer,
            timelinePreviewView: timelinePreviewView
        )
    }

    func updateNSView(_ nsView: MacEditorShellView, context: Context) {
        nsView.apply(timeline: store.timeline, selection: store.selection)
    }
}

#endif
