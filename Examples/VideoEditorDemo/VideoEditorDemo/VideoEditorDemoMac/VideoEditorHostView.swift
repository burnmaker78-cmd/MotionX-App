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
struct VideoEditorHostView: View {
    @State private var editorStore: EditorStore?
    @State private var isImporting = false
    @State private var isShowingPicker = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let editorStore {
                ClipEditorView(store: editorStore) { _, _ in
                    // Draft already saved inside ClipEditorView; keep hook for future.
                }
            } else {
                landingView
            }
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

    // MARK: - Landing

    private var landingView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.blue)

            Text("TimelineKit Demo (macOS)")
                .font(.title2.bold())

            Text("Choose media files to create an editable timeline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isShowingPicker = true
            } label: {
                Label(isImporting ? "Importing..." : "Choose Media", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isImporting)

            if isImporting {
                ProgressView()
                    .controlSize(.large)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
