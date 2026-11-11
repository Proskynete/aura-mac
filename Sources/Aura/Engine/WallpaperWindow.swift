import AppKit
import AVFoundation
import QuartzCore
import AuraCore

/// Ventana sin bordes que vive en el nivel del escritorio: por encima del
/// fondo de macOS y por debajo de los íconos del escritorio y de todas las apps.
final class WallpaperWindow: NSWindow {
    let displayKey: String

    init(display: DisplayInfo) {
        displayKey = display.id
        super.init(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        contentView = WallpaperView(frame: CGRect(origin: .zero, size: display.frame.size))
        setFrame(display.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var wallpaperView: WallpaperView { contentView as! WallpaperView }
}

/// Vista con capas: una AVPlayerLayer para video o una capa de imagen.
final class WallpaperView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layerContentsRedrawPolicy = .never

        for l in [imageLayer, playerLayer] as [CALayer] {
            l.frame = bounds
            l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            l.isHidden = true
            layer?.addSublayer(l)
        }
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func setScaling(_ mode: ScalingMode) {
        switch mode {
        case .fit:
            playerLayer.videoGravity = .resizeAspect
            imageLayer.contentsGravity = .resizeAspect
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
            imageLayer.contentsGravity = .resizeAspectFill
        case .stretch:
            playerLayer.videoGravity = .resize
            imageLayer.contentsGravity = .resize
        }
    }

    private func crossfade() {
        let t = CATransition()
        t.type = .fade
        t.duration = 0.6
        layer?.add(t, forKey: "aura.fade")
    }

    func show(player: AVPlayer, animated: Bool) {
        if animated { crossfade() }
        playerLayer.player = player
        playerLayer.isHidden = false
        imageLayer.isHidden = true
        imageLayer.contents = nil
    }

    func show(image: CGImage, animated: Bool) {
        if animated { crossfade() }
        imageLayer.contents = image
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.isHidden = false
        playerLayer.isHidden = true
        playerLayer.player = nil
    }

    func clear() {
        crossfade()
        playerLayer.player = nil
        playerLayer.isHidden = true
        imageLayer.contents = nil
        imageLayer.isHidden = true
    }
}
