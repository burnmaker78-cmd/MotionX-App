//
//  VideoEditorHostView.swift
//  VideoEditorDemo
//
//  Created by xiaoyuan on 2026/8/29.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import TimelineKitCore
import TimelineKitUIShared
import TimelineKitUIMac

/// Landing view: pick media files, build a timeline, enter the macOS clip editor.
struct VideoEditorView: View {
    @State private var editorStore: EditorStore
    @State private var isImporting = false
    @State private var isShowingPicker = false
    @State private var errorMessage: String?
    
    init(editorStore: EditorStore? = nil) {
        if let editorStore {
            self.editorStore = editorStore
        } else {
            let timelineSchema = ServerTimelineSchema(version: "v1", duration: 0, fps: 30, canvas: SCanvas(width: 1920, height: 1080), scenes: [])
            let timeline = TimelineImporter.importing(from: timelineSchema)
            self.editorStore = EditorStore(timeline: timeline)
        }
    }

    var body: some View {
        ClipEditorView(store: editorStore) { _, _ in
            // Draft already saved inside ClipEditorView; keep hook for future.
        }
        .fileImporter(
            isPresented: $isShowingPicker,
            allowedContentTypes: [.movie, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await openEditor(with: urls) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }


    // MARK: - Import

    private func openEditor(with urls: [URL]) async {
        await MainActor.run {
            isImporting = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        do {
            // Access the security-scoped URLs (fileImporter on macOS).
            var resolved: [URL] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    resolved.append(url)
                } else {
                    resolved.append(url)
                }
            }
            let timeline = try await TimelineImporter.importingMedia(
                from: resolved,
                canvas: EditorCanvas(width: 720, height: 1280, fps: 30),
                imageDuration: 3,
                productName: "VideoEditorDemoMac"
            )
            await MainActor.run {
                editorStore = EditorStore(timeline: timeline, videoURL: nil)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#endif
