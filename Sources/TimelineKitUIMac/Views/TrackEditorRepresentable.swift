//
//  TrackEditorRepresentable.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import SwiftUI
import TimelineKitCore
import TimelineKitUIShared

// MARK: - UIKit Bridge

struct TrackEditorRepresentable: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = ClipEditorViewController
    var store: EditorStore
    var libraryStore: TimelineLibraryStore
    var onEmptyTrackAdd: ((UUID, EditorTrack.Kind) -> Void)?
    
    func makeNSViewController(context: Context) -> ClipEditorViewController {
        let vc = ClipEditorViewController(store: store, libraryStore: libraryStore)
        vc.onEmptyTrackAdd = onEmptyTrackAdd
        return vc
    }

    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
        nsViewController.onEmptyTrackAdd = onEmptyTrackAdd
        nsViewController.apply(timeline: store.timeline, selection: store.selection)
    }
}

