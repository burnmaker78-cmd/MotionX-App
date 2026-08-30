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
    private let onDraftSave: ((UUID, EditorTimeline) -> Void)?
    private let onImportMedia: (() -> Void)?
    @State private var showAddMediaPicker = false
    @State private var errorMessage: String?
    @State private var isImporting = false

    public init(
        store: EditorStore,
        onDraftSave: ((UUID, EditorTimeline) -> Void)? = nil,
        onImportMedia: (() -> Void)? = nil
    ) {
        _store = State(initialValue: store)
        self.onDraftSave = onDraftSave
        self.onImportMedia = onImportMedia
    }

    public var body: some View {
        MacEditorShellRepresentable(
            store: store,
            timeline: store.document.timeline,
            selection: store.document.selection,
            compositionPlayer: coordinator.player,
            timelinePreviewView: coordinator.timelinePreviewView
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
    private func addMedia(urls: [URL]) async {
        await MainActor.run { isImporting = true }
        defer {
            Task { @MainActor in isImporting = false }
        }

        for url in urls {
            // Keep the security scope while copying, then release it.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            // Copy into the sandbox container so the URL stays readable for the
            // whole session (import, preview, thumbnails, export).
            guard let containerURL = Self.importCopy(of: url) else {
                errorMessage = "无法读取素材：\(url.lastPathComponent)"
                continue
            }

            let type: UTType
            if let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                type = t
            } else {
                type = .data
            }

            if type.conforms(to: .movie) || type.conforms(to: .video) {
                let native = await avDuration(of: containerURL) ?? 0
                await MainActor.run {
                    _ = store.addVisualSegment(localURL: containerURL, nativeDuration: native)
                }
            } else if type.conforms(to: .image) {
                await MainActor.run {
                    _ = store.addVisualSegment(localURL: containerURL, nativeDuration: nil)
                }
            } else if type.conforms(to: .audio) {
                let native = await avDuration(of: containerURL) ?? 0
                await MainActor.run {
                    _ = store.addAudioSegment(localURL: containerURL, nativeDuration: native)
                }
            }
        }
    }

    /// Copy an imported (security-scoped) file into the app container.
    private static func importCopy(of source: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimelineKitImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = source.pathExtension.isEmpty ? "media" : source.pathExtension
        let dest = dir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return nil
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
    let timeline: EditorTimeline
    let selection: SelectionState
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
        nsView.apply(timeline: timeline, selection: selection)
    }
}

#endif
