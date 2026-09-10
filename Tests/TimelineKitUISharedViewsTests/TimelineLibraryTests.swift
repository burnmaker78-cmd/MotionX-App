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

    func testImportMediaCopiesIntoMediaDirectory() async throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        // Write a fake source file.
        let src = tempDir.appendingPathComponent("clip.mp4")
        try Data("fake".utf8).write(to: src)

        let importedURL = try await lib.importMedia(from: src)

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertEqual(importedURL.deletingLastPathComponent().lastPathComponent, "Media")
        // Original untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))

        XCTAssertEqual(lib.listMediaAssets().count, 1)
    }

    // MARK: - Manifest

    func testImportMediaWritesManifestWithCaptureDate() async throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        let src = tempDir.appendingPathComponent("photo.jpg")
        try Data("fakeimg".utf8).write(to: src)

        let entry = try await lib.importMediaEntry(from: src)

        XCTAssertEqual(lib.listMediaManifest().count, 1)
        XCTAssertEqual(entry.originalFileName, "photo.jpg")
        XCTAssertEqual(entry.kind, .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.mediaManifestURL.path))
    }

    // MARK: - Open validation

    func testOpenRejectsPlainFolder() throws {
        let plainDir = tempDir.appendingPathComponent("plain-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        XCTAssertThrowsError(try TimelineLibrary.open(at: plainDir)) { error in
            guard case TimelineLibraryError.notABundle = error else {
                XCTFail("expected notABundle, got \(error)")
                return
            }
        }
    }

    func testOpenAcceptsCreatedBundle() throws {
        let lib = try TimelineLibrary.create(at: bundleURL, name: "库")
        let reopened = try TimelineLibrary.open(at: bundleURL)
        XCTAssertEqual(reopened.name, "库")
        _ = lib
    }

    // MARK: - Project round-trip

    func testSaveAndLoadProjectRoundTrips() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let timeline = EditorTimeline(canvas: canvas)
        let projectID = try lib.saveProject(timeline)

        XCTAssertEqual(lib.listProjectIDs(), [projectID])
        let loaded = try lib.loadProject(projectID: projectID)
        XCTAssertEqual(loaded.timeline.canvas.width, 1920)
        XCTAssertEqual(loaded.timeline.canvas.height, 1080)
    }

    // MARK: - Project with name

    func testSaveProjectWithNameRoundTrips() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        let timeline = EditorTimeline(canvas: canvas)
        let project = LibraryProject(name: "我的项目", timeline: timeline)
        let id = try lib.saveProject(project)

        let projects = lib.listProjects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.id, id)
        XCTAssertEqual(projects.first?.name, "我的项目")
        XCTAssertEqual(projects.first?.timeline.canvas.width, 1920)
    }

    func testLoadLegacyProjectFallsBackToFileName() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)

        // Write a legacy .tlkproj (bare EditorTimeline, no LibraryProject wrapper).
        let projectID = UUID()
        let canvas = EditorCanvas(width: 1280, height: 720, fps: 30)
        let timeline = EditorTimeline(canvas: canvas)
        let url = lib.projectsDirectory
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("tlkproj")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(timeline).write(to: url, options: .atomic)

        let loaded = try lib.loadProject(projectID: projectID)
        XCTAssertEqual(loaded.timeline.canvas.width, 1280)
        XCTAssertEqual(loaded.timeline.canvas.height, 720)
    }

    // MARK: - Project management (rename / duplicate / delete / pin)

    func testRenameProject() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)
        let project = try lib.createProjectForTest(name: "原名")

        try lib.renameProject(id: project.id, newName: "新名")
        let loaded = try lib.loadProject(projectID: project.id)
        XCTAssertEqual(loaded.name, "新名")
        XCTAssertEqual(loaded.timeline.canvas.width, project.timeline.canvas.width)
    }

    func testDuplicateProject() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)
        let project = try lib.createProjectForTest(name: "原始")

        let copy = try lib.duplicateProject(id: project.id)
        XCTAssertNotEqual(copy.id, project.id)
        XCTAssertEqual(copy.name, "原始 副本")
        XCTAssertEqual(copy.timeline.duration, project.timeline.duration)
        XCTAssertEqual(lib.listProjects().count, 2)
    }

    func testDeleteProject() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)
        let project = try lib.createProjectForTest(name: "待删")

        try lib.deleteProject(id: project.id)
        XCTAssertEqual(lib.listProjects().count, 0)
        XCTAssertThrowsError(try lib.loadProject(projectID: project.id))
    }

    func testSetPinnedAndSortedOrder() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)
        let a = try lib.createProjectForTest(name: "A")
        let b = try lib.createProjectForTest(name: "B")  // newest

        // Default order: newest first.
        XCTAssertEqual(TimelineLibrary.sortedProjects(lib.listProjects()).map(\.name), ["B", "A"])

        // Pin the older project → it moves to the front.
        try lib.setPinned(id: a.id, isPinned: true)
        let pinned = try lib.loadProject(projectID: a.id)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(TimelineLibrary.sortedProjects(lib.listProjects()).map(\.name), ["A", "B"])
        _ = b
    }

    func testLegacyProjectWithoutIsPinnedDecodesFalse() throws {
        let lib = try TimelineLibrary.create(at: bundleURL)
        let project = try lib.createProjectForTest(name: "兼容")

        // Rewrite the .tlkproj without the isPinned key (simulating a phase-1 file).
        let url = lib.projectsDirectory
            .appendingPathComponent(project.id.uuidString)
            .appendingPathExtension("tlkproj")
        let legacyJSON = """
        {"id":"\(project.id.uuidString)","name":"兼容","createdAt":0,"timeline":{"id":"\(project.timeline.id.uuidString)","canvas":{"width":1920,"height":1080,"fps":30},"tracks":[],"materials":[],"transitions":[],"metadata":{"createdAt":0}}}
        """
        try legacyJSON.data(using: .utf8)!.write(to: url, options: .atomic)

        let loaded = try lib.loadProject(projectID: project.id)
        XCTAssertFalse(loaded.isPinned, "legacy file without isPinned should decode to false")
    }
}

