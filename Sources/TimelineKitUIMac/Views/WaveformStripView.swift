//
//  WaveformStripView.swift
//  TimelineKit
//
//  Created by xiaoyuan on 2026/8/31.
//

#if canImport(AppKit)

import AppKit
import TimelineKitRender

// MARK: - WaveformStripView

/// A waveform visualization for audio segment blocks.
/// Renders symmetric amplitude bars using a CAShapeLayer.
/// Waveform data is generated asynchronously via WaveformProvider and cached.
final class WaveformStripView: BaseFlippedView {

    /// Gap between bars in the waveform, in points.
    private static let barGap: CGFloat = 0.5

    private let shapeLayer = CAShapeLayer()
    private var loadingTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        shapeLayer.fillColor = NSColor.white.withAlphaComponent(0.6).cgColor
        shapeLayer.strokeColor = nil
        layer?.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) { fatalError() }
    
    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let window {
            layer?.contentsScale = window.backingScaleFactor
        }
    }

    // MARK: - Load

    func load(url: URL) {
        loadingTask?.cancel()
        shapeLayer.path = nil

        guard bounds.width > 4, bounds.height > 4 else { return }

        let viewSize = bounds.size
        let task = Task { [weak self] in
            guard let self else { return }
            let samples = await WaveformProvider.shared.waveform(for: url)
            guard !Task.isCancelled, let samples else { return }
            await MainActor.run {
                self.shapeLayer.path = Self.buildPath(samples: samples, size: viewSize)
            }
        }
        loadingTask = task
    }

    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    // MARK: - Path building

    private static func buildPath(samples: [Float], size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard samples.count > 1, size.width > 0, size.height > 0 else { return path }

        let barCount = min(samples.count, Int(size.width / (1 + barGap)))
        let step = max(1, samples.count / barCount)
        let barWidth = max(1, size.width / CGFloat(barCount) - barGap)
        let midY = size.height / 2
        let maxAmp = midY - 2  // 2pt padding from top/bottom

        for i in 0..<barCount {
            let sampleIdx = min(i * step + step / 2, samples.count - 1)
            let amp = CGFloat(samples[sampleIdx]) * maxAmp
            let x = CGFloat(i) * (barWidth + barGap)
            let rect = CGRect(x: x, y: midY - amp, width: barWidth, height: amp * 2)
            path.addRect(rect)
        }

        return path
    }
}

#endif
