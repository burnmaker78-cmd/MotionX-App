
#if canImport(UIKit)
import SwiftUI
import PhotosUI
import AVFoundation
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

public struct ClipEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: EditorStore
    @State private var libraryStore = TimelineLibraryStore()
    @State private var activeProjectID: UUID?
    @State private var activeToolCategory: EditorToolCategory? = nil
    @State private var coordinator = CompositionCoordinator()
    @State private var draftStore = DraftStore()

    private let onExport: ((Data, URL, UIImage) -> Void)?
    private let onDraftSave: ((UUID, EditorTimeline) -> Void)?

    private var transitionEditContext: TransitionEditContext? {
        store.selection.editingTransitionContext
    }

    public init(
        libraryStore: TimelineLibraryStore,
        project: LibraryProject,
        onDraftSave: ((UUID, EditorTimeline) -> Void)? = nil,
        onExport: ((Data, URL, UIImage) -> Void)? = nil
    ) {
        self.onDraftSave = onDraftSave
        self.onExport = onExport
        _store = State(initialValue: EditorStore(timeline: project.timeline))
        _libraryStore = State(initialValue: libraryStore)
        _activeProjectID = State(initialValue: project.id)
    }

    private let controlBarHeight: CGFloat = 52
    private let trackMinHeight: CGFloat = 140

    @State private var showAddMediaPicker = false
    @State private var addMediaItems: [PhotosPickerItem] = []
    @State private var pendingVisualTrackID: UUID?
    @State private var pendingAudioTrackID: UUID?
    @State private var showExport = false
    @State private var showExportConfig = false
    @State private var showFullScreenPreview = false

    public var body: some View {
        editorSheets(editorObservers(editorContent))
    }

    private var editorContent: some View {
        GeometryReader { geo in
            let previewHeight = UIDevice.current.userInterfaceIdiom == .pad
                ? geo.size.height * 0.62
                : geo.size.height * 0.53

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    EditorPreviewView(
                        store: store,
                        compositionPlayer: coordinator.player,
                        timelinePreviewView: coordinator.timelinePreviewView
                    )
                    .frame(height: previewHeight)

                    Divider().background(Color.white.opacity(0.08))

                    EditorControlBar(
                        store: store,
                        onRequestFullScreenPreview: {
                            showFullScreenPreview = true
                        }
                    )
                    .frame(height: controlBarHeight)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .trailing) {
                        undoRedoButtons
                            .padding(.trailing, 55)
                    }

                    ZStack(alignment: .topTrailing) {
                        TrackEditorRepresentable(
                            store: store,
                            onEmptyTrackAdd: handleEmptyTrackAdd
                        )
                        .frame(minHeight: trackMinHeight, maxHeight: .infinity)

                        addSegmentButton
                            .padding(
                                .top,
                                TrackCanvasView.rulerHeight
                                    + TrackCanvasView.SegmentVisuals.blockVPadding
                            )
                            .padding(.trailing, 8)
                    }

                    EditorBottomToolbar(
                        activeCategory: $activeToolCategory
                    )
                }

                panelOverlay(geo: geo)
            }
            .animation(.spring(duration: 0.25), value: activeToolCategory)
        }
    }

    // MARK: - Sheets

    func editorSheets(_ base: some View) -> some View {
        base
            .background(Color(white: 0.08).ignoresSafeArea())
            .background(
                NavigationLink(
                    destination: ExportResultView(
                        store: store,
                        onExport: onExport
                    ),
                    isActive: $showExport,
                    label: { EmptyView() }
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .sheet(
                isPresented: Binding(
                    get: { transitionEditContext != nil },
                    set: {
                        if !$0 {
                            store.selection.editingTransitionContext = nil
                        }
                    }
                )
            ) {
                if let ctx = transitionEditContext {
                    TransitionEditSheet(context: ctx, store: store)
                        .presentationDetents([.height(310)])
                        .presentationDragIndicator(.hidden)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { store.ttsConfigSheetTargets != nil },
                    set: {
                        if !$0 {
                            store.ttsConfigSheetTargets = nil
                        }
                    }
                )
            ) {
                if let targets = store.ttsConfigSheetTargets {
                    TTSConfigSheet(
                        store: store,
                        targetSegmentIDs: targets,
                        onDismiss: {
                            store.ttsConfigSheetTargets = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showExportConfig) {
                ExportConfigSheet(store: store) {
                    showExportConfig = false
                }
            }
            .fullScreenCover(isPresented: $showFullScreenPreview) {
                FullScreenPreviewView(timeline: store.timeline) { exitTime in
                    showFullScreenPreview = false

                    let exitSeconds = exitTime.seconds
                    if exitSeconds.isFinite, exitSeconds >= 0 {
                        store.seek(to: exitSeconds)
                    }
                }
            }
            .onChange(of: showFullScreenPreview) { _, isPresented in
                if isPresented {
                    if store.isPlaying {
                        store.pause()
                    }
                    coordinator.suspendTimelineRuntime()
                } else {
                    coordinator.resumeTimelineRuntime()
                }
            }
            .photosPicker(
                isPresented: $showAddMediaPicker,
                selection: $addMediaItems,
                maxSelectionCount: 8,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            )
    }

    // MARK: - Observers

    func editorObservers(_ base: some View) -> some View {
        base
            .onChange(of: addMediaItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await loadAddMedias(items: items)
                }
            }
            .onAppear {
                coordinator.attach(to: store)
                store.coordinatorPlayer = coordinator.player
                store.coordinator = coordinator
                coordinator.scheduleRebuild(
                    timeline: store.timeline,
                    immediate: true
                )
                draftStore.bind(to: store)
                Task {
                    await store.normalizeAudioDurations()
                }
            }
            .onDisappear {
                saveDraftAndNotify()
                draftStore.unbind()
            }
            .onChange(of: store.compositionVersion) { _, _ in
                coordinator.scheduleRebuild(timeline: store.timeline)
            }
            .onChange(of: store.selection.singleSelectedID) { _, newID in
                guard let id = newID,
                      let seg = store.timeline.segment(id: id) else {
                    return
                }

                switch seg.content {
                case .text, .subtitle:
                    activeToolCategory = .text
                case .audio:
                    activeToolCategory = .audio
                case .video, .image:
                    activeToolCategory = .clip
                }
            }
            .onChange(of: store.selection.editingSegmentID) { oldValue, newValue in
                guard newValue == nil,
                      let oldID = oldValue,
                      let seg = store.timeline.segment(id: oldID) else {
                    return
                }

                let textToCheck: String

                switch seg.content {
                case .text(let content):
                    textToCheck = content.text
                case .subtitle(let content):
                    textToCheck = content.text
                default:
                    return
                }

                if textToCheck.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    store.deleteSegment(id: oldID)
                }
            }
            .onChange(of: activeToolCategory) { _, newCategory in
                if newCategory != .audio {
                    pendingAudioTrackID = nil
                }

                guard let newCategory,
                      let segID = store.selection.singleSelectedID,
                      let seg = store.timeline.segment(id: segID),
                      !categoryMatchesSelection(
                        newCategory,
                        segment: seg
                      ) else {
                    return
                }

                store.selection.deselect()
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                        saveDraftAndNotify()
                        draftStore.unbind()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        specButton
                        exportButton
                    }
                }

                ToolbarItem(placement: .title) {
                    Text(store.timeline.metadata.productName ?? "Edit")
                        .foregroundColor(.white)
                }
            }
    }

    // MARK: - Toolbar Items

    private var undoRedoButtons: some View {
        HStack(spacing: 4) {
            Button(action: { store.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!store.canUndo)

            Button(action: { store.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!store.canRedo)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var addSegmentButton: some View {
        Button {
            pendingVisualTrackID = nil
            showAddMediaPicker = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(
                    width: 40,
                    height: TrackCanvasView.trackHeight
                        - TrackCanvasView.SegmentVisuals.blockVPadding * 2
                )
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func handleEmptyTrackAdd(
        trackID: UUID,
        kind: EditorTrack.Kind
    ) {
        store.selection.deselect()

        switch kind {
        case .overlay:
            pendingVisualTrackID = trackID
            showAddMediaPicker = true
        case .audio:
            pendingAudioTrackID = trackID
            activeToolCategory = .audio
        case .text:
            _ = store.createNewTextSegment(targetTrackID: trackID)
            activeToolCategory = .text
        case .subtitle:
            _ = store.createNewSubtitleSegment(targetTrackID: trackID)
            activeToolCategory = .text
        case .video:
            pendingVisualTrackID = nil
            showAddMediaPicker = true
        case .adjustment:
            activeToolCategory = .adjust
        }
    }

    private func saveDraftAndNotify() {
        let draftID = DraftStore.save(store.timeline)
        onDraftSave?(draftID, store.timeline)
        persistActiveProject()
    }

    private func persistActiveProject() {
        guard let id = activeProjectID else { return }

        var project = LibraryProject(
            id: id,
            name: "Untitled Project",
            timeline: store.timeline
        )

        if let existing = libraryStore.projects.first(where: { $0.id == id }) {
            project.name = existing.name
        }

        _ = try? libraryStore.saveProject(project)
    }

    // MARK: - Panel Overlay

    @ViewBuilder
    private func panelOverlay(geo: GeometryProxy) -> some View {
        if let segID = store.selection.editingSegmentID,
           let seg = store.timeline.segment(id: segID),
           (seg.isText || seg.isSubtitle) {
            TextEditPanel(segmentID: segID, store: store)
                .frame(maxHeight: geo.size.height * 0.45)
                .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if let segID = store.selection.editingSegmentID,
                  store.timeline.segment(id: segID)?.isAudio == true {
            AudioEditPanel(segmentID: segID, store: store)
                .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .text,
                  let segID = store.selection.singleSelectedID,
                  let seg = store.timeline.segment(id: segID),
                  (seg.isText || seg.isSubtitle) {
            TextSegmentActionPanel(
                segmentID: segID,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .clip,
                  let segID = store.selection.singleSelectedID,
                  store.timeline.mainTrack?.segment(id: segID) != nil {
            SegmentReplacePanel(
                segmentID: segID,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        // Effects panel connection.
        // Keeps the selected video/image clip selected.
        } else if activeToolCategory == .effects,
                  let segID = store.selection.singleSelectedID,
                  let seg = store.timeline.segment(id: segID),
                  isVisualSegment(seg) {
            EditorSecondaryToolPanel(
                category: .effects,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .adjust,
                  let segID = store.selection.singleSelectedID,
                  store.timeline.mainTrack?.segment(id: segID) != nil {
            ColorAdjustmentPanel(
                segmentID: segID,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .animation,
                  let segID = store.selection.singleSelectedID,
                  store.timeline.mainTrack?.segment(id: segID) != nil {
            AnimationPickerSheet(
                segmentID: segID,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .audio,
                  let segID = store.selection.singleSelectedID,
                  store.timeline.segment(id: segID)?.isAudio == true {
            AudioSegmentActionPanel(
                segmentID: segID,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if activeToolCategory == .audio {
            AudioSecondaryPanel(
                store: store,
                targetTrackID: pendingAudioTrackID,
                onTargetConsumed: {
                    pendingAudioTrackID = nil
                },
                onDismiss: {
                    activeToolCategory = nil
                    pendingAudioTrackID = nil
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        } else if let category = activeToolCategory {
            EditorSecondaryToolPanel(
                category: category,
                store: store,
                onDismiss: {
                    activeToolCategory = nil
                    store.selection.deselect()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func isVisualSegment(_ segment: EditorSegment) -> Bool {
        switch segment.content {
        case .video, .image:
            return true
        default:
            return false
        }
    }

    // MARK: - Tool Category Dispatch

    private func categoryMatchesSelection(
        _ category: EditorToolCategory,
        segment: EditorSegment
    ) -> Bool {
        switch (category, segment.content) {
        case (.text, .text), (.text, .subtitle):
            return true
        case (.audio, .audio):
            return true
        case (.clip, .video), (.clip, .image):
            return true
        case (.adjust, .video), (.adjust, .image):
            return true
        case (.animation, .video), (.animation, .image):
            return true
        case (.effects, .video), (.effects, .image):
            return true
        default:
            return false
        }
    }

    // MARK: - Add Media

    private func loadAddMedias(items: [PhotosPickerItem]) async {
        let targetTrackID = await MainActor.run {
            pendingVisualTrackID
        }

        defer {
            Task { @MainActor in
                addMediaItems = []
                pendingVisualTrackID = nil
            }
        }

        var pendingURLs: [URL] = []
        var stagingFiles: [URL] = []

        for item in items {
            if let movie = try? await item.loadTransferable(
                type: VideoTransferable.self
            ) {
                pendingURLs.append(movie.url)
                continue
            }

            if let data = try? await item.loadTransferable(type: Data.self) {
                let ext = item.supportedContentTypes.first?
                    .preferredFilenameExtension ?? "jpg"

                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)

                do {
                    try data.write(to: staging)
                } catch {
                    continue
                }

                stagingFiles.append(staging)
                pendingURLs.append(staging)
            }
        }

        guard !pendingURLs.isEmpty else { return }

        let libraryURLs = await libraryStore.addMedia(urls: pendingURLs)

        for url in stagingFiles {
            try? FileManager.default.removeItem(at: url)
        }

        guard !libraryURLs.isEmpty else { return }

        var segments: [(url: URL, native: Double?)] = []

        for libraryURL in libraryURLs {
            let type = try? libraryURL.resourceValues(
                forKeys: [.contentTypeKey]
            ).contentType

            let isVideo = type?.conforms(to: .movie) == true
                || type?.conforms(to: .video) == true

            let native = isVideo ? await avDuration(of: libraryURL) : nil
            segments.append((libraryURL, native))
        }

        await MainActor.run {
            for (url, native) in segments {
                store.addVisualSegment(
                    localURL: url,
                    nativeDuration: native,
                    targetTrackID: targetTrackID
                )
            }
        }
    }

    private func avDuration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)

        guard let duration = try? await asset.load(.duration),
              duration.isNumeric,
              duration.seconds > 0 else {
            return nil
        }

        return duration.seconds
    }

    private var exportButton: some View {
        Button("Export") {
            store.pause()
            showExport = true
        }
        .foregroundStyle(.white)
        .fontWeight(.medium)
    }

    private var specButton: some View {
        Button {
            showExportConfig = true
        } label: {
            Text(store.timeline.effectiveExportConfig.resolution.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(6)
        }
        .accessibilityLabel(
            "Export settings: \(store.timeline.effectiveExportConfig.resolution.label)"
        )
    }
}

// MARK: - UIKit Bridge

struct TrackEditorRepresentable: UIViewControllerRepresentable {
    var store: EditorStore
    var onEmptyTrackAdd: ((UUID, EditorTrack.Kind) -> Void)?

    func makeUIViewController(
        context: Context
    ) -> ClipEditorViewController {
        let controller = ClipEditorViewController(store: store)
        controller.onEmptyTrackAdd = onEmptyTrackAdd
        return controller
    }

    func updateUIViewController(
        _ controller: ClipEditorViewController,
        context: Context
    ) {
        controller.onEmptyTrackAdd = onEmptyTrackAdd
        controller.apply(
            timeline: store.timeline,
            selection: store.selection
        )
    }
}
#endif
