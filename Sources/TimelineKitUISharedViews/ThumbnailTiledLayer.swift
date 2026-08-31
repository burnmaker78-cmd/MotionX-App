//
//  ThumbnailTiledLayer.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import os
import TimelineKitCore
import TimelineKitRender

/// CATiledLayer 后备实现。绘制在后台线程，状态读写通过 OSAllocatedUnfairLock 同步。
/// 单个「逻辑 tile」= 一个 44pt 宽的缩略图；CATiledLayer 内部按 256×256 像素分块
/// 调用 draw(in:)，每次绘一片可能包含多个逻辑 tile。
/// Sendable: 所有可变状态都被 stateLock / NSCache（自身线程安全）保护。
package final class ThumbnailTiledLayer: CATiledLayer, @unchecked Sendable {

    /// 关闭 tile 淡入动画，避免缩放时缩略图渐现产生的闪烁。
    package override class func fadeDuration() -> CFTimeInterval { 0 }

    // 单个缩略图 tile 在 layer 点坐标系下的宽度。configure 时由 ThumbnailStripView 注入。
    private struct State {
        var url: URL?
        var segment: EditorSegment?
        var isImageAsset: Bool = false
        var thumbTilePoints: CGFloat = 44
        /// configure 调用计数，用于丢弃跨 segment 的过时异步加载结果。
        var generation: UInt64 = 0
    }

    // Swift 6 async-safe scoped locking. CATiledLayer.draw(in:) is called on a background
    // queue; configure() writes from main. NSLock is forbidden in async context.
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// 本地同步缓存：tile 索引 → UIImage。NSCache 自身线程安全。
    /// configure 切换或 purge 通知时清空。
    private let tileImageCache = NSCache<NSNumber, TlkImage>()

    package override init() {
        super.init()
        #if os(iOS)
        contentsScale = UIScreen.main.scale
        #endif
        // 256×256 像素是 CATiledLayer 推荐尺寸；levelsOfDetail=1 表示无多级 LOD。
        tileSize = CGSize(width: 256, height: 256)
        levelsOfDetail = 1
        levelsOfDetailBias = 0
        tileImageCache.countLimit = 256
    }

    package override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// 由 ThumbnailStripView 调用（主线程）。完整切换 asset/segment 上下文。
    package func configure(asset: EditorAsset?, segment: EditorSegment?, tileWidthPoints: CGFloat) {
        stateLock.withLock { state in
            state.url = asset?.bestURL
            state.segment = segment
            if let asset, case .image = asset.type {
                state.isImageAsset = true
            } else {
                state.isImageAsset = false
            }
            state.thumbTilePoints = tileWidthPoints
            state.generation &+= 1
        }
        tileImageCache.removeAllObjects()
        setNeedsDisplay()
    }

    /// purge 通知时调用：清本地 cache + 重绘。底层 ThumbnailProvider.cache 已被外部 purge。
    package func purgeLocalCache() {
        tileImageCache.removeAllObjects()
        setNeedsDisplay()
    }

    // MARK: - Drawing (background thread)

    package override func draw(in ctx: CGContext) {
        let snapshot = stateLock.withLock { $0 }
        let url = snapshot.url
        let segment = snapshot.segment
        let isImage = snapshot.isImageAsset
        let tileW = snapshot.thumbTilePoints
        let myGen = snapshot.generation

        guard let url, let segment, tileW > 0 else { return }

        let clipRect = ctx.boundingBoxOfClipPath
        let h = bounds.height
        let totalW = bounds.width
        let totalTiles = max(1, Int(ceil(totalW / tileW)))
        // CoreAnimation may request drawing for a clipRect entirely beyond the bounds
        // (e.g. during rubber-band overscroll or zoom). Clamp firstIndex to totalTiles
        // so the range firstIndex..<lastIndex is never invalid.
        let firstIndex = min(max(0, Int(floor(clipRect.minX / tileW))), totalTiles)
        let lastIndex  = min(totalTiles, max(0, Int(ceil(clipRect.maxX / tileW))))
        guard firstIndex < lastIndex else { return }
        let srcStart = segment.sourceRange?.start    ?? 0
        let srcDur   = segment.sourceRange?.duration ?? segment.targetRange.duration

        // Request enough pixels for the actual tile aspect. AVAssetImageGenerator
        // preserves source aspect, so final drawing still center-crops below.
        let pixelSize = CGSize(
            width: max(tileW * contentsScale, 88),
            height: max(h * contentsScale, 88)
        )
        
        for i in firstIndex..<lastIndex {
            let key = i as NSNumber
            let tileRect = CGRect(x: CGFloat(i) * tileW, y: 0, width: tileW, height: h)
            let img = TlkImage(data: Data())

            if let img = tileImageCache.object(forKey: key), let cg = img.cgImage {
                // ctx 来自 CATiledLayer，坐标系 origin 在左下；翻转 y 后再 draw。
                // Draw with aspect-fill instead of stretching the frame into the
                // tile. This keeps landscape/portrait video and photo thumbnails
                // visually natural at any track height.
                let drawBounds = CGRect(x: tileRect.minX, y: 0,
                                        width: tileRect.width, height: tileRect.height)
                let imageSize = CGSize(width: cg.width, height: cg.height)
                let drawRect = Self.aspectFillRect(for: imageSize, in: drawBounds)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: tileRect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.clip(to: drawBounds)
                ctx.draw(cg, in: drawRect)
                ctx.restoreGState()
            } else {
                // Cache miss：异步请求 + 完成后 setNeedsDisplay(局部 tile)。
                let t: Double = isImage ? 0 :
                    (totalTiles > 1
                        ? srcStart + Double(i) / Double(totalTiles - 1) * srcDur
                        : srcStart)
                Self.fetchTile(layer: self, url: url, isImage: isImage,
                               time: t, size: pixelSize, tileIndex: i,
                               tileRect: tileRect, expectedGeneration: myGen)
            }
        }
    }

    private static func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    /// Sendable 包装，让 Swift 6 strict concurrency 信任 weak 引用穿越 isolation boundary。
    /// CATiledLayer 自身已声明 @unchecked Sendable，本 wrapper 仅是显式 Sendable 标记。
    private struct WeakRef: @unchecked Sendable {
        weak var value: ThumbnailTiledLayer?
    }

    /// 静态调度，避免在 draw(in:) 内捕获 self 闭包触发 Swift 6 `sending` 检查。
    /// 用 WeakRef + Task.detached：WeakRef 是 Sendable，闭包内通过 ref.value 解引用。
    nonisolated private static func fetchTile(
        layer: ThumbnailTiledLayer,
        url: URL,
        isImage: Bool,
        time: Double,
        size: CGSize,
        tileIndex: Int,
        tileRect: CGRect,
        expectedGeneration: UInt64
    ) {
        let ref = WeakRef(value: layer)
        Task.detached {
            let img = await ThumbnailProvider.shared.thumbnail(
                for: url, isImage: isImage, at: time, size: size
            )
            guard let layer = ref.value, let img else { return }
            let curGen = layer.stateLock.withLock { $0.generation }
            guard curGen == expectedGeneration else { return }
#if canImport(UIKit)
            layer.tileImageCache.setObject(TlkImage(cgImage: img), forKey: tileIndex as NSNumber)
#elseif canImport(AppKit)
            layer.tileImageCache.setObject(TlkImage(cgImage: img, size: NSSize(width: size.width, height: size.height)), forKey: tileIndex as NSNumber)
#endif
            await MainActor.run {
                ref.value?.setNeedsDisplay(tileRect)
            }
        }
    }
}