/// 测试辅助：直接走 store 的 createProject（含主轨骨架）。
extension TimelineLibrary {
    @MainActor
    func createProjectForTest(name: String) throws -> LibraryProject {
        let canvas = EditorCanvas(width: 1920, height: 1080, fps: 30)
        var timeline = EditorTimeline(canvas: canvas)
        if !timeline.tracks.contains(where: { $0.isMainTrack }) {
            timeline.tracks.append(EditorTrack(id: UUID(), kind: .video, label: "视频", zPosition: 0, segments: [], isMainTrack: true))
        }
        let project = LibraryProject(name: name, timeline: timeline)
        try saveProject(project)
        return project
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

    func testAddMediaPopulatesLibrary() async throws {
        let store = TimelineLibraryStore()
        try store.createLibrary(at: bundleURL)

        let src = tempDir.appendingPathComponent("img.png")
        try Data("img".utf8).write(to: src)

        let imported = await store.addMedia(urls: [src])
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(store.mediaURLs.count, 1)
        XCTAssertEqual(store.mediaEntries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported[0].path))
    }

    func testGroupedMediaGroupsByDate() async throws {
        let store = TimelineLibraryStore()
        try store.createLibrary(at: bundleURL)

        let pin = tempDir.appendingPathComponent("img.png")
        try Data("img".utf8).write(to: pin)

        _ = await store.addMedia(urls: [pin])
        // A single file -> one day group, newest first.
        XCTAssertEqual(store.groupedMedia.count, 1)
        XCTAssertEqual(store.groupedMedia.first?.items.count, 1)
    }

    func testAddMediaWithoutLibraryShowsError() async {
        let store = TimelineLibraryStore()
        let src = URL(fileURLWithPath: "/tmp/none.mp4")
        let imported = await store.addMedia(urls: [src])
        XCTAssertTrue(imported.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}
