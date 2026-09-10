import XCTest
import Observation
import UniformTypeIdentifiers
import TimelineKitCore
@testable import TimelineKitUIShared

/// Verifies the observation model that the macOS editor shell relies on for
/// timeline refresh: observing `store.document.timeline` (the actual @Observable
/// stored property) must fire when `addVisualSegment` mutates the document.
@MainActor
final class EditorStoreObservationTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private var _value = 0
        private let lock = NSLock()
        var value: Int {
            get { lock.withLock { _value } }
        }
        func increment() { lock.withLock { _value += 1 } }
    }

    func testObservingDocumentTimelineFiresOnAddVisualSegment() {
        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let store = EditorStore(timeline: EditorTimeline(canvas: canvas))
        XCTAssertEqual(store.document.timeline.tracks.count, 0)

        let fired = Counter()
        withObservationTracking {
            _ = store.document.timeline
        } onChange: {
            fired.increment()
        }

        let segID = store.addVisualSegment(
            localURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            nativeDuration: 2
        )

        XCTAssertNotNil(segID, "addVisualSegment should create a segment")
        XCTAssertEqual(store.document.timeline.tracks.count, 1)
        XCTAssertEqual(store.document.timeline.tracks.first?.segments.count, 1)
        XCTAssertGreaterThan(fired.value, 0, "observing document.timeline should fire on mutation")
    }

    func testObservingComputedTimelinePropertyFires() {
        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let store = EditorStore(timeline: EditorTimeline(canvas: canvas))

        let fired = Counter()
        withObservationTracking {
            _ = store.timeline
        } onChange: {
            fired.increment()
        }

        _ = store.addVisualSegment(
            localURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            nativeDuration: 2
        )

        // Computed property forwarding should also fire if the getter reads the
        // observable stored property during tracking.
        XCTAssertGreaterThan(fired.value, 0, "observing computed store.timeline should fire")
    }

    func testInsertVisualSegmentAtSpecificTime() {
        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let store = EditorStore(timeline: EditorTimeline(canvas: canvas))

        // Append one segment to the main track (ends at 2.0).
        _ = store.addVisualSegment(localURL: URL(fileURLWithPath: "/tmp/a.mp4"), nativeDuration: 2)
        // Insert a second at 0.5 — not appended at the end.
        let segID = store.insertVisualSegment(
            localURL: URL(fileURLWithPath: "/tmp/b.mp4"),
            nativeDuration: 1,
            at: 0.5
        )

        XCTAssertNotNil(segID, "insert should create a segment")
        let main = store.timeline.mainTrack
        XCTAssertEqual(main?.segments.count, 2, "insert adds a second segment")
        // The inserted segment is placed at 0.5, not appended after 2.0.
        let inserted = store.timeline.segment(id: segID!)
        XCTAssertEqual(inserted?.targetRange.start ?? -1, 0.5, accuracy: 0.001)
    }

    // MARK: - Smart Canvas (first-clip sizing)

    /// 生成一张真实 JPEG（CoreGraphics 绘制 → CGImageDestination 写出）。
    private func makeJPEG(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-canvas-\(UUID().uuidString).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 直接验证 readMediaDimensions 对 JPEG 的返回值（定位智能画布失败环节）。
    func testReadMediaDimensionsForJPEG() async throws {
        let image = try makeJPEG(width: 640, height: 360)
        let dims = await EditorStore.readMediaDimensions(url: image)
        print("[Diag] readMediaDimensions =", dims as Any)
        XCTAssertNotNil(dims, "readMediaDimensions should succeed for JPEG")
        XCTAssertEqual(dims?.width, 640)
        XCTAssertEqual(dims?.height, 360)
    }

    /// 首个视觉片段定型画布：空 timeline 加 640x360 图片 → 画布变为 640x360；
    /// 已定型后再加片段 → 画布不再变化。
    func testFirstClipAdjustsCanvasThenLocks() async throws {
        let store = EditorStore(timeline: EditorTimeline(canvas: EditorCanvas(width: 1920, height: 1080, fps: 30)))
        let image1 = try makeJPEG(width: 640, height: 360)

        _ = store.addVisualSegment(localURL: image1, nativeDuration: nil)

        // 轮询等待异步画布调整（最多 ~2s）。
        for _ in 0..<100 {
            if store.timeline.canvas.width == 640 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.timeline.canvas.width, 640, "canvas should match first clip width")
        XCTAssertEqual(store.timeline.canvas.height, 360, "canvas should match first clip height")

        // 已定型：第二个不同尺寸的片段不再改变画布。
        let image2 = try makeJPEG(width: 1080, height: 1080)
        _ = store.addVisualSegment(localURL: image2, nativeDuration: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.timeline.canvas.width, 640, "canvas should stay locked after first clip")
        XCTAssertEqual(store.timeline.canvas.height, 360, "canvas should stay locked after first clip")
    }

    /// 竖屏图片（无 EXIF 旋转）→ 竖屏画布。
    func testPortraitFirstClipGivesPortraitCanvas() async throws {
        let store = EditorStore(timeline: EditorTimeline(canvas: EditorCanvas(width: 1920, height: 1080, fps: 30)))
        let portrait = try makeJPEG(width: 720, height: 1280)

        _ = store.addVisualSegment(localURL: portrait, nativeDuration: nil)

        for _ in 0..<100 {
            if store.timeline.canvas.width == 720 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.timeline.canvas.width, 720)
        XCTAssertEqual(store.timeline.canvas.height, 1280)
    }

    /// 生成带 EXIF orientation 的 JPEG（模拟 iPhone 竖拍：像素横 + orientation=6）。
    private func makeJPEGWithOrientation(width: Int, height: Int, orientation: UInt32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif-\(UUID().uuidString).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 竖拍照片（像素横 4032x3024 + orientation=6）→ 画布应为竖屏 3024x4032。
    func testPortraitPhotoWithEXIFOrientationGivesPortraitCanvas() async throws {
        let photo = try makeJPEGWithOrientation(width: 4032, height: 3024, orientation: 6)

        // 尺寸读取：应交换宽高（orientation 6 = 顺时针 90°）。
        let dims = await EditorStore.readMediaDimensions(url: photo)
        XCTAssertEqual(dims?.width, 3024, "portrait photo with orientation 6 should report portrait width")
        XCTAssertEqual(dims?.height, 4032, "portrait photo with orientation 6 should report portrait height")

        // 画布定型：应为竖屏。
        let store = EditorStore(timeline: EditorTimeline(canvas: EditorCanvas(width: 1920, height: 1080, fps: 30)))
        _ = store.addVisualSegment(localURL: photo, nativeDuration: nil)
        for _ in 0..<100 {
            if store.timeline.canvas.width == 3024 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.timeline.canvas.width, 3024, "canvas should be portrait for a portrait photo")
        XCTAssertEqual(store.timeline.canvas.height, 4032, "canvas should be portrait for a portrait photo")
    }

    /// 横拍照片（无 orientation 旋转）→ 画布为横屏（宽高不交换）。
    func testLandscapePhotoGivesLandscapeCanvas() async throws {
        let photo = try makeJPEGWithOrientation(width: 4032, height: 3024, orientation: 1)
        let dims = await EditorStore.readMediaDimensions(url: photo)
        XCTAssertEqual(dims?.width, 4032)
        XCTAssertEqual(dims?.height, 3024)
    }
}
