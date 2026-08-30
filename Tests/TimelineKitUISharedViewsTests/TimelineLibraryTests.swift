import XCTest
import Foundation
import TimelineKitCore
import TimelineKitUIShared

/// Tests for the .tlkbundle resource-library model and its @Observable store.
@MainActor
final class TimelineLibraryTests: XCTestCase {

    private var tempDir: URL!
    private var bundleURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tlk-lib-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bundleURL = tempDir.appendingPathComponent("test.tlkbundle")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Create / structure

    func testCreateBuildsBundleStructure() throws {
        let lib = try TimelineLibrary.create(at: bundleURL, name: "我的库")

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.mediaDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.projectsDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.eventsDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.metadataURL.path))
        XCTAssertEqual(lib.name, "我的库")
    }

    // MARK: - importMedia

    func testImportMediaCopiesIntoMediaDirectory() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        // Write a fake source file.
        let src = tempDir.appendingPathComponent("clip.mp4")
        try Data("fake".utf8).write(to: src)

        let importedURL = try lib.importMedia(from: src)

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertEqual(importedURL.deletingLastPathComponent().lastPathComponent, "Media")
        // Original untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))

        XCTAssertEqual(lib.listMediaAssets().count, 1)
    }

    // MARK: - Project round-trip

    func testSaveAndLoadProjectRoundTrips() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let timeline = EditorTimeline(canvas: canvas)
        let projectID = try lib.saveProject(timeline)

        XCTAssertEqual(lib.listProjectIDs(), [projectID])
        let loaded = try lib.loadProject(projectID: projectID)
        XCTAssertEqual(loaded.canvas.width, 1920)
        XCTAssertEqual(loaded.canvas.height, 1080)
    }
}

/// Tests for the @Observable store wrapper (create/open/addMedia).
@MainActor
final class TimelineLibraryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var bundleURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tlk-store-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bundleURL = tempDir.appendingPathComponent("store.tlkbundle")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateLibrarySetsState() throws {
        let store = TimelineLibraryStore()
        try store.createLibrary(at: bundleURL)
        XCTAssertTrue(store.hasLibrary)
        XCTAssertEqual(store.library?.name, "store")
        XCTAssertTrue(store.mediaURLs.isEmpty)
    }

    func testAddMediaPopulatesLibrary() throws {
        let store = TimelineLibraryStore()
        try store.createLibrary(at: bundleURL)

        let src = tempDir.appendingPathComponent("img.png")
        try Data("img".utf8).write(to: src)

        let imported = store.addMedia(urls: [src])
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(store.mediaURLs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported[0].path))
    }

    func testAddMediaWithoutLibraryShowsError() {
        let store = TimelineLibraryStore()
        let src = URL(fileURLWithPath: "/tmp/none.mp4")
        let imported = store.addMedia(urls: [src])
        XCTAssertTrue(imported.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}
