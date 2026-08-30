//
//  VideoEditorHostView.swift
//  VideoEditorDemo
//
//  Created by xiaoyuan on 2026/8/29.
//

#if os(macOS)
import SwiftUI
import TimelineKitCore
import TimelineKitUIShared
import TimelineKitUIMac

/// macOS entry: build an empty timeline and host the clip editor.
/// Media import (fileImporter + addMedia) lives inside ClipEditorView.
struct VideoEditorView: View {
    @State private var editorStore: EditorStore

    init(editorStore: EditorStore? = nil) {
        if let editorStore {
            self.editorStore = editorStore
        } else {
            // 空 timeline：场景为空时 importing(from:) 会过滤掉所有空轨道，
            // 导致没有任何 isMainTrack 轨道 → addVisualSegment 无法落位。
            // 显式创建一条主轨，让空项目也有"骨架轨道"可承接素材。
            let timelineSchema = ServerTimelineSchema(version: "v1", duration: 0, fps: 30, canvas: SCanvas(width: 1920, height: 1080), scenes: [])
            var timeline = TimelineImporter.importing(from: timelineSchema)
            if !timeline.tracks.contains(where: { $0.isMainTrack }) {
                timeline.tracks.append(EditorTrack(id: UUID(), kind: .video, label: "视频", zPosition: 0, segments: [], isMainTrack: true))
            }
            self.editorStore = EditorStore(timeline: timeline)
        }
    }

    var body: some View {
        ClipEditorView(store: editorStore) { _, _ in
            // Draft already saved inside ClipEditorView; keep hook for future.
        }
    }
}

#endif

