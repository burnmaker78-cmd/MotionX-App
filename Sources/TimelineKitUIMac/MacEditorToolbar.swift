#if canImport(AppKit)
import AppKit
import TimelineKitUIShared

// MARK: - MacEditorToolbar

/// Top toolbar for the macOS editor shell (FCP style).
///
/// UI-structure milestone: import entry, title, and an export placeholder.
/// Playback controls live in the timeline control bar (剪映 Mac style), not here.
@MainActor
final class MacEditorToolbar: NSView {

    // MARK: - Callbacks (hosted by the shell / demo)

    /// User tapped "导入素材".
    var onImportMedia: (() -> Void)?

    // MARK: - Subviews

    private let titleLabel = NSTextField(labelWithString: "TimelineKit")
    private let importButton = NSButton()
    private let exportButton = NSButton()

    static let height: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 工具栏背景略亮于内容区（0.10 vs 0.08），形成层次但保持深色统一。
        // 不用语义色 windowBackgroundColor，避免浅色外观下解析为白色。
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        configureButton(importButton, title: "导入素材", symbol: "square.and.arrow.down",
                        action: #selector(importTapped))
        configureButton(exportButton, title: "导出", symbol: "square.and.arrow.up",
                        action: #selector(exportTapped))
        // Export is a placeholder in the UI-structure milestone.
        exportButton.isEnabled = false

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            importButton.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -8),
            importButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            exportButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            exportButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Helpers

    private func configureButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.isBordered = true
        button.bezelStyle = .rounded
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
    }

    @objc private func importTapped() {
        onImportMedia?()
    }

    @objc private func exportTapped() {
        // Placeholder — export pipeline wiring is a later iteration.
    }
}

#endif
