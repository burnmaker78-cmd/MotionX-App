#if canImport(AppKit)
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

/// Public entry point for the macOS clip editor (FCP-style four-zone layout).
///
/// Layout:
///   - Top: system unified toolbar — title + import/export (host sets the style;
///     buttons live in `.toolbar` below)
///   - Vertical split: top area (Browser | Viewer | Inspector) over Timeline
///   - Viewer reuses the shared SwiftUI preview + playback controls
///   - Timeline uses the AppKit track canvas (scroll/select/scrub/zoom)
///
/// Media import: the系统 fileImporter lives here (SwiftUI) — the toolbar's
/// "导入素材" button opens it; selected files are added to the timeline via
/// EditorStore (video/image/audio auto-routed to the right track).
public struct ClipEditorView: View {
    @State private var store: EditorStore
    @State private var coordinator = CompositionCoordinator()
    @State private var draftStore  = DraftStore()
    @State private var libraryStore = TimelineLibraryStore()
    private let onDraftSave: ((UUID, EditorTimeline) -> Void)?
    @State private var showAddMediaPicker = false
    @State private var showCreateOrOpenLibrary = false
    @State private var errorMessage: String?
    @State private var isImporting = false

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
            libraryStore: libraryStore,
            timeline: store.document.timeline,
            selection: store.document.selection,
            compositionPlayer: coordinator.player,
            timelinePreviewView: coordinator.timelinePreviewView,
            onImportMedia: { showAddMediaPicker = true },
            onCreateOrOpenLibrary: { showCreateOrOpenLibrary = true }
        )
        // NSView default intrinsicContentSize is noIntrinsicMetric; SwiftUI would
        // otherwise size the AppKit shell to 0 height. Force it to fill.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        // Set the window title to "TimelineKit" so the unified titlebar shows a
        // single title (not the Xcode target's window name). .toolbar(.principal)
        // merely overlays a view and would duplicate the system title.
        .navigationTitle("TimelineKit")
        .toolbar {
            // Import — opens the fileImporter (host may also trigger via callback).
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddMediaPicker = true
                } label: {
                    Label("导入素材", systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)
            }
            // Export — placeholder until the export pipeline lands.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Placeholder.
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(true)
            }
        }
                .onAppear {
            coordinator.attach(to: store)
            store.coordinatorPlayer = coordinator.player
            store.coordinator       = coordinator
            coordinator.scheduleRebuild(timeline: store.timeline, immediate: true)
            draftStore.bind(to: store)
        }
        .onChange(of: store.compositionVersion) { _, _ in
            coordinator.scheduleRebuild(timeline: store.timeline)
        }
        .onDisappear {
            saveDraftAndNotify()
        }
        .fileImporter(
            isPresented: $showAddMediaPicker,
            allowedContentTypes: [.movie, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await addMedia(urls: urls) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("资源库", isPresented: $showCreateOrOpenLibrary, titleVisibility: .visible) {
            Button("创建资源库…") {
                presentCreateLibraryPanel()
            }
            Button("打开已有资源库…") {
                presentOpenLibraryPanel()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("资源库存放媒体与项目，可选择任意可访问位置保存。")
        }
    }

    // MARK: - Library panels (AppKit)

    /// NSSavePanel: pick a location + name for a new .tlkbundle, then create it.
    private func presentCreateLibraryPanel() {
        let panel = NSSavePanel()
        panel.title = "创建资源库"
        panel.nameFieldStringValue = "未命名资源库"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.folder]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let bundleURL = url.pathExtension.lowercased() == "tlkbundle"
                ? url
                : url.appendingPathExtension("tlkbundle")
            do {
                try self.libraryStore.createLibrary(at: bundleURL)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// NSOpenPanel: pick an existing .tlkbundle and open it.
    private func presentOpenLibraryPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开资源库"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.libraryStore.openLibrary(at: url)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Add Media

    /// Add imported URLs to the timeline, auto-routing by type:
    /// video/image → visual segment (main/overlay track), audio → audio track.
    ///
    /// macOS sandbox: fileImporter returns security-scoped URLs into the user's
    /// folders (e.g. ~/Downloads). Security scope only lasts as long as
    /// startAccessingSecurityScopedResource() is held, but the render pipeline
    /// reads these URLs later on background threads. So we COPY each file into
    /// the app container's temporary directory and use the copies — otherwise
    /// AVFoundation can't open the media (Code=257 permission denied, "no video
    /// track").
    /// Import URLs into the current library, then add the library copies to the
    /// current timeline. The library persists media in `Media/` so the files
    /// survive even if the source location changes or temporary caches clear.
    private func addMedia(urls: [URL]) async {
        await MainActor.run { isImporting = true }
        defer {
            Task { @MainActor in isImporting = false }
        }

        // Import into the library (copies files to Media/<assetID>.<ext>).
        let libraryURLs = libraryStore.addMedia(urls: urls)
        guard !libraryURLs.isEmpty else {
            if let msg = libraryStore.errorMessage { errorMessage = msg }
            return
        }

        for libraryURL in libraryURLs {
            let ext = libraryURL.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v", "avi", "mpeg"].contains(ext)
            let isImage = ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext)
            let isAudio = ["mp3", "m4a", "wav", "aac", "caf"].contains(ext)

            if isVideo || isImage {
                let native = isVideo ? (await avDuration(of: libraryURL) ?? 0) : nil
                await MainActor.run {
                    _ = store.addVisualSegment(localURL: libraryURL, nativeDuration: native)
                }
            } else if isAudio {
                let native = await avDuration(of: libraryURL) ?? 0
                await MainActor.run {
                    _ = store.addAudioSegment(localURL: libraryURL, nativeDuration: native)
                }
            } else if let type = try? libraryURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                if type.conforms(to: .movie) || type.conforms(to: .video) {
                    let native = await avDuration(of: libraryURL) ?? 0
                    await MainActor.run {
                        _ = store.addVisualSegment(localURL: libraryURL, nativeDuration: native)
                    }
                } else if type.conforms(to: .audio) {
                    let native = await avDuration(of: libraryURL) ?? 0
                    await MainActor.run {
                        _ = store.addAudioSegment(localURL: libraryURL, nativeDuration: native)
                    }
                }
            }
        }
    }

    private func avDuration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration),
              dur.isNumeric, dur.seconds > 0 else { return nil }
        return dur.seconds
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
///
/// `timeline`/`selection` are Equatable inputs: SwiftUI re-invokes `updateNSView`
/// whenever they change, letting the AppKit canvas refresh. The shell itself is
/// built once in `makeNSView` from the real `store` (so interactions stay wired),
/// and its timeline/selection are kept in sync here.
struct MacEditorShellRepresentable: NSViewRepresentable {
    let store: EditorStore
    let libraryStore: TimelineLibraryStore
    let timeline: EditorTimeline
    let selection: SelectionState
    let compositionPlayer: AVPlayer?
    let timelinePreviewView: TimelinePreviewView?
    var onImportMedia: (() -> Void)?
    var onCreateOrOpenLibrary: (() -> Void)?

    func makeNSView(context: Context) -> MacEditorShellView {
        MacEditorShellView(
            store: store,
            libraryStore: libraryStore,
            compositionPlayer: compositionPlayer,
            timelinePreviewView: timelinePreviewView,
            onImportMedia: onImportMedia,
            onCreateOrOpenLibrary: onCreateOrOpenLibrary
        )
    }

    func updateNSView(_ nsView: MacEditorShellView, context: Context) {
        nsView.apply(timeline: timeline, selection: selection)
    }
}

#endif
