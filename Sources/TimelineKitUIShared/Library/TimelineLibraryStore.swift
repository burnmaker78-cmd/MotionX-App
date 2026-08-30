import Foundation
import Observation
import TimelineKitCore

/// 当前打开的 `.tlkbundle` 资源库状态容器。
///
/// 职责：持有当前库、库内媒体清单，提供创建/打开库、导入媒体进库、
/// 项目保存。是对 `TimelineLibrary` 的 @Observable 包装，供 UI（Browser 面板）
/// 订阅变化。
@MainActor @Observable
public final class TimelineLibraryStore {

    /// 当前打开的库；nil = 未打开（空态显示"创建资源库"）。
    public private(set) var library: TimelineLibrary?
    /// 当前库内媒体文件清单（刷新后更新）。
    public private(set) var mediaURLs: [URL] = []
    /// 最近一次操作的错误信息（用于弹窗）。
    public var errorMessage: String?

    public init() {}

    /// 是否已打开库。
    public var hasLibrary: Bool { library != nil }

    // MARK: - Create / open

    /// 在指定位置创建库并设为当前库。
    public func createLibrary(at packageURL: URL, name: String? = nil) throws {
        let lib = try TimelineLibrary.create(at: packageURL, name: name)
        self.library = lib
        refreshMedia()
    }

    /// 打开现有库。
    public func openLibrary(at packageURL: URL) throws {
        let lib = try TimelineLibrary.open(at: packageURL)
        self.library = lib
        refreshMedia()
    }

    // MARK: - Media

    /// 把外部媒体导入当前库（复制进 `Media/`），刷新媒体清单。
    /// - Returns: 库内媒体 URL；无库或复制失败返回 nil 并设 errorMessage。
    @discardableResult
    public func addMedia(urls: [URL]) -> [URL] {
        guard let library else {
            errorMessage = "请先创建或打开资源库"
            return []
        }
        var imported: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                imported.append(try library.importMedia(from: url))
            } catch {
                errorMessage = "导入失败：\(url.lastPathComponent) — \(error.localizedDescription)"
            }
        }
        if !imported.isEmpty { refreshMedia() }
        return imported
    }

    /// 重新枚举库内媒体。
    public func refreshMedia() {
        mediaURLs = library?.listMediaAssets() ?? []
    }

    // MARK: - Project

    /// 把 timeline 保存为库内项目。
    @discardableResult
    public func saveProject(_ timeline: EditorTimeline) throws -> UUID {
        guard let library else { throw TimelineLibraryError.notABundle(URL(fileURLWithPath: "")) }
        return try library.saveProject(timeline)
    }

    /// 加载库内项目。
    public func loadProject(projectID: UUID) throws -> EditorTimeline {
        guard let library else { throw TimelineLibraryError.notABundle(URL(fileURLWithPath: "")) }
        return try library.loadProject(projectID: projectID)
    }

    /// 当前库内所有项目 ID。
    public func projectIDs() -> [UUID] {
        library?.listProjectIDs() ?? []
    }
}
