//
//  TrackLabelRowView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

import AppKit
import TimelineKitCore

// MARK: - Track Label Row View

/// A single row in the collapsible track labels sidebar.
///
/// Layout (collapsed, 52pt) — pure icon + name, all buttons hidden:
/// ```
/// [icon]
/// [name]
/// ```
///
/// Layout (expanded, 136pt) — full control panel:
/// ```
/// [icon] [name] [lock] [hide] [mute] [+]
/// ```
///
/// Per-kind button visibility:
/// - Lock : every track
/// - Hide : every track EXCEPT main video
/// - Mute : only `.video` and `.audio` tracks
final class TrackLabelRowView: BaseFlippedView {
    
    var onToggleLock:   (() -> Void)?
    var onToggleHidden: (() -> Void)?
    var onToggleMute:   (() -> Void)?
    var onAddTrack:     (() -> Void)?
    
    private var track: EditorTrack
    private var isExpanded: Bool
    
    private let iconView   = NSImageView()
    private let nameLabel  = NSTextField(labelWithString: "")
    private let buttonStack = NSStackView()
    private var lockBtn: NSButton?
    private var hideBtn: NSButton?
    private var muteBtn: NSButton?
    private var addBtn: NSButton?
    
    private static let tracksWithAudio: Set<EditorTrack.Kind> = [.video, .audio]
    
    override var isFlipped: Bool {
        return true
    }
    
    init(track: EditorTrack, isExpanded: Bool, showAddButton: Bool) {
        self.track = track
        self.isExpanded = isExpanded
        super.init(frame: .zero)
        wantsLayer = true
        
        // Icon
        iconView.image = Self.icon(for: track.kind)
        iconView.contentTintColor = Self.iconColor(for: track.kind)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        // Name label
        nameLabel.stringValue = Self.labelText(for: track.kind)
        nameLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        // Button stack (horizontal)
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 4
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)
        
