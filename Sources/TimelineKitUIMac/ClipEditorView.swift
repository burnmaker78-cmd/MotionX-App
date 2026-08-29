#if canImport(AppKit)
import SwiftUI
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

/// Public entry point for the macOS clip editor (剪映 Mac 风格两区布局).
///
/// Layout (mirrors iOS `ClipEditorView` structure, adapted for macOS):
///   Zone 1 — Preview : EditorPreviewView (top, flexible) + EditorControlBar playback controls
///   Zone 2 — Timeline : AppKit track area (MacTimelineRepresentable — scroll/select/scrub/zoom)
///
/// The AppKit timeline canvas is hosted via NSViewRepresentable so the complex
/// interaction surface (scroll, scrub, zoom, multi-row sync) keeps native
/// fidelity — same rationale as iOS using UIKit for TrackCanvasView.
public struct ClipEditorView: View {
    @State private var store: EditorStore
    @State private var coordinator = CompositionCoordinator()
    @State private var draftStore  = DraftStore()
    private let onDraftSave: ((UUID, EditorTimeline) -> Void)?

    private let previewFraction: CGFloat = 0.52

    public init(
        store: EditorStore,
        onDraftSave: ((UUID, EditorTimeline) -> Void)? = nil
    ) {
        _store = State(initialValue: store)
        self.onDraftSave = onDraftSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Zone 1: Preview + playback controls ──────────────────────────
            VStack(spacing: 0) {
                EditorPreviewView(
                    store: store,
                    compositionPlayer: coordinator.player,
                    timelinePreviewView: coordinator.timelinePreviewView
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                EditorControlBar(store: store)
                    .frame(height: 52)
                    .padding(.horizontal, 12)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .background(Color.white.opacity(0.1))

            // ── Zone 2: AppKit timeline ──────────────────────────────────────
            MacTimelineRepresentable(store: store)
                .frame(minHeight: 160, maxHeight: .infinity)
        }
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

#endif
