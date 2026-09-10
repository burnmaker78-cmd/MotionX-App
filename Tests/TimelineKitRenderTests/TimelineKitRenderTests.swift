import XCTest
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import TimelineKitCore
@testable import TimelineKitRender

/// macOS smoke tests for TimelineKitRender.
///
/// Verifies that the types previously gated behind `#if canImport(UIKit)`
/// (TimelineRenderer, TextLayerComposer, TimelineClock, ...) exist and function
/// on macOS — the whole point of the macOS support milestone.
@MainActor
final class TimelineKitRenderTests: XCTestCase {

    // MARK: - Helpers

    /// Writes a solid-color PNG to a temp file and returns its URL.
    private func makeTestImageURL(
        width: Int = 64,
        height: Int = 64,
        red: CGFloat = 0.9,
        green: CGFloat = 0.2,
        blue: CGFloat = 0.1
    ) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            throw NSError(domain: "test", code: 1)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tlk_test_\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "test", code: 2)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: 3)
        }
        return url
    }

    /// A timeline with one image segment on the main track and one text segment
    /// on a text track — exercises ImageLayerComposer + TextLayerComposer.
    private func makeTimeline(imageURL: URL) -> EditorTimeline {
        let canvas = EditorCanvas(width: 64, height: 64, fps: 30)

        let imageAssetID = UUID()
        let imageSegmentID = UUID()
        let imageAsset = EditorAsset(
            id: imageAssetID,
            type: .image,
            localURL: imageURL,
            nativeDuration: nil,
            naturalWidth: 64,
            naturalHeight: 64
        )
        let imageSegment = EditorSegment(
            id: imageSegmentID,
            materialID: imageAssetID,
            sourceRange: nil,
            targetRange: TimeRange(start: 0, duration: 2),
            content: .image(SegmentContent.ImageContent())
        )
        let mainTrack = EditorTrack(
            id: UUID(),
            kind: .video,
            label: "main",
            zPosition: 0,
            segments: [imageSegment],
            isMainTrack: true
        )

        let textSegmentID = UUID()
        let textSegment = EditorSegment(
            id: textSegmentID,
            materialID: UUID(),
            sourceRange: nil,
            targetRange: TimeRange(start: 0, duration: 2),
            content: .text(SegmentContent.TextContent(
                text: "Hello macOS",
                style: TextStyle(fontSize: 16, color: "#FFFFFF")
            ))
        )
        let textTrack = EditorTrack(
            id: UUID(),
            kind: .text,
            label: "text",
            zPosition: 10,
            segments: [textSegment]
        )

        var materials = MaterialsPool()
        materials.add(imageAsset)

        return EditorTimeline(
            canvas: canvas,
            tracks: [mainTrack, textTrack],
            materials: materials
        )
    }

    /// Asserts a CVPixelBuffer is not entirely black (i.e. actually rendered).
    private func assertNotBlack(_ buffer: CVPixelBuffer, file: StaticString = #filePath, line: UInt = #line) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            XCTFail("nil base address", file: file, line: line)
            return
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var nonBlack = 0
        // Sample every 4th row/col to keep the test fast.
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let i = y * bytesPerRow + x * 4
                let b = ptr[i]
                let g = ptr[i + 1]
                let r = ptr[i + 2]
                if r > 40 || g > 40 || b > 40 { nonBlack += 1 }
            }
        }
        XCTAssertGreaterThan(nonBlack, 0, "frame is entirely black", file: file, line: line)
    }

    // MARK: - TimelineRenderer

    func testRendererRendersImageAndTextFrame() throws {
        let imageURL = try makeTestImageURL()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let timeline = makeTimeline(imageURL: imageURL)
        let renderer = TimelineRenderer()
        renderer.update(timeline: timeline, canvasSize: CGSize(width: 64, height: 64))

        guard let buffer = renderer.renderFrame(at: 0.5) else {
            XCTFail("renderFrame returned nil on macOS")
            return
        }
        assertNotBlack(buffer)
    }

    // MARK: - TimelineClock

    func testClockFiresOnTickAndStops() async {
        let clock = TimelineClock()
        let expectation = expectation(description: "onTick fires")

        var tickCount = 0
        clock.onTick = {
            tickCount += 1
            if tickCount >= 2 { expectation.fulfill() }
        }

        clock.start()
        await fulfillment(of: [expectation], timeout: 2.0)
        clock.stop()

        let countAfterStop = tickCount
        // Give the (now-invalidated) timer a moment — count must not grow.
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(tickCount, countAfterStop, "onTick kept firing after stop()")
    }

    // MARK: - ImageLayerComposer orientation

    /// 写一张带 EXIF orientation 的 JPEG（模拟 iPhone 竖拍：像素横 + orientation=6）。
    private func makeJPEG(width: Int, height: Int, orientation: UInt32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ilc-orient-\(UUID().uuidString).jpg")
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 竖拍照片（像素横 4032×3024 + orientation=6）经 ImageLayerComposer 后
    /// extent 应为竖屏（高 > 宽）——EXIF orientation 已应用。
    func testImageLayerComposerAppliesEXIFOrientation() throws {
        let url = try makeJPEG(width: 4032, height: 3024, orientation: 6)
        // contain 模式不裁剪到画布，结果 extent 保持图片显示比例 → 可断言方向。
        let spec = ImageLayerSpec(
            imageURL: url,
            renderSize: CGSize(width: 1080, height: 1080),
            contentMode: .contain,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600))
        )
        let out = ImageLayerComposer.evaluate(spec: spec, at: CMTime(seconds: 1, preferredTimescale: 600))
        XCTAssertNotNil(out)
        guard let out else { return }
        XCTAssertGreaterThan(out.extent.height, out.extent.width,
                             "EXIF-rotated portrait photo should render with portrait extent (orientation applied)")
    }

    /// 对照：orientation=1（横拍）→ extent 横屏（宽 > 高）。
    func testImageLayerComposerKeepsLandscapeOrientation() throws {
        let url = try makeJPEG(width: 4032, height: 3024, orientation: 1)
        let spec = ImageLayerSpec(
            imageURL: url,
            renderSize: CGSize(width: 1080, height: 1080),
            contentMode: .contain,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600))
        )
        let out = ImageLayerComposer.evaluate(spec: spec, at: CMTime(seconds: 1, preferredTimescale: 600))
        XCTAssertNotNil(out)
        guard let out else { return }
        XCTAssertGreaterThan(out.extent.width, out.extent.height,
                             "landscape photo should render with landscape extent")
    }

    // MARK: - Video preferredTransform coordinate conversion

    /// 竖拍视频（自然 1920×1080 + AVFoundation orientation-6 风格 transform）经
    /// 坐标系转换后，应把自然横屏矩形映射为竖屏显示矩形（宽 1080 / 高 1920），
    /// 且不引入上下颠倒（转换 ≠ 原矩阵）。
    func testVideoDisplayTransformConvertsToCIImageCoordinates() {
        // 典型竖拍后置摄像头 transform（AVFoundation 左上原点坐标系）。
        let avTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let converted = videoDisplayTransformForCIImage(avTransform, naturalHeight: 1080)

        // 与直接应用原矩阵不同（原矩阵在 CIImage 左下原点会导致上下颠倒）。
        XCTAssertNotEqual(converted, avTransform, "converted transform must differ from the raw AVFoundation transform")

        // 自然横屏矩形应用转换后 → 竖屏显示矩形。
        let natural = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let display = natural.applying(converted)
        XCTAssertEqual(display.width, 1080, accuracy: 0.001, "display width should be the natural height")
        XCTAssertEqual(display.height, 1920, accuracy: 0.001, "display height should be the natural width")
    }

    /// identity transform（横拍视频）→ 转换后仍为 identity（不改变帧）。
    func testVideoDisplayTransformIdentityPassthrough() {
        XCTAssertEqual(videoDisplayTransformForCIImage(.identity, naturalHeight: 1080), .identity)
    }
}