        // Icon + label vertical stack pinned left
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6),
            nameLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            
            buttonStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
        
        buildButtons(track: track, showAddButton: showAddButton)
        applyExpandedState(animated: false)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - Update
    
    func update(track: EditorTrack, isExpanded: Bool) {
        self.track = track
        self.isExpanded = isExpanded
        refreshButtonIcons()
        applyExpandedState(animated: false)
    }
    
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        applyExpandedState(animated: true)
    }
    
    private func applyExpandedState(animated: Bool) {
        let changes = {
            // Collapsed: all buttons hidden (pure icon + name).
            // Expanded: full lock / hide / mute per track kind rules.
            let showControls = self.isExpanded
            
            for btn in [self.lockBtn, self.hideBtn, self.muteBtn].compactMap({ $0 }) {
                btn.alphaValue = showControls ? 1 : 0
                btn.isHidden = !showControls
            }
            self.addBtn?.alphaValue = showControls ? 1 : 0
            self.addBtn?.isHidden = !showControls
            self.buttonStack.layoutSubtreeIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                changes()
            }
        } else {
            changes()
        }
    }
    
    private func refreshButtonIcons() {
        Self.style(button: lockBtn,
                   icon: track.isLocked ? "lock.fill" : "lock.open",
                   tint: track.isLocked ? .systemYellow : .white.withAlphaComponent(0.65),
                   label: track.isLocked ? "解锁轨道" : "锁定轨道")
        if let h = hideBtn {
            Self.style(button: h,
                       icon: track.isHidden ? "eye.slash.fill" : "eye",
                       tint: track.isHidden ? .systemOrange : .white.withAlphaComponent(0.65),
                       label: track.isHidden ? "显示轨道" : "隐藏轨道")
        }
        if let m = muteBtn {
            Self.style(button: m,
                       icon: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                       tint: track.isMuted ? .systemRed : .white.withAlphaComponent(0.65),
                       label: track.isMuted ? "取消静音" : "静音轨道")
        }
    }
    
    // MARK: - Button building
    
    private func buildButtons(track: EditorTrack, showAddButton: Bool) {
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        lockBtn = nil; hideBtn = nil; muteBtn = nil; addBtn = nil
        
        // Lock — every track
        let lock = Self.makeButton()
        Self.style(button: lock,
                   icon: track.isLocked ? "lock.fill" : "lock.open",
                   tint: track.isLocked ? .systemYellow : .white.withAlphaComponent(0.65),
                   label: track.isLocked ? "解锁轨道" : "锁定轨道")
        lock.target = self
        lock.action = #selector(lockAction)
        buttonStack.addArrangedSubview(lock)
        lockBtn = lock
        
        // Hide — every track except main video
        if !track.isMainTrack {
            let hide = Self.makeButton()
            Self.style(button: hide,
                       icon: track.isHidden ? "eye.slash.fill" : "eye",
                       tint: track.isHidden ? .systemOrange : .white.withAlphaComponent(0.65),
                       label: track.isHidden ? "显示轨道" : "隐藏轨道")
            hide.target = self
            hide.action = #selector(hideAction)
            buttonStack.addArrangedSubview(hide)
            hideBtn = hide
        }
        
        // Mute — only video + audio
        if Self.tracksWithAudio.contains(track.kind) {
            let mute = Self.makeButton()
            Self.style(button: mute,
                       icon: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                       tint: track.isMuted ? .systemRed : .white.withAlphaComponent(0.65),
                       label: track.isMuted ? "取消静音" : "静音轨道")
            mute.target = self
            mute.action = #selector(muteAction)
            buttonStack.addArrangedSubview(mute)
            muteBtn = mute
        }
        
        // "+" add track button
        if showAddButton {
            let plus = Self.makeButton()
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            plus.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "新建\(Self.labelText(for: track.kind))轨道")?.withSymbolConfiguration(cfg)
            plus.contentTintColor = NSColor.white.withAlphaComponent(0.55)
            plus.target = self
            plus.action = #selector(plusAction)
            buttonStack.addArrangedSubview(plus)
            addBtn = plus
        }
    }
    
    // MARK: - Actions
    @objc private func lockAction() {
        self.triggerHapticFeedback()
        self.onToggleLock?()
    }
    
    @objc private func hideAction() {
        self.triggerHapticFeedback()
        self.onToggleHidden?()
    }
    
    @objc private func muteAction() {
        self.triggerHapticFeedback()
        self.onToggleMute?()
    }
    
    @objc private func plusAction() {
        self.onAddTrack?()
    }

    // MARK: - Helpers
    
    private func triggerHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private static func makeButton() -> NSButton {
        let btn = NSButton()
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.wantsLayer = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22)
        ])
        return btn
    }

    private static func style(button: NSButton?, icon: String, tint: NSColor, label: String) {
        guard let button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)?
                .withSymbolConfiguration(cfg)
        button.contentTintColor = tint
    }

    // MARK: - Static helpers (same as before)

    static func icon(for kind: EditorTrack.Kind) -> NSImage? {
        let name: String = {
            switch kind {
            case .video:      return "video.fill"
            case .overlay:    return "square.on.square.fill"
            case .text:       return "textformat"
            case .subtitle:   return "captions.bubble.fill"
            case .audio:      return "music.note"
            case .adjustment: return "slider.horizontal.3"
            }
        }()
        return NSImage(systemSymbolName: name, accessibilityDescription: name)
    }

    static func iconColor(for kind: EditorTrack.Kind) -> NSColor {
        switch kind {
        case .video:      return NSColor.systemPurple
        case .overlay:    return NSColor.systemOrange
        case .text:       return NSColor.systemGreen
        case .subtitle:   return NSColor.systemBlue
        case .audio:      return NSColor.systemTeal
        case .adjustment: return NSColor.systemYellow
        }
    }

    static func labelText(for kind: EditorTrack.Kind) -> String {
        switch kind {
        case .video:      return "视频"
        case .overlay:    return "叠加"
        case .text:       return "文字"
        case .subtitle:   return "字幕"
        case .audio:      return "音频"
        case .adjustment: return "调节"
        }
    }
}
