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
//   - ClipEditorView            — FCP 式四区编辑器壳（工具栏 + Browser/Viewer/
//                                  Inspector + Timeline，NSSplitView 可拖拽分割）
//   - MacEditorShellView        — AppKit 根容器（垂直分割）
//   - MacEditorTopAreaView      — 上部水平三区（Browser | Viewer | Inspector）
//   - MacBrowserPanelView       — 素材区（左资源库侧栏 + 右媒体面板）
//   - MacLibrarySidebarView     — 资源库侧栏（打开/导入/新建项目）
//   - MacMediaPanelView         — 媒体面板（项目分组 + 按拍摄日期分组）
//   - MacInspectorPanelView     — 检查器占位
//   - TrackEditorRepresentable  — 时间线编辑器（移植自 iOS）：ClipEditorViewController
//                                  + TrackCanvasView（轨道/片段/缩略图/修剪/拖放）
//   - Views/                    — 移植的 AppKit 时间线视图（BaseFlippedView 翻转坐标系）
//
// 顶部导航：标题 + 导入/导出按钮由 ClipEditorView 的 .toolbar 挂到系统
// unified titlebar（宿主设置 .windowToolbarStyle(.unified)）。

public let timelineKitUIMacVersion = "8.2.0"
