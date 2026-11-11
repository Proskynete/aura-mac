import AppKit
import AVFoundation
import ImageIO
import AuraCore

/// Motor de fondos: una ventana de escritorio por pantalla y un reproductor
/// por archivo de video. Si dos pantallas muestran el mismo video comparten
/// el reproductor, así se decodifica una sola vez y el audio no se duplica.
@MainActor
final class WallpaperEngine {
    struct Assignment: Equatable {
        let path: String
        let playableURL: URL
        let kind: MediaKind
    }

    private final class PlayerEntry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        var observation: NSKeyValueObservation?

        init(player: AVQueuePlayer, looper: AVPlayerLooper) {
            self.player = player
            self.looper = looper
        }
    }

    private var windows: [String: WallpaperWindow] = [:]
    private var assignments: [String: Assignment] = [:]
    private var players: [String: PlayerEntry] = [:]
    private var occlusionObservers: [String: NSObjectProtocol] = [:]
    private var displays: [DisplayInfo] = []
    /// Ventanas cuyo estado de oclusión ya se informó como visible al menos una vez.
    /// Hasta entonces no se confía en `occlusionState` (evita pausas falsas).
    private var occlusionTrusted: Set<String> = []

    /// Pausa general (usuario, batería, bloqueo de pantalla…).
    var globalPaused = false { didSet { updatePlayback() } }
    /// Pantallas tapadas por ventanas o apps a pantalla completa.
    var pausedDisplays: Set<String> = [] { didSet { if oldValue != pausedDisplays { updatePlayback() } } }

    var volume: Float = 1 { didSet { applyAudio() } }
    var muted: Bool = true { didSet { applyAudio() } }

    var onError: ((String) -> Void)?
    var onOcclusionChange: (() -> Void)?

    // MARK: Pantallas

    func syncDisplays(_ newDisplays: [DisplayInfo], scaling: (String) -> ScalingMode) {
        displays = newDisplays
        let ids = Set(newDisplays.map(\.id))

        for (id, window) in windows where !ids.contains(id) {
            window.orderOut(nil)
            window.close()
            windows[id] = nil
            assignments[id] = nil
            if let obs = occlusionObservers.removeValue(forKey: id) {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        for display in newDisplays {
            if let window = windows[display.id] {
                if window.frame != display.frame { window.setFrame(display.frame, display: true) }
            } else {
                let window = WallpaperWindow(display: display)
                windows[display.id] = window
                occlusionObservers[display.id] = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self, id = display.id] note in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let w = note.object as? NSWindow, w.occlusionState.contains(.visible) {
                            self.occlusionTrusted.insert(id)
                        }
                        self.onOcclusionChange?()
                    }
                }
            }
            windows[display.id]?.wallpaperView.setScaling(scaling(display.id))
        }
        collectUnusedPlayers()
        updatePlayback()
    }

    func assignment(for displayID: String) -> Assignment? { assignments[displayID] }

    /// La ventana de esa pantalla se ve (no está en un espacio de pantalla completa
    /// ni totalmente cubierta).
    func isVisible(_ displayID: String) -> Bool {
        guard let w = windows[displayID], w.isVisible, assignments[displayID] != nil else { return true }
        guard occlusionTrusted.contains(displayID) else { return true }
        return w.occlusionState.contains(.visible)
    }

    // MARK: Aplicar

    func show(_ assignment: Assignment, on displayIDs: [String], scaling: (String) -> ScalingMode, animated: Bool = true) {
        for id in displayIDs {
            guard let window = windows[id] else { continue }
            if assignments[id] == assignment {
                window.wallpaperView.setScaling(scaling(id))
                continue
            }
            assignments[id] = assignment
            let view = window.wallpaperView
            view.setScaling(scaling(id))
            switch assignment.kind {
            case .video:
                let entry = playerEntry(for: assignment)
                view.show(player: entry.player, animated: animated)
            case .image:
                let maxPixels = displays.first { $0.id == id }.map { max($0.pixelWidth, $0.pixelHeight) } ?? 5120
                if let image = Self.loadImage(assignment.playableURL, maxPixelSize: maxPixels) {
                    view.show(image: image, animated: animated)
                } else {
                    onError?(tr("No se pudo abrir la imagen \(assignment.playableURL.lastPathComponent).",
                                "Could not open the image \(assignment.playableURL.lastPathComponent)."))
                }
            }
            window.orderFrontRegardless()
        }
        collectUnusedPlayers()
        updatePlayback()
        applyAudio()
    }

    func setScaling(_ mode: ScalingMode, for displayID: String) {
        windows[displayID]?.wallpaperView.setScaling(mode)
    }

    func clear(_ displayIDs: [String]? = nil) {
        let targets = displayIDs ?? Array(windows.keys)
        for id in targets {
            assignments[id] = nil
            windows[id]?.wallpaperView.clear()
            windows[id]?.orderOut(nil)
        }
        collectUnusedPlayers()
    }

    /// Ruta del fondo de cada pantalla.
    func currentAssignmentPaths() -> [String: String] {
        assignments.mapValues(\.path)
    }

    // MARK: Reproducción

    private func playerEntry(for a: Assignment) -> PlayerEntry {
        if let existing = players[a.path] { return existing }
        let item = AVPlayerItem(asset: AVURLAsset(url: a.playableURL))
        item.preferredForwardBufferDuration = 2
        let player = AVQueuePlayer()
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let entry = PlayerEntry(player: player, looper: looper)
        let name = a.playableURL.lastPathComponent
        entry.observation = looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            let reason = looper.error?.localizedDescription ?? ""
            Task { @MainActor in
                self?.onError?(tr("No se pudo reproducir \(name). \(reason)", "Could not play \(name). \(reason)"))
            }
        }
        players[a.path] = entry
        return entry
    }

    private func collectUnusedPlayers() {
        let inUse = Set(assignments.values.filter { $0.kind == .video }.map(\.path))
        for (path, entry) in players where !inUse.contains(path) {
            entry.player.pause()
            entry.looper.disableLooping()
            entry.player.removeAllItems()
            entry.observation = nil
            players[path] = nil
        }
    }

    func updatePlayback() {
        for (path, entry) in players {
            let screens = assignments.filter { $0.value.path == path }.map { $0.key }
            let shouldPlay = !globalPaused && screens.contains { !pausedDisplays.contains($0) }
            if shouldPlay {
                if entry.player.timeControlStatus != .playing { entry.player.play() }
            } else if entry.player.timeControlStatus != .paused {
                entry.player.pause()
            }
        }
    }

    /// Solo suena el video de la pantalla principal (o el primero que haya).
    private func applyAudio() {
        let mainID = displays.first(where: \.isMain)?.id
        let audioPath = mainID.flatMap { assignments[$0]?.path } ?? players.keys.sorted().first
        for (path, entry) in players {
            entry.player.volume = volume
            entry.player.isMuted = muted || path != audioPath
        }
    }

    var isAnyVideoPlaying: Bool {
        players.values.contains { $0.player.timeControlStatus == .playing }
    }

    var hasVideo: Bool { !players.isEmpty }

    // MARK: Imágenes

    /// Decodifica la imagen ya reducida al tamaño de la pantalla para no gastar
    /// memoria con fotos de 8K en monitores 1080p.
    nonisolated static func loadImage(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
