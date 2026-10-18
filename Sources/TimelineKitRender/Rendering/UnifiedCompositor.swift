
import Foundation
import CoreImage
import CoreGraphics
import TimelineKitCore

/// Applies MotionX clip effects to a Core Image frame.
///
/// Effects are processed in the order stored on the clip.
public enum MotionXEffectsRenderer {

    public static func apply(
        _ effects: [MotionXClipEffect],
        to image: CIImage,
        at time: Double
    ) -> CIImage {
        let originalExtent = image.extent
        var result = image

        for effect in effects where effect.isEnabled {
            let intensity = CGFloat(
                min(max(effect.intensity, 0.0), 1.0)
            )
            let speed = min(max(effect.speed, 0.0), 1.0)
            let size = CGFloat(
                min(max(effect.size, 0.0), 1.0)
            )

            switch effect.kind {

            case .glow:
                // Soft glow around bright areas.
                let radius = 2.0 + size * 38.0
                let amount = intensity * 2.0

                result = result.applyingFilter(
                    "CIGloom",
                    parameters: [
                        kCIInputRadiusKey: radius,
                        kCIInputIntensityKey: amount
                    ]
                )

            case .tiles:
                // Repeat the image using an affine tiling transform.
                let scale = 1.0 / (1.0 + size * 3.0)

                let transform = CGAffineTransform(
                    scaleX: scale,
                    y: scale
                )

                result = result.applyingFilter(
                    "CIAffineTile",
                    parameters: [
                        kCIInputTransformKey:
                            NSValue(cgAffineTransform: transform)
                    ]
                )
                .cropped(to: originalExtent)

            case .waveWarp:
                // Distort the image with a moving wave.
                let radius = max(
                    originalExtent.width,
                    originalExtent.height
                ) * (0.08 + size * 0.42)

                let phase = time * (0.5 + speed * 5.0)

                result = result.applyingFilter(
                    "CIWaveDistortion",
                    parameters: [
                        kCIInputCenterKey: CIVector(
                            x: originalExtent.midX,
                            y: originalExtent.midY
                        ),
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: intensity * 0.08,
                        "inputAngle": phase
                    ]
                )
                .cropped(to: originalExtent)

            case .oscillate:
                // Move the frame back and forth over time.
                let phase = time * (1.0 + speed * 7.0)
                    * 2.0 * Double.pi

                let distance = Double(size) * Double(intensity) * 45.0

                let offsetX = CGFloat(sin(phase) * distance)
                let offsetY = CGFloat(cos(phase) * distance)

                result = result.transformed(
                    by: CGAffineTransform(
                        translationX: offsetX,
                        y: offsetY
                    )
                )
                .cropped(to: originalExtent)
            }
        }

        return result.cropped(to: originalExtent)
    }
}
