
import TimelineKitCore
import AVFoundation
import CoreImage
import CoreMedia

// MARK: - ColorAdjustmentInstruction

/// Custom AVVideoCompositionInstruction carrying per-segment color adjustment data.
final class ColorAdjustmentInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool
    var containsTweening: Bool = false

    var requiredSourceTrackIDs: [NSValue]? {
        [NSValue(nonretainedObject: sourceTrackID)]
    }

    var requiredSourceSampleDataTrackIDs: [CMPersistentTrackID] { [] }
    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    let sourceTrackID: CMPersistentTrackID
    let segmentID: UUID
    let adjustment: SegmentAdjustment

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        segmentID: UUID,
        adjustment: SegmentAdjustment
    ) {
        self.timeRange = timeRange
        self.sourceTrackID = sourceTrackID
        self.segmentID = segmentID
        self.adjustment = adjustment
        self.enablePostProcessing = !adjustment.isIdentity
    }
}

// MARK: - ColorAdjustmentCompositor

/// Applies Core Image adjustments to individual video segments.
final class ColorAdjustmentCompositor: NSObject, AVVideoCompositing {

    var sourcePixelBufferAttributes: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    private let ciContext = CIContext(options: [
        .workingColorSpace: NSNull()
    ])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction =
                request.videoCompositionInstruction as? ColorAdjustmentInstruction else {
            request.finish(with: CompositorError.badInstruction)
            return
        }

        guard let pixelBuffer = request.sourceFrame(
            byTrackID: instruction.sourceTrackID
        ) else {
            request.finish(with: CompositorError.missingSourceFrame)
            return
        }

        // Skip processing when no adjustment is active.
        guard !instruction.adjustment.isIdentity else {
            request.finish(withComposedVideoFrame: pixelBuffer)
            return
        }

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: CompositorError.noOutputBuffer)
            return
        }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let result = applyAdjustments(instruction.adjustment, to: source)

        ciContext.render(result, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - CIFilter Chain

    private func applyAdjustments(
        _ adj: SegmentAdjustment,
        to image: CIImage
    ) -> CIImage {
        var result = image
        let extent = image.extent

        // Exposure
        if adj.exposure != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: adj.exposure
            ])
        }

        // Brightness, contrast, saturation
        if adj.brightness != 0 ||
            adj.contrast != 1 ||
            adj.saturation != 1 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: adj.brightness,
                kCIInputContrastKey: adj.contrast,
                kCIInputSaturationKey: adj.saturation
            ])
        }

        // Vibrance
        if adj.vibrance != 0 {
            result = result.applyingFilter("CIVibrance", parameters: [
                kCIInputAmountKey: adj.vibrance
            ])
        }

        // Temperature and tint.
        // Preserve the existing temperature/tint behavior.
        if adj.temperature != 6500 || adj.tint != 0 {
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(
                    x: CGFloat(adj.temperature),
                    y: CGFloat(adj.tint)
                ),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }

        // Highlights and shadows.
        if adj.highlights != 0 || adj.shadows != 0 {
            result = result.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": min(
                    max(1.0 - adj.highlights, 0.0), 1.0
                ),
                "inputShadowAmount": min(
                    max(adj.shadows, 0.0), 1.0
                )
            ])
        }

        // Whites and blacks: shape the endpoints of the tone curve.
        if adj.whites != 0 || adj.blacks != 0 {
            let whites = min(max(adj.whites, -1.0), 1.0)
            let blacks = min(max(adj.blacks, -1.0), 1.0)

            let point0 = CIVector(
                x: 0,
                y: CGFloat(min(max(blacks * 0.22, 0), 1))
            )
            let point1 = CIVector(
                x: 0.25,
                y: CGFloat(min(max(0.25 + blacks * 0.08, 0), 1))
            )
            let point2 = CIVector(x: 0.5, y: 0.5)
            let point3 = CIVector(
                x: 0.75,
                y: CGFloat(min(max(0.75 + whites * 0.08, 0), 1))
            )
            let point4 = CIVector(
                x: 1,
                y: CGFloat(min(max(1.0 + whites * 0.22, 0), 1))
            )

            result = result.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": point0,
                "inputPoint1": point1,
                "inputPoint2": point2,
                "inputPoint3": point3,
                "inputPoint4": point4
            ])
        }

        // Clarity: local contrast using an unsharp mask.
        if adj.clarity > 0 {
            result = result.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 2.5,
                kCIInputIntensityKey: min(max(adj.clarity, 0), 1) * 0.7
            ])
        }

        // Sharpen: enhance luminance detail.
        if adj.sharpen > 0 {
            result = result.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: min(max(adj.sharpen, 0), 1)
            ])
        }

        // Fade: reduce contrast and gently lift brightness.
        if adj.fade > 0 {
            let amount = min(max(adj.fade, 0), 1)

            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.0 - amount * 0.3,
                kCIInputBrightnessKey: amount * 0.06
            ])
        }

        // Vignette: darken the image edges.
        if adj.vignette > 0 {
            result = result.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: min(max(adj.vignette, 0), 1) * 1.5,
                kCIInputRadiusKey: 1.0
            ])
        }

        // Grain: blend subtle monochrome noise over the image.
        if adj.grain > 0 {
            let amount = min(max(adj.grain, 0), 1)

            if let randomImage = CIFilter(name: "CIRandomGenerator")?.outputImage {
                let noise = randomImage
                    .cropped(to: extent)
                    .applyingFilter("CIColorControls", parameters: [
                        kCIInputSaturationKey: 0.0,
                        kCIInputContrastKey: 1.0,
                        kCIInputBrightnessKey: -0.5
                    ])
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputBiasVector": CIVector(
                            x: 0, y: 0, z: 0, w: amount * 0.15
                        )
                    ])

                result = noise
                    .applyingFilter("CISoftLightBlendMode", parameters: [
                        kCIInputBackgroundImageKey: result
                    ])
                    .cropped(to: extent)
            }
        }

        // Preset filter with optional intensity blending.
        if let preset = adj.filterName {
            let filtered = result.applyingFilter(preset.ciFilterName)
            let intensity = min(max(adj.filterIntensity, 0), 1)

            if intensity >= 1 {
                result = filtered
            } else if intensity > 0 {
                result = filtered.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: result,
                    kCIInputTimeKey: 1.0 - intensity
                ])
            }
        }

        return result.cropped(to: extent)
    }

    // MARK: - Errors

    private enum CompositorError: Error {
        case badInstruction
        case missingSourceFrame
        case noOutputBuffer
    }
}
