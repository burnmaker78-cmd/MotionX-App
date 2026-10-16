
//
//  VideoEditorView.swift
//  MotionX
//

#if os(iOS)
import SwiftUI
import TimelineKitUIShared
import TimelineKitUIiOS

/// MotionX's main entry point.
/// Opens or creates the default project library, then displays the project browser.
struct VideoEditorView: View {
    @State private var libraryStore = TimelineLibraryStore()
    @State private var showOpenLibraryError = false
    @State private var openLibraryError: Error?

    var body: some View {
        NavigationStack {
            ProjectBrowserView(libraryStore: libraryStore)
                .task {
                    openLibrary()
                }
                .alert(
                    "Unable to Open Library",
                    isPresented: $showOpenLibraryError
                ) {
                    Button("Recreate Library", role: .destructive) {
                        let url = defaultLibraryURL

                        do {
                            if FileManager.default.fileExists(
                                atPath: url.path
                            ) {
                                try FileManager.default.removeItem(at: url)
                            }

                            try libraryStore.createLibrary(at: url)
                            openLibraryError = nil
                        } catch {
                            openLibraryError = error
                        }
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "The project library may be damaged. " +
                        "Recreating it may delete existing projects. " +
                        "Cancel if you want to keep your current data."
                    )
                }
        }
    }

    private func openLibrary() {
        let url = defaultLibraryURL

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try libraryStore.openLibrary(at: url)
            } else {
                try libraryStore.createLibrary(at: url)
            }
        } catch {
            openLibraryError = error
            showOpenLibraryError = true
        }
    }

    private var defaultLibraryURL: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        // Keep the existing filename so existing projects can be found.
        return documents.appendingPathComponent("默认资源库.tlkbundle")
    }
}

#endif

#Preview {
    if #available(iOS 18.0, *) {
        VideoEditorView()
    } else {
        Text("MotionX requires iOS 18 or later.")
    }
}
