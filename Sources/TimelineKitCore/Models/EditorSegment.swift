
import Foundation

/// A single clip placed on a track. The core editing unit.
public struct EditorSegment: Identifiable, Sendable, Hashable, Codable {

    // MARK: - Codable (backward compatibility)

    private enum CodingKeys: String, CodingKey {
        case id, materialID, sourceRange, targetRange, speed, transform
        case blendMode, keyframes, content
        case leadingTransitionID, trailingTransitionID
        case adjustment, sourceSceneID, sourceZIndex, userZOrder
        case animations
        case effects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        materialID = try c.decode(UUID.self, forKey: .materialID)
        sourceRange = try c.decodeIfPresent(TimeRange.self, forKey: .sourceRange)
        targetRange = try c.decode(TimeRange.self, forKey: .targetRange)
        speed = try c.decode(Double.self, forKey: .speed)
        transform = try c.decode(SegmentTransform.self, forKey: .transform)
        blendMode = try c.decode(BlendMode.self, forKey: .blendMode)
        keyframes = try c.decode(KeyframeSet.self, forKey: .keyframes)
        content = try c.decode(SegmentContent.self, forKey: .content)
        leadingTransitionID = try c.decodeIfPresent(UUID.self, forKey: .leadingTransitionID)
        trailingTransitionID = try c.decodeIfPresent(UUID.self, forKey: .trailingTransitionID)
        adjustment = try c.decodeIfPresent(SegmentAdjustment.self, forKey: .adjustment) ?? .identity
        sourceSceneID = try c.decodeIfPresent(String.self, forKey: .sourceSceneID)
        sourceZIndex = try c.decodeIfPresent(Int.self, forKey: .sourceZIndex)
        userZOrder = try c.decodeIfPresent(Int.self, forKey: .userZOrder)
        animations = try c.decodeIfPresent([ClipAnimation].self, forKey: .animations) ?? []
        effects = try c.decodeIfPresent([MotionXClipEffect].self, forKey: .effects) ?? []
    }

    public let id: UUID
    public var materialID: UUID
    public var sourceRange: TimeRange?
    public var targetRange: TimeRange

    public var speed: Double
    public var transform: SegmentTransform
    public var blendMode: BlendMode
    public var keyframes: KeyframeSet
    public var content: SegmentContent

    public var leadingTransitionID: UUID?
    public var trailingTransitionID: UUID?

    /// Per-segment color and tone adjustments.
    public var adjustment: SegmentAdjustment

    public var sourceSceneID: String?
    public var sourceZIndex: Int?
    public var userZOrder: Int?

    /// Clip-level animations.
    public var animations: [ClipAnimation]

    /// Effects applied to this clip during rendering.
    public var effects: [MotionXClipEffect]

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        sourceRange: TimeRange? = nil,
        targetRange: TimeRange,
        speed: Double = 1.0,
        transform: SegmentTransform = .identity,
        blendMode: BlendMode = .normal,
        keyframes: KeyframeSet = .empty,
        content: SegmentContent,
        leadingTransitionID: UUID? = nil,
        trailingTransitionID: UUID? = nil,
        adjustment: SegmentAdjustment = .identity,
        sourceSceneID: String? = nil,
        sourceZIndex: Int? = nil,
        userZOrder: Int? = nil,
        animations: [ClipAnimation] = [],
        effects: [MotionXClipEffect] = []
    ) {
        self.id = id
        self.materialID = materialID
        self.sourceRange = sourceRange
        self.targetRange = targetRange
        self.speed = speed
        self.transform = transform
        self.blendMode = blendMode
        self.keyframes = keyframes
        self.content = content
        self.leadingTransitionID = leadingTransitionID
        self.trailingTransitionID = trailingTransitionID
        self.adjustment = adjustment
        self.sourceSceneID = sourceSceneID
        self.sourceZIndex = sourceZIndex
        self.userZOrder = userZOrder
        self.animations = animations
        self.effects = effects
    }
}

// MARK: - EditorSegment helpers

extension EditorSegment {
    public var isSubtitle: Bool {
        if case .subtitle = content { return true }
        return false
    }

    public var isText: Bool {
        if case .text = content { return true }
        return false
    }

    public var isAudio: Bool {
        if case .audio = content { return true }
        return false
    }
}

// MARK: - Animation accessors

extension EditorSegment {
    public var inAnimation: ClipAnimation? {
        animations.first { $0.timing == .in }
    }

    public var outAnimation: ClipAnimation? {
        animations.first { $0.timing == .out }
    }

    public var comboAnimation: ClipAnimation? {
        animations.first { $0.timing == .combo }
    }

    public mutating func setAnimation(_ anim: ClipAnimation) {
        if anim.timing == .combo {
            animations = [anim]
        } else {
            animations.removeAll {
                $0.timing == anim.timing || $0.timing == .combo
            }
            animations.append(anim)
        }
    }

    public mutating func removeAnimation(timing: AnimationTiming) {
        animations.removeAll { $0.timing == timing }
    }
}

// MARK: - Clip effects

public enum MotionXEffectKind: String, Sendable, Hashable, Codable, CaseIterable {
    case glow
    case tiles
    case waveWarp
    case oscillate
}

public struct MotionXClipEffect: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var kind: MotionXEffectKind
    public var isEnabled: Bool
    public var intensity: Double
    public var speed: Double
    public var size: Double

    public init(
        id: UUID = UUID(),
        kind: MotionXEffectKind,
        isEnabled: Bool = true,
        intensity: Double = 0.5,
        speed: Double = 0.5,
        size: Double = 0.5
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.intensity = intensity
        self.speed = speed
        self.size = size
    }
}

// MARK: - Blend modes

public enum BlendMode: String, Sendable, Hashable, Codable, CaseIterable {
    case normal
    case multiply, screen, overlay
    case hardLight = "hard_light"
    case softLight = "soft_light"
    case difference, exclusion
}
