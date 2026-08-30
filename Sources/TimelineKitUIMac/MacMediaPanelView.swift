#if canImport(AppKit)
import AppKit
import Observation
import TimelineKitUIShared

/// Browser 右栏：按拍摄日期分组的媒体面板。
///
/// FCP 风格：折叠式日期头（"2026年4月28日 (1)"）+ 每组的缩略图网格。
/// 数据源为 `TimelineLibraryStore.groupedMedia`（按拍摄日期倒序分组）。
@MainActor
final class MacMediaPanelView: NSView {

    // MARK: - Callbacks

    /// User tapped a media item — host adds it to the timeline.
    var onMediaSelected: ((LibraryMediaEntry) -> Void)?

    // MARK: - Subviews

    private let libraryStore: TimelineLibraryStore
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    /// 折叠状态：已折叠的日期（startOfDay）。
    private var collapsedDates: Set<Date> = []

    private static let headerIdentifier = NSUserInterfaceItemIdentifier("MacMediaHeader")

    // MARK: - Init

    init(libraryStore: TimelineLibraryStore) {
        self.libraryStore = libraryStore
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        setupViews()
        refresh()
        startObserving()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 84)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        // Section header (date) geometry.
        layout.headerReferenceSize = NSSize(width: 0, height: 28)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [NSColor(white: 0.08, alpha: 1)]
        collectionView.register(MacMediaGridItem.self, forItemWithIdentifier: MacMediaGridItem.identifier)
        collectionView.register(MacMediaSectionHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: Self.headerIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])
    }

    // MARK: - Store observation

    private var observesStore = false

    private func startObserving() {
        guard !observesStore else { return }
        observesStore = true
        observeLoop()
    }

    private func observeLoop() {
        withObservationTracking {
            _ = libraryStore.mediaEntries
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observesStore else { return }
                self.refresh()
                self.observeLoop()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        collectionView.reloadData()

        let hasLibrary = libraryStore.hasLibrary
        let empty = libraryStore.groupedMedia.isEmpty
        if !hasLibrary {
            emptyLabel.stringValue = "创建资源库后导入媒体"
            emptyLabel.isHidden = false
        } else if empty {
            emptyLabel.stringValue = "导入媒体\n（图片 / 视频 / 音频）"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension MacMediaPanelView: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        libraryStore.groupedMedia.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        let group = libraryStore.groupedMedia[section]
        return collapsedDates.contains(group.date) ? 0 : group.items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MacMediaGridItem.identifier, for: indexPath) as? MacMediaGridItem
            ?? MacMediaGridItem()
        let group = libraryStore.groupedMedia[indexPath.section]
        let entry = group.items[indexPath.item]
        item.configure(entry: entry)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: Self.headerIdentifier, for: indexPath) as? MacMediaSectionHeader
            ?? MacMediaSectionHeader()
        let group = libraryStore.groupedMedia[indexPath.section]
        let count = group.items.count
        let isCollapsed = collapsedDates.contains(group.date)
        header.configure(date: group.date, count: count, isCollapsed: isCollapsed)
        header.onToggle = { [weak self] in
            guard let self else { return }
            if isCollapsed {
                self.collapsedDates.remove(group.date)
            } else {
                self.collapsedDates.insert(group.date)
            }
            self.collectionView.reloadData()
        }
        return header
    }
}

// MARK: - NSCollectionViewDelegate

extension MacMediaPanelView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let idx = indexPaths.first else { return }
        let group = libraryStore.groupedMedia[idx.section]
        let entry = group.items[idx.item]
        onMediaSelected?(entry)
    }
}

// MARK: - MacMediaGridItem

@MainActor
final class MacMediaGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MacMediaGridItem")

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
            thumbView.heightAnchor.constraint(equalToConstant: 52),

            nameLabel.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 3),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4)
        ])
        self.view = container
    }

    func configure(entry: LibraryMediaEntry) {
        nameLabel.stringValue = entry.originalFileName
        thumbView.image = NSImage(systemSymbolName: Self.symbol(for: entry.kind), accessibilityDescription: nil)
    }

    private static func symbol(for kind: LibraryMediaEntry.MediaKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }
}

// MARK: - MacMediaSectionHeader

@MainActor
final class MacMediaSectionHeader: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("MacMediaSectionHeader")

    var onToggle: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(date: Date, count: Int, isCollapsed: Bool) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        let chevron = isCollapsed ? "▸" : "▾"
        titleLabel.stringValue = "\(chevron) \(fmt.string(from: date))  (\(count))"
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }
}

#endif
