import Foundation
import SwiftUI
import TimelineKitCore
import TimelineKitRender
import TimelineKitUIShared
import TimelineKitUISharedViews

// MARK: - TimelineKitUIMac
//
// V8：macOS 编辑器壳（M7 正式交付）。
//
// 包含：
//   - ClipEditorView          — 剪映 Mac 风格两区编辑器壳（预览 + AppKit 时间线）
//   - MacTimelineCanvasView   — AppKit 时间线画布（滚动/选中/scrub/缩放）
//   - MacTimelineCanvasHost   — 标签侧栏 + 滚动视图组合，SwiftUI 桥接
//   - MacTrackLabelSidebar    — 轨道标签侧栏（锁定/隐藏/静音开关）

public let timelineKitUIMacVersion = "8.1.0"
