
#if canImport(UIKit)
import SwiftUI
import TimelineKitCore
import TimelineKitUIShared

// MARK: - Tool Category

/// All top-level editing categories.
public enum EditorToolCategory: String, CaseIterable, Identifiable {
    case clip = "Clip"
    case audio = "Audio"
    case text = "Text"
    case sticker = "Stickers"
    case effects = "Effects"
    case transition = "Transition"
    case adjust = "Adjust"
    case animation = "Animation"

    public var id: String { rawValue }

    /// Only show categories that are available in this version.
    var isEnabled: Bool {
        switch self {
        case .clip, .audio, .text, .transition, .adjust, .animation:
            return true
        default:
            return false
        }
    }

    var icon: String {
        switch self {
        case .clip:       return "scissors"
        case .audio:      return "music.note"
        case .text:       return "textformat"
        case .sticker:    return "face.smiling"
        case .effects:    return "sparkles"
        case .transition: return "arrow.left.and.right.square"
        case .adjust:     return "slider.horizontal.3"
        case .animation:  return "wand.and.stars"
        }
    }
}

// MARK: - Bottom Toolbar

/// Always-visible bottom toolbar. Tapping a category toggles its secondary panel.
struct EditorBottomToolbar: View {
    @Binding var activeCategory: EditorToolCategory?

    static let height: CGFloat = 68

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(EditorToolCategory.allCases.filter(\.isEnabled)) { category in
                    categoryButton(for: category)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: Self.height)
        .background(Color(white: 0.11))
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    private func categoryButton(for category: EditorToolCategory) -> some View {
        let isActive = activeCategory == category

        return Button {
            withAnimation(.spring(duration: 0.25)) {
                activeCategory = isActive ? nil : category
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 40, height: 28)

                Text(category.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isActive ? Color.yellow : Color.white.opacity(0.8))
            .frame(width: 64)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Tool Panel

/// Context-sensitive panel shown above the bottom toolbar.
struct EditorSecondaryToolPanel: View {
    let category: EditorToolCategory
    let store: EditorStore
    var onDismiss: (() -> Void)? = nil

    static let height: CGFloat = 72

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                toolStubs(for: category)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.height)
        .background(Color(white: 0.13))
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    // MARK: - Tools per category

    @ViewBuilder
    private func toolStubs(for category: EditorToolCategory) -> some View {
        switch category {
        case .clip:
            let hasSelection = store.selection.hasSingleSelection
            let selectedID = store.selection.singleSelectedID

            toolButton("Split", icon: "scissors.badge.ellipsis", enabled: hasSelection) {
                guard let id = selectedID else { return }
                store.splitSegment(id: id, at: store.selection.playheadTime)
            }

            toolButton("Delete", icon: "trash", enabled: hasSelection) {
                guard let id = selectedID else { return }
                store.deleteSegment(id: id)
            }

            toolButton("Duplicate", icon: "doc.on.doc", enabled: hasSelection) {
                guard let id = selectedID else { return }
                store.copySegment(id: id)
            }

            toolButton("Paste", icon: "doc.on.clipboard", enabled: store.hasClipboardSegment) {
                store.pasteSegment(after: selectedID)
            }

        case .transition:
            toolItem("Transition", icon: "arrow.left.and.right.square")

        case .adjust:
            toolItem("Adjust", icon: "slider.horizontal.3")

        case .text:
            toolButton("Add Text", icon: "textformat", enabled: true) {
                store.createNewTextSegment()
            }

            toolButton("Add Subtitle", icon: "text.bubble", enabled: true) {
                store.createNewSubtitleSegment()
            }

        case .audio:
            toolItem("Audio", icon: "music.note")

        case .animation:
            toolItem("Animation", icon: "wand.and.stars")

        case .sticker:
            toolItem("Stickers", icon: "face.smiling")

        case .effects:
            toolItem("Effects", icon: "sparkles")
        }
    }

    private func toolButton(
        _ label: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 44, height: 36)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .foregroundStyle(
                enabled ? Color.white.opacity(0.85) : Color.white.opacity(0.35)
            )
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toolItem(_ label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 44, height: 36)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .frame(width: 60)
    }
}
#endif
