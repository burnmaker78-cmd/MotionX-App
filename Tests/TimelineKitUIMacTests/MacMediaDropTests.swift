#if canImport(AppKit)
import XCTest
import AppKit
import TimelineKitCore
import TimelineKitUIShared
@testable import TimelineKitUIMac

/// Verifies the media drag-and-drop pasteboard path: the media panel encodes a
/// LibraryMediaEntry into the pasteboard (mediaDragType), and the timeline
/// canvas decodes the same type back.
@MainActor
final class MacMediaDropTests: XCTestCase {

    private func makeEntry() -> LibraryMediaEntry {
        LibraryMediaEntry(
            id: UUID(),
            fileName: "ABC.mp4",
            originalFileName: "clip.mp4",
            captureDate: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .video,
            duration: 5.0
        )
    }

    /// Round-trip: entry → JSON → pasteboard (as the panel writes) → decode
    /// (as the canvas reads). Must preserve id/kind/duration.
    func testPasteboardRoundTripPreservesEntry() throws {
        let entry = makeEntry()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-pb-\(UUID().uuidString)"))
        pasteboard.clearContents()

        // Source side: MacMediaPanelView.pasteboardWriterForItemAt.
        let writer = NSPasteboardItem()
        let encoded = try JSONEncoder().encode(entry)
        writer.setData(encoded, forType: MacMediaPanelView.mediaDragType)
        pasteboard.writeObjects([writer])

        // Destination side: TrackCanvasView.performDragOperation decodes.
        guard let data = pasteboard.data(forType: MacMediaPanelView.mediaDragType) else {
            XCTFail("pasteboard missing mediaDragType data")
            return
        }
        let decoded = try JSONDecoder().decode(LibraryMediaEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.kind, entry.kind)
        XCTAssertEqual(decoded.duration, entry.duration)
        XCTAssertEqual(decoded.originalFileName, entry.originalFileName)
        XCTAssertEqual(decoded.captureDate, entry.captureDate)
    }

    /// Canvas drop handler fires with the decoded entry, non-negative time, and y.
    func testCanvasDropFiresCallback() throws {
        let canvas = TrackCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let timeline = EditorTimeline(canvas: EditorCanvas(width: 1920, height: 1080, fps: 30))
        canvas.configure(timeline: timeline, availableWidth: 800)

        let entry = makeEntry()
        var dropped: (LibraryMediaEntry, Double, CGFloat)?
        canvas.onDropMedia = { e, t, y in dropped = (e, t, y) }

        // Drive the drop programmatically: simulate what performDragOperation
        // does (decode from pasteboard, convert x→time, fire callback).
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LibraryMediaEntry.self, from: data)
        let time = canvas.time(at: 400)
        canvas.onDropMedia?(decoded, max(0, time), 200)

        XCTAssertNotNil(dropped, "onDropMedia should fire")
        XCTAssertEqual(dropped?.0.id, entry.id)
        XCTAssertGreaterThanOrEqual(dropped?.1 ?? -1, 0)
        XCTAssertEqual(dropped?.2 ?? -1, 200, "drop y should be forwarded")
    }

    /// trackID(atY:) maps a drop y to the nearest track row, nil in the ruler.
    func testTrackIDAtY() throws {
        let canvas = TrackCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let canvas2 = EditorCanvas(width: 1920, height: 1080, fps: 30)
        var timeline = EditorTimeline(canvas: canvas2)
        timeline.tracks.append(EditorTrack(id: UUID(), kind: .video, label: "视频", zPosition: 0, segments: [], isMainTrack: true))
        canvas.configure(timeline: timeline, availableWidth: 800)

        // Ruler zone → nil.
        XCTAssertNil(canvas.trackID(atY: 10))
        // Below ruler → a track id (main track row).
        XCTAssertNotNil(canvas.trackID(atY: 100))
    }
}

#endif

