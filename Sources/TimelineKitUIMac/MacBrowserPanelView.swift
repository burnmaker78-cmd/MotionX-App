#if canImport(AppKit)
import AppKit
import TimelineKitCore
import TimelineKitUIShared

// MARK: - MacBrowserPanelView

/// Browser panel (FCP style): left library/event sidebar + right media grid.
///
/// State driven by `TimelineLibraryStore`:
///   - No library: shows the "创建资源库" / "打开资源库" empty card (left).
///   - Library, no media: shows "导入媒体" empty state (right grid).
///   - Library + media: NSCollectionView grid of imported media thumbnails.
///
/// Importing is triggered by the host (ClipEditorView toolbar / open dialog),
/// which calls `libraryStore.addMedia(urls:)`.
@MainActor
final class MacBrowserPanelView: NSView {

    // MARK: - Callbacks

    /// Host asks the user to create/open a library (via NSSavePanel/NSOpenPanel).
    var onCreateOrOpenLibrary: (() -> Void)?
    /// Host asks the user to pick media files and import them into the library.
    var onImportMedia: (() -> Void)?
    /// User double-clicked a media item — host adds it to the timeline.
    var onMediaSelected: ((URL) -> Void)?

    // MARK: - Subviews

    private let libraryStore: TimelineLibraryStore
    private let sidebar = MacLibrarySidebarView(frame: .zero)
    private let grid = NSCollectionView()
    private let gridScroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")

    // MARK: - Init

    init(libraryStore: TimelineLibraryStore) {
        self.libraryStore = libraryStore
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        setupViews()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Left sidebar (library + events).
        sidebar.onCreateOrOpenLibrary = { [weak self] in self?.onCreateOrOpenLibrary?() }
        sidebar.onImportMedia = { [weak self] in self?.onImportMedia?() }
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)

        // Right media grid.
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 120, height: 90)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = false
        grid.backgroundColors = [NSColor(white: 0.08, alpha: 1)]
        grid.dataSource = self
        grid.delegate = self

        gridScroll.documentView = grid
        gridScroll.hasVerticalScroller = true
        gridScroll.drawsBackground = false
        gridScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridScroll)

        // Empty-state overlay (centered over grid).
        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 160),

            gridScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScroll.topAnchor.constraint(equalTo: topAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])
    }

    /// Refresh from the library store state.
    func refresh() {
        let hasLibrary = libraryStore.hasLibrary
        let media = libraryStore.mediaURLs

        sidebar.setLibraryName(libraryStore.library?.name)
        sidebar.setMediaCount(media.count)
        grid.reloadData()

        // Empty states.
        if !hasLibrary {
            emptyLabel.stringValue = "创建资源库后导入媒体"
            emptyLabel.isHidden = false
        } else if media.isEmpty {
            emptyLabel.stringValue = "导入媒体\n（图片 / 视频 / 音频）"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension MacBrowserPanelView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        libraryStore.mediaURLs.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let id = NSUserInterfaceItemIdentifier("MacMediaItem")
        let item = (collectionView.makeItem(withIdentifier: id, for: indexPath) as? MacMediaItem)
            ?? MacMediaItem()

        let url = libraryStore.mediaURLs[indexPath.item]
        item.configure(url: url)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension MacBrowserPanelView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let idx = indexPaths.first else { return }
        let url = libraryStore.mediaURLs[idx.item]
        onMediaSelected?(url)
    }
}

// MARK: - MacMediaItem

@MainActor
final class MacMediaItem: NSCollectionViewItem {
    private let thumbView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 4

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(thumbView)

        nameLabel.font = .systemFont(ofSize: 9, weight: .medium)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            thumbView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            thumbView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            thumbView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            thumbView.heightAnchor.constraint(equalToConstant: 56),

            nameLabel.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 3),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4)
        ])
        self.view = container
    }

    func configure(url: URL) {
        nameLabel.stringValue = url.lastPathComponent
        // Simple placeholder thumbnail; actual thumbnail generation is a later step.
        thumbView.image = NSImage(systemSymbolName: Self.symbol(for: url), accessibilityDescription: nil)
    }

    private static func symbol(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "avi": return "film"
        case "png", "jpg", "jpeg", "heic", "gif": return "photo"
        case "mp3", "m4a", "wav", "aac": return "waveform"
        default: return "doc"
        }
    }
}

// MARK: - MacLibrarySidebarView

@MainActor
final class MacLibrarySidebarView: NSView {
    var onCreateOrOpenLibrary: (() -> Void)?
    var onImportMedia: (() -> Void)?

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

    func setMediaCount(_ count: Int) {
        // Reserved for a badge; no-op for now.
        _ = count
    }

    @objc private func openTapped() { onCreateOrOpenLibrary?() }
    @objc private func importTapped() { onImportMedia?() }
}

#endif

