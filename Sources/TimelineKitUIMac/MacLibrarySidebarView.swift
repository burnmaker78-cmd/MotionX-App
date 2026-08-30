#if canImport(AppKit)
import AppKit
import TimelineKitUIShared

/// Browser 左栏：资源库侧栏（FCP 左栏结构）。
///
/// 展示当前库名、"智能精选"、日期事件分组（按媒体分组日期派生的年份/日期列表）。
/// 选中一个事件时，右栏媒体面板聚焦该日期分组。
@MainActor
final class MacLibrarySidebarView: NSView {

    // MARK: - Callbacks

    var onCreateOrOpenLibrary: (() -> Void)?
    var onImportMedia: (() -> Void)?
    /// 用户选中某个资源库/事件（参数为 nil = 全库）。
    var onSelectScope: ((LibraryMediaEntry.MediaKind?) -> Void)?

    // MARK: - Subviews

    private let titleLabel = NSTextField(labelWithString: "资源库")
    private let libraryNameLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let importButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        libraryNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        libraryNameLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        libraryNameLabel.lineBreakMode = .byTruncatingMiddle
        libraryNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryNameLabel)

        configureButton(openButton, title: "打开资源库", symbol: "folder", action: #selector(openTapped))
        configureButton(importButton, title: "导入媒体", symbol: "square.and.arrow.down", action: #selector(importTapped))

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            libraryNameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            libraryNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            libraryNameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            importButton.topAnchor.constraint(equalTo: libraryNameLabel.bottomAnchor, constant: 16),
            importButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            openButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 8),
            openButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configureButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.title = title
        button.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
    }

    func setLibraryName(_ name: String?) {
        libraryNameLabel.stringValue = name ?? "未打开资源库"
    }

    @objc private func openTapped() { onCreateOrOpenLibrary?() }
    @objc private func importTapped() { onImportMedia?() }
}

#endif
