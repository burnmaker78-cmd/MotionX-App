//
//  VideoEditorDemoApp.swift
//  VideoEditorDemo
//
//  Created by xiaoyuan on 2026/7/1.
//

import SwiftUI

@main
struct VideoEditorDemoApp: App {
    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            VideoEditorView()
        }
        #endif
        #if os(macOS)
        WindowGroup {
            VideoEditorHostView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        #endif
    }
}
