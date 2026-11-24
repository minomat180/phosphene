import AVFoundation
import ImageIO
import ObjectiveC
import os
import QuartzCore

/// The desktop's own wallpaper, in a display layer above the video. It covers the video
/// while the surface presents the unlocked desktop and fades away for the lock screen,
/// so the video plays only on the lock screen.
///
/// The layer joins the tree before the context is first hosted: a display layer added
/// to an already hosted context does not composite. It is empty and transparent until
/// a source arrives, and an image goes in as an IOSurface-backed sample buffer, since
/// `CALayer.contents` is black cross-process.
final class DesktopOverlay: @unchecked Sendable, TargetFollower {
    private static let idCounter = OSAllocatedUnfairLock(initialState: 0)
    let debugID: Int = DesktopOverlay.idCounter.withLock { $0 += 1; return $0 }

    /// Fade lengths. Fading out for the lock screen is short so the video is on screen
    /// while the lock reveal plays; fading in on unlock follows the desktop's zoom in.
    private static let fadeOutDuration: CFTimeInterval = 0.6
    private static let fadeInDuration: CFTimeInterval = 1.2

    let layer: AVSampleBufferDisplayLayer
    private let rootLayer: CALayer
    private let queue = DispatchQueue(label: "io.github.minomat180.phosphene.desktop-overlay", qos: .userInitiated)
    private let followTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    // Everything below is confined to `queue`.
    private var isRunning = true
    private var source: DesktopSource?
    /// Bumped on every source change, so a video that finishes opening after the
    /// source moved on is dropped.
    private var sourceGeneration = 0
    private var video: VideoRenderer?
    private var isShown = false
    private var desktopPolicy: PlaybackPolicy = .paused

    /// Create the layer and add it to `rootLayer`. Call before the context is hosted.
    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspectFill
        layer.frame = rootLayer.bounds
        layer.contentsScale = rootLayer.contentsScale
        layer.isOpaque = true
        layer.opacity = 0
        // Above the video's display layer, which is added later.
        layer.zPosition = 1
        setDisallowsVideoLayerDisplayCompositing(layer, true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.addSublayer(layer)
        CATransaction.commit()
    }

    func setFollowTask(_ task: Task<Void, Never>) {
        followTask.withLock { $0?.cancel(); $0 = task }
    }

    func apply(_ target: SurfaceTarget) {
        queue.async { [self] in reconcile(to: target) }
    }

    func resize(to destSize: CGSize, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: destSize)
        layer.contentsScale = scale
        CATransaction.commit()
        CATransaction.flush()
        queue.async { [self] in
            // An image was decoded for the old size; a video's layer just re-frames.
            if source?.kind == .image {
                showImage()
            }
        }
    }

    /// Stop for good. Must not be called on `queue`.
    func stop() {
        followTask.withLock { $0?.cancel(); $0 = nil }
        let video = queue.sync { () -> VideoRenderer? in
            isRunning = false
            let video = self.video
            self.video = nil
            return video
        }
        video?.stop()
        layer.removeFromSuperlayer()
    }

    // MARK: - Targets

    private func reconcile(to target: SurfaceTarget) {
        guard isRunning else { return }
        if target.desktopSource != source {
            load(target.desktopSource)
        }
        // A source that failed to load leaves the layer empty: keep the video visible.
        let shows = target.showsDesktop && source != nil
        if shows != isShown {
            isShown = shows
            fade(in: shows, animated: target.ramps)
        }
        if desktopPolicy != target.desktopPolicy {
            desktopPolicy = target.desktopPolicy
            video?.apply(SurfaceTarget(policy: target.desktopPolicy, ramps: false))
        }
    }

    private func fade(in shows: Bool, animated: Bool) {
        extensionLog("  [desktop #\(debugID)] \(shows ? "cover" : "uncover") video\(animated ? " (fade)" : "")")
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(shows ? Self.fadeInDuration : Self.fadeOutDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.opacity = shows ? 1 : 0
        CATransaction.commit()
        CATransaction.flush()
    }

    // MARK: - Sources

    private func load(_ newSource: DesktopSource?) {
        extensionLog("  [desktop #\(debugID)] source \(source.map(\.description) ?? "none") → \(newSource.map(\.description) ?? "none")")
        source = newSource
        sourceGeneration += 1
        if let video {
            self.video = nil
            // `stop()` syncs onto the renderer's own queue, never this one.
            video.stop()
        }
        // A desktop video left its clock on the layer; an image shows without one.
        layer.controlTimebase = nil
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        guard let newSource else { return }
        guard FileManager.default.fileExists(atPath: newSource.url.path) else {
            extensionLog("  [desktop #\(debugID)] missing file \(newSource.file)")
            source = nil
            return
        }
        switch newSource.kind {
        case .image: showImage()
        case .video: openVideo(newSource.url)
        }
    }

    private func showImage() {
        guard let url = source?.url else { return }
        let pixels = max(layer.bounds.width, layer.bounds.height) * max(layer.contentsScale, 1)
        guard let image = Self.loadImage(url, maxPixelSize: Int(pixels)),
              let buffer = makeStillSampleBuffer(from: image, taggedSRGB: true) else {
            extensionLog("  [desktop #\(debugID)] could not decode \(url.lastPathComponent)")
            source = nil
            return
        }
        VideoRenderer.setDisplayImmediately(buffer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sampleBufferRenderer.enqueue(buffer)
        CATransaction.commit()
        CATransaction.flush()
        extensionLog("  [desktop #\(debugID)] showing image \(url.lastPathComponent) (\(image.width)x\(image.height))")
    }

    private func openVideo(_ url: URL) {
        let generation = sourceGeneration
        let root = SendableBox(value: rootLayer)
        let layer = SendableBox(value: layer)
        Task(name: "Desktop video") { [self] in
            let renderer: VideoRenderer
            do {
                renderer = try await VideoRenderer.create(rootLayer: root.value, videoURL: url, displayLayer: layer.value)
            } catch {
                extensionLog("  [desktop #\(debugID)] could not open \(url.lastPathComponent): \(error)")
                return
            }
            renderer.setVariantSelector { _ in url }
            let current = queue.sync { () -> Bool in
                guard isRunning, generation == sourceGeneration else { return false }
                video = renderer
                renderer.apply(SurfaceTarget(policy: desktopPolicy, ramps: false))
                return true
            }
            guard current else {
                renderer.stop()
                return
            }
            await renderer.start()
            extensionLog("  [desktop #\(debugID)] playing video \(url.lastPathComponent)")
        }
    }

    /// Decode an image no larger than the display needs, with its orientation applied.
    private static func loadImage(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }
}
