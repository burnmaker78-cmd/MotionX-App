//
//  BaseFlippedView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import AppKit

class BaseFlippedView: NSView {
    // 强制把坐标系原点改为左上角，与 UIKit 行为完全一致
    // 将 macOS 坐标系翻转为与 iOS 一致（原点在左上角），
    // 保证 draw(_:) 内的算法与 iOS 100% 相同。
    override var isFlipped: Bool {
        return true
    }
}
