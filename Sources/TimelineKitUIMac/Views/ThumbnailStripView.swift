//
//  ThumbnailStripView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import AppKit
import TimelineKitCore
import TimelineKitUISharedViews

// MARK: - ThumbnailStripView

/// V5.1 BUG 3: 改为 CATiledLayer 驱动的按需渲染，支持超长素材（>16384pt）。
/// 旧实现给整个 segment 宽度预创建 N 个 UIImageView 子视图，1000 秒视频在 minPPS=20
/// 下产生 ~450 个 UIImageView，超过 CALayer 单图层栅格化上限，导致 ScrollView 坐标
/// 异常、Pinch 手势失效。CATiledLayer 只渲染当前可见 tile，子视图数始终为 0。
///
/// API 保持兼容：`load(asset:segment:)` / `cancelLoading()` 调用点不变。
final class ThumbnailStripView: BaseFlippedView {

    private static let thumbTileWidth: CGFloat = 44  // pt; matches blockH ≈ 40pt

    // 必须重写 makeBackingLayer 并配对 wantsLayer
    override func makeBackingLayer() -> CALayer { ThumbnailTiledLayer() }
    
    private var tiled: ThumbnailTiledLayer {
        guard let tiledLayer = layer as? ThumbnailTiledLayer else {
            fatalError("Layer must be ThumbnailTiledLayer")
        }
        return tiledLayer
    }
  
    // V5.1 BUG 4: 保存最近一次 load 的入参，用于 thumbnailProviderDidPurge 后主动恢复。
    private var lastAsset: EditorAsset?
    private var lastSegment: EditorSegment?
    // Swift 6 strict concurrency: NSObjectProtocol is not Sendable, but the observer
    // is only assigned on MainActor (init) and read in nonisolated deinit. Mirror the
    // pattern used by CompositionCoordinator / FullScreenPreviewController.
    nonisolated(unsafe) private var purgeObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // CATiledLayer 自动用其内置队列异步绘制；不在 main 排队 layout，避免阻塞。
        // 用 NSScreen 替换 UIScreen 获取 Retina 缩放倍率
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        tiled.contentsScale = scale
        purgeObserver = NotificationCenter.default.addObserver(
            forName: .thumbnailProviderDidPurge,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.tiled.purgeLocalCache()
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        if let purgeObserver {
            NotificationCenter.default.removeObserver(purgeObserver)
        }
    }

    private var lastBoundsWidth: CGFloat = 0
    
    // 当 View 移入窗口时，同步屏幕缩放倍率（处理外接显示器/跨屏拖拽）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            tiled.contentsScale = window.backingScaleFactor
        }
    }

    override func layout() {
        super.layout()
        // bounds 变化时（trim / zoom）：tile 索引含义会变（index→时间戳的映射依赖 totalTiles
        // = ceil(bounds.width/tileW)），必须先清本地 cache 再 invalidate 重绘，否则
        if abs(bounds.width - lastBoundsWidth) > 0.5 {
            lastBoundsWidth = bounds.width
            tiled.purgeLocalCache()
            tiled.setNeedsDisplay() // 仅在尺寸变更清 Cache 时重新绘制 TiledLayer
        }
    }

    // MARK: - Load (compat API)

    func load(asset: EditorAsset?, segment: EditorSegment) {
        lastAsset = asset
        lastSegment = segment
        tiled.configure(asset: asset, segment: segment, tileWidthPoints: Self.thumbTileWidth)
    }

    func cancelLoading() {
        // CATiledLayer 自身按需绘制，无显式 Task 列表需要取消；调用点保留兼容。
    }
}
