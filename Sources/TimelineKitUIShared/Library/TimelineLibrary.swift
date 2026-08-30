import Foundation
import TimelineKitCore

/// TimelineKit 资源库（Library）—— 自研 `.tlkbundle` 目录包。
///
/// FCP 资源库心智模型（对照 `.fcpbundle`）：库 = 媒体库 + 项目。
/// 结构（与用户手建的 timeline.fcpbundle 对齐，但用 JSON 而非私有二进制）：
///
/// ```
/// mylibrary.tlkbundle/
/// ├── CurrentVersion.json        # 库元数据（名称/创建时间/格式版本）
/// ├── Media/                     # 导入媒体的副本（按 assetID 命名，唯一副本）
/// │   └── <assetID>.<ext>
/// ├── Projects/
/// │   └── <projectID>.tlkproj    # 项目（EditorTimeline JSON 持久化）
/// └── Events/
///     └── <eventID>.tlkevent     # 事件元数据（媒体分组，预留）
/// ```
///
/// 关键：媒体文件复制进 `Media/`，时间线素材的 URL 指向库内文件。这样
/// 原始文件不受影响、库可整体迁移、媒体不会因 temporaryDirectory 清理丢失。
public struct TimelineLibrary: Sendable {
    /// 库包目录 URL（.tlkbundle）。
    public let packageURL: URL
    /// 库显示名称。
    public var name: String
    /// 格式版本。
    public let formatVersion: String
    /// 创建时间。
    public let createdAt: Date

    /// 库名（默认取包文件名）。
    public static let defaultFormatVersion = "1.0"

    // MARK: - Key paths

    public var mediaDirectory: URL { packageURL.appendingPathComponent("Media", isDirectory: true) }
    public var projectsDirectory: URL { packageURL.appendingPathComponent("Projects", isDirectory: true) }
    public var eventsDirectory: URL { packageURL.appendingPathComponent("Events", isDirectory: true) }
    public var metadataURL: URL { packageURL.appendingPathComponent("CurrentVersion.json") }

    // MARK: - Create / open

    /// 在指定位置创建一个空资源库包（目录 + Media/Projects/Events + 元数据）。
    /// - Parameter at: 用户选择的包目录（例如 file:///Users/xx/Movies/mylibrary.tlkbundle）
    public static func create(at packageURL: URL, name: String? = nil) throws -> TimelineLibrary {
        let fm = FileManager.default
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let libraryName = name ?? packageURL.deletingPathExtension().lastPathComponent
        let lib = TimelineLibrary(
            packageURL: packageURL,
            name: libraryName,
            formatVersion: defaultFormatVersion,
            createdAt: Date()
        )

        try fm.createDirectory(at: lib.mediaDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.projectsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.eventsDirectory, withIntermediateDirectories: true)
        try lib.saveMetadata()
        return lib
    }

    /// 打开一个已存在的资源库包（校验包结构存在）。
    public static func open(at packageURL: URL) throws -> TimelineLibrary {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: packageURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw TimelineLibraryError.notABundle(packageURL)
        }

        // 读元数据（若缺失则按包名初始化）。
        let name = packageURL.deletingPathExtension().lastPathComponent
        var lib = TimelineLibrary(
            packageURL: packageURL,
            name: name,
            formatVersion: defaultFormatVersion,
            createdAt: Date()
        )
        try lib.loadMetadataIfPresent()
        return lib
    }

    // MARK: - Media import

    /// 把外部媒体复制进库 `Media/`，返回库内 URL。
    ///
    /// - Parameter sourceURL: 外部（可能安全作用域）媒体 URL；函数内持作用域复制，
    ///   复制完成即释放。原始文件不改动。
    /// - Returns: 库内 `Media/<assetID>.<ext>` URL。
    @discardableResult
    public func importMedia(from sourceURL: URL, assetID: UUID = UUID()) throws -> URL {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw TimelineLibraryError.sourceMissing
        }
        let ext = sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension
        let dest = mediaDirectory
            .appendingPathComponent(assetID.uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }

    /// 枚举库内已导入的媒体文件。
    public func listMediaAssets() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    // MARK: - Project persistence

    /// 把 timeline 保存为库内项目（`Projects/<projectID>.tlkproj`）。
    @discardableResult
    public func saveProject(_ timeline: EditorTimeline, projectID: UUID = UUID()) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(timeline)
        let url = projectsDirectory
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("tlkproj")
        try data.write(to: url, options: .atomic)
        return projectID
    }

    /// 加载库内某项目。
    public func loadProject(projectID: UUID) throws -> EditorTimeline {
        let url = projectsDirectory
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("tlkproj")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EditorTimeline.self, from: data)
    }

    /// 枚举库内项目 ID。
    public func listProjectIDs() -> [UUID] {
        (try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }) ?? []
    }

    // MARK: - Metadata

    private func saveMetadata() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let doc = Metadata(name: name, formatVersion: formatVersion, createdAt: createdAt)
        try encoder.encode(doc).write(to: metadataURL, options: .atomic)
    }

    private mutating func loadMetadataIfPresent() throws {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        if let doc = try? JSONDecoder().decode(Metadata.self, from: data) {
            self.name = doc.name
        }
    }

    private struct Metadata: Codable {
        let name: String
        let formatVersion: String
        let createdAt: Date
    }
}

// MARK: - Errors

public enum TimelineLibraryError: Error, LocalizedError {
    case notABundle(URL)
    case sourceMissing

    public var errorDescription: String? {
        switch self {
        case .notABundle(let url): return "\(url.lastPathComponent) 不是有效的资源库"
        case .sourceMissing: return "源素材不存在"
        }
    }
}
