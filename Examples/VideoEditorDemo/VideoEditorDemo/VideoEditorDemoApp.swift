//
//  VideoEditorDemoApp.swift
//  VideoEditorDemo
//
//  Created by xiaoyuan on 2026/7/1.
//

import SwiftUI
#if DEBUG && os(iOS)
import DebugSwift
#endif

@main
struct VideoEditorDemoApp: App {
#if DEBUG && os(iOS)
    private let debugSwift = DebugSwift()
#endif
    
    init() {
#if DEBUG && os(iOS)
        debugSwift.setup()
        // debugSwift.setup(disable: [.leaksDetector])
        debugSwift.show()
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            VideoEditorView()
#if os(macOS)
                .frame(minWidth: 1000, minHeight: 700)
#endif
        }
#if os(macOS)
        // unified toolbar：标题 + 工具栏按钮与系统 titlebar 合并为一行
        // （FCP / 剪映 Mac 形态），交通灯、拖拽、全屏由系统处理。
        .windowToolbarStyle(.unified)
#endif
    }
}
