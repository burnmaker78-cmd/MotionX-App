
import Foundation

// MARK: - SegmentAdjustment

/// Per-segment color, tone, and detail adjustments.
/// All added values default to no effect.
public struct SegmentAdjustment: Sendable, Hashable, Codable {

    // MARK: - Tone

    /// CIColorControls brightness: -1...1
    public var brightness: Double

    /// CIColorControls contrast: 0.5...1.5
    public var contrast: Double

    /// CIColorControls saturation: 0...2
    public var saturation: Double

    /// CIExposureAdjust exposure bias, in EV.
    public var exposure: Double

    /// CIVibrance amount: -1...1
    public var vibrance: Double

    // MARK: - Color Temperature

    /// White balance temperature in Kelvin.
    public var temperature: Double

    /// Green/magenta tint adjustment.
    public var tint: Double

    // MARK: - Highlights and Shadows

    public var highlights: Double
    public var shadows: Double

    /// White point adjustment: -1...1
    public var whites: Double

    /// Black point adjustment: -1...1
    public var blacks: Double

    // MARK: - Detail and Style

    /// Sharpening amount: 0...1
    public var sharpen: Double

    /// Local contrast amount: 0...1
    public var clarity: Double

    /// Faded look amount: 0...1
    public var fade: Double

    /// Vignette amount: 0...1
    public var vignette: Double

    /// Film grain amount: 0...1
    public var grain: Double

    // MARK: - Preset Filter

    public var filterName: PresetFilter?
    public var filterIntensity: Double

    // MARK: - Initializer

    public init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        temperature: Double = 6500,
        tint: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        filterName: PresetFilter? = nil,
        filterIntensity: Double = 1,
        exposure: Double = 0,
        vibrance: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        sharpen: Double = 0,
        clarity: Double = 0,
        fade: Double = 0,
        vignette: Double = 0,
        grain: Double = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.filterName = filterName
        self.filterIntensity = filterIntensity

        self.exposure = exposure
        self.vibrance = vibrance
        self.whites = whites
        self.blacks = blacks
        self.sharpen = sharpen
        self.clarity = clarity
        self.fade = fade
        self.vignette = vignette
        self.grain = grain
    }

    // MARK: - Identity

    public static let identity = SegmentAdjustment()

    /// True when every adjustment is at its default value.
    public var isIdentity: Bool {
        brightness == 0 &&
        contrast == 1 &&
        saturation == 1 &&
        temperature == 6500 &&
        tint == 0 &&
        highlights == 0 &&
        shadows == 0 &&
        exposure == 0 &&
        vibrance == 0 &&
        whites == 0 &&
        blacks == 0 &&
        sharpen == 0 &&
        clarity == 0 &&
        fade == 0 &&
        vignette == 0 &&
        grain == 0 &&
        filterName == nil
    }

    // MARK: - Backward-Compatible Decoding

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation
        case temperature, tint
        case highlights, shadows
        case filterName, filterIntensity
        case exposure, vibrance, whites, blacks
        case sharpen, clarity, fade, vignette, grain
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        brightness = try values.decodeIfPresent(
            Double.self, forKey: .brightness
        ) ?? 0

        contrast = try values.decodeIfPresent(
            Double.self, forKey: .contrast
        ) ?? 1

        saturation = try values.decodeIfPresent(
            Double.self, forKey: .saturation
        ) ?? 1

        temperature = try values.decodeIfPresent(
            Double.self, forKey: .temperature
        ) ?? 6500

        tint = try values.decodeIfPresent(
            Double.self, forKey: .tint
        ) ?? 0

        highlights = try values.decodeIfPresent(
            Double.self, forKey: .highlights
        ) ?? 0

        shadows = try values.decodeIfPresent(
            Double.self, forKey: .shadows
        ) ?? 0

        filterName = try values.decodeIfPresent(
            PresetFilter.self, forKey: .filterName
        )

        filterIntensity = try values.decodeIfPresent(
            Double.self, forKey: .filterIntensity
        ) ?? 1

        exposure = try values.decodeIfPresent(
            Double.self, forKey: .exposure
        ) ?? 0

        vibrance = try values.decodeIfPresent(
            Double.self, forKey: .vibrance
        ) ?? 0

        whites = try values.decodeIfPresent(
            Double.self, forKey: .whites
        ) ?? 0

        blacks = try values.decodeIfPresent(
            Double.self, forKey: .blacks
        ) ?? 0

        sharpen = try values.decodeIfPresent(
            Double.self, forKey: .sharpen
        ) ?? 0

        clarity = try values.decodeIfPresent(
            Double.self, forKey: .clarity
        ) ?? 0

        fade = try values.decodeIfPresent(
            Double.self, forKey: .fade
        ) ?? 0

        vignette = try values.decodeIfPresent(
            Double.self, forKey: .vignette
        ) ?? 0

        grain = try values.decodeIfPresent(
            Double.self, forKey: .grain
        ) ?? 0
    }
}

// MARK: - PresetFilter

/// Built-in Core Image presets.
/// Case names are preserved for saved-project compatibility.
public enum PresetFilter: String, Sendable, Hashable, Codable, CaseIterable {

    case naturalVivid
    case naturalWarm
    case naturalCool
    case naturalSoft

    case cinemaChrome
    case cinemaNoir
    case cinemaInstant
    case cinemaMono

    case retroTransfer
    case retroFade
    case retroProcess
    case retroSepia

    public var ciFilterName: String {
        switch self {
        case .naturalVivid: return "CIVibrance"
        case .naturalWarm: return "CIPhotoEffectProcess"
        case .naturalCool: return "CIPhotoEffectFade"
        case .naturalSoft: return "CIPhotoEffectTonal"
        case .cinemaChrome: return "CIPhotoEffectChrome"
        case .cinemaNoir: return "CIPhotoEffectNoir"
        case .cinemaInstant: return "CIPhotoEffectInstant"
        case .cinemaMono: return "CIPhotoEffectMono"
        case .retroTransfer: return "CIPhotoEffectTransfer"
        case .retroFade: return "CIPhotoEffectFade"
        case .retroProcess: return "CIPhotoEffectProcess"
        case .retroSepia: return "CISepiaTone"
        }
    }

    public var displayName: String {
        switch self {
        case .naturalVivid: return "Vivid"
        case .naturalWarm: return "Warm"
        case .naturalCool: return "Cool"
        case .naturalSoft: return "Soft"
        case .cinemaChrome: return "Chrome"
        case .cinemaNoir: return "Noir"
        case .cinemaInstant: return "Instant"
        case .cinemaMono: return "Monochrome"
        case .retroTransfer: return "Transfer"
        case .retroFade: return "Retro Fade"
        case .retroProcess: return "Retro Process"
        case .retroSepia: return "Sepia"
        }
    }

    public var category: Category {
        switch self {
        case .naturalVivid, .naturalWarm, .naturalCool, .naturalSoft:
            return .natural
        case .cinemaChrome, .cinemaNoir, .cinemaInstant, .cinemaMono:
            return .cinematic
        case .retroTransfer, .retroFade, .retroProcess, .retroSepia:
            return .retro
        }
    }

    public enum Category: String, CaseIterable {
        case natural = "Natural"
        case cinematic = "Cinematic"
        case retro = "Retro"
    }
}
