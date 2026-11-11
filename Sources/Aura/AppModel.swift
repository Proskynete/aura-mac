import AppKit
import SwiftUI
import Combine
import AuraCore

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    let kind: Kind
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Estado central de Aura. Todas las vistas, el menú de la barra, el selector
/// y los comandos de terminal pasan por aquí.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var config: AuraConfig {
        didSet { if config != oldValue { scheduleSave(); configChanged(from: oldValue) } }
    }
    @Published private(set) var library: [WallpaperItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var userPaused = false
    @Published private(set) var pauseReasons: [PauseReason] = []
    @Published private(set) var coveredDisplays: Set<String> = []
    @Published private(set) var accent: Color = .accentColor
    @Published private(set) var transcoding: [String: Double] = [:]
    @Published var toast: Toast?
    @Published var selectedDisplay: String = "*"

    let engine = WallpaperEngine()
    let downloads = DownloadManager()
    private(set) lazy var pauseMonitor = PauseMonitor(settings: pauseSettings)

    private var saveWork: DispatchWorkItem?
    private var rotationTimer: Timer?
    private var toastWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var historyCursor: Int?

    private init() {
        let loaded = ConfigStore.load()
        config = loaded
        Localizer.current = loaded.language
        selectedDisplay = loaded.output
    }

    // MARK: Ciclo de vida

    func start() {
        SystemWallpaper.migrateLegacyFrames()
        SystemWallpaper.rememberOriginals()

        engine.onError = { [weak self] msg in self?.showToast(msg, kind: .error) }
        engine.onOcclusionChange = { [weak self] in self?.pauseMonitor.refreshCoverage() }
        engine.volume = Float(config.volume) / 100
        engine.muted = config.mute

        downloads.onFinished = { [weak self] item, url, apply in
            guard let self else { return }
            var action: (String, () -> Void)? = nil
            if !apply {
                action = (tr("Aplicar", "Apply"), { AppModel.shared.apply(path: url.path) })
            }
            self.showToast(tr("Descargado: \(item.title)", "Downloaded: \(item.title)"), kind: .success, action: action)
            self.rescan()
            if apply { self.apply(path: url.path) }
        }
        downloads.onFailed = { [weak self] item, msg in
            self?.showToast(tr("Falló la descarga de \(item.title): \(msg)", "Download of \(item.title) failed: \(msg)"), kind: .error)
        }

        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }

        pauseMonitor.displays = { [weak self] in self?.displays ?? [] }
        pauseMonitor.isWallpaperVisible = { [weak self] id in self?.engine.isVisible(id) ?? true }
        pauseMonitor.onChange = { [weak self] in self?.applyPauseState() }
        pauseMonitor.start()

        rescan()
        restoreWallpapers()
        restartRotation()
        if config.autostart != LoginItem.isEnabled { _ = LoginItem.set(config.autostart) }
        publishStatus()
    }

    func shutdown() {
        pauseMonitor.stop()
        saveNow()
    }

    // MARK: Pantallas

    func refreshDisplays() {
        displays = DisplayInfo.current()
        engine.syncDisplays(displays) { [config = self.config] id in config.scaling(for: id) }
        if selectedDisplay != "*" && !displays.contains(where: { $0.id == selectedDisplay }) {
            selectedDisplay = "*"
        }
        // Pantallas nuevas (y todas al abrir la app) reciben su fondo o el general.
        // También se sincroniza el fondo de macOS: si no, Mission Control y el cambio
        // de escritorio muestran el fondo que macOS tenía de antes.
        for d in displays where engine.assignment(for: d.id) == nil {
            if let path = config.wallpaper(for: d.id) { show(path: path, on: [d.id], animated: false, sync: true) }
        }
        pauseMonitor.refreshCoverage()
        publishStatus()
    }

    func displayName(_ id: String) -> String {
        if id == "*" { return tr("Todas las pantallas", "All displays") }
        return displays.first { $0.id == id }?.name ?? tr("Pantalla desconectada", "Disconnected display")
    }

    // MARK: Biblioteca

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        let dirs = config.dirs
        Task.detached(priority: .userInitiated) {
            let items = LibraryScanner.scan(dirs: dirs)
            await MainActor.run {
                self.library = items
                self.isScanning = false
                self.publishStatus()
            }
        }
    }

    var sortedLibrary: [WallpaperItem] { LibraryScanner.sorted(library, by: config.librarySort) }

    func isFavorite(_ path: String) -> Bool { config.favorites.contains(path) }

    func toggleFavorite(_ path: String) {
        if let i = config.favorites.firstIndex(of: path) { config.favorites.remove(at: i) } else { config.favorites.append(path) }
    }

    func addFolder(_ url: URL) {
        let p = url.standardizedFileURL.path
        guard !config.dirs.contains(p) else { return }
        config.dirs.append(p)
        rescan()
    }

    func removeFolder(_ path: String) {
        config.dirs.removeAll { $0 == path }
        rescan()
    }

    func moveToTrash(_ item: WallpaperItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            config.favorites.removeAll { $0 == item.path }
            if currentPaths.contains(item.path) { stop() }
            rescan()
        } catch {
            showToast(error.localizedDescription, kind: .error)
        }
    }

    /// Importa archivos arrastrados a la ventana (los copia a la carpeta de Aura).
    func importFiles(_ urls: [URL]) {
        var imported: [URL] = []
        for url in urls where MediaTypes.isSupported(url) {
            let dest = DownloadManager.uniqueDestination(AuraPaths.downloadsDir.appendingPathComponent(url.lastPathComponent))
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { imported.append(dest) }
        }
        if imported.isEmpty {
            showToast(tr("Ningún archivo compatible.", "No supported files."), kind: .error)
        } else {
            showToast(tr("\(imported.count) fondo(s) importado(s).", "\(imported.count) wallpaper(s) imported."), kind: .success)
            rescan()
            if imported.count == 1 { apply(path: imported[0].path) }
        }
    }

    // MARK: Aplicar fondos

    /// Rutas que se están mostrando ahora.
    var currentPaths: Set<String> { Set(engine.currentAssignmentPaths().values) }

    /// Fondo "actual" para la UI: el de la pantalla principal o el general.
    var currentPath: String? {
        if let main = displays.first(where: \.isMain), let p = engine.assignment(for: main.id)?.path { return p }
        return config.current ?? engine.currentAssignmentPaths().values.first
    }

    var currentItem: WallpaperItem? {
        guard let p = currentPath else { return nil }
        return library.first { $0.path == p }
    }

    /// Aplica un fondo a `target` ("*" = todas, o UUID de pantalla). Por defecto usa la pantalla elegida en la biblioteca.
    func apply(path: String, target: String? = nil, fromHistory: Bool = false) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), MediaTypes.isSupported(url) else {
            showToast(tr("No se encontró el archivo \(url.lastPathComponent).", "File not found: \(url.lastPathComponent)."), kind: .error)
            return
        }
        let target = target ?? selectedDisplay
        let ids: [String]
        if target == "*" {
            ids = displays.map(\.id)
            config.current = path
            config.wallpapers = [:]
        } else {
            ids = [target]
            config.wallpapers[target] = path
        }
        if !fromHistory {
            config.pushHistory(path)
            historyCursor = nil
        }
        userPaused = false
        show(path: path, on: ids, animated: true, sync: true)
        applyPauseState()
    }

    /// Muestra un fondo (convirtiéndolo antes si hace falta) sin tocar la configuración.
    private func show(path: String, on ids: [String], animated: Bool, sync: Bool) {
        let url = URL(fileURLWithPath: path)
        guard let kind = MediaTypes.kind(of: url) else { return }
        if kind == .video && MediaTypes.needsTranscode(url) {
            if let playable = Transcoder.playableURL(for: url) {
                finishShow(path: path, playable: playable, kind: kind, ids: ids, animated: animated, sync: sync)
            } else {
                transcodeThenShow(url: url, ids: ids, sync: sync)
            }
            return
        }
        finishShow(path: path, playable: url, kind: kind, ids: ids, animated: animated, sync: sync)
    }

    private func finishShow(path: String, playable: URL, kind: MediaKind, ids: [String], animated: Bool, sync: Bool) {
        engine.show(.init(path: path, playableURL: playable, kind: kind), on: ids,
                    scaling: { [config = self.config] id in config.scaling(for: id) }, animated: animated)
        publishStatus()
        guard sync else { return }
        let cfg = config
        Task.detached(priority: .utility) {
            if cfg.syncSystemWallpaper {
                let applied = await SystemWallpaper.sync(path: path, kind: kind, playableURL: playable, displayIDs: ids)
                if !applied { await self.warnSystemWallpaperBlocked() }
            }
            if cfg.autoTheme || cfg.systemAccent {
                await self.applyAutoTheme(for: path, config: cfg)
            }
        }
    }

    private func transcodeThenShow(url: URL, ids: [String], sync: Bool) {
        guard config.transcodeUnsupported else {
            showToast(tr("macOS no reproduce .\(url.pathExtension) directamente. Activa la conversión en Ajustes → Rendimiento.",
                         "macOS can't play .\(url.pathExtension) natively. Enable conversion in Settings → Performance."), kind: .error)
            return
        }
        guard Transcoder.isAvailable else {
            showToast(Transcoder.Failure.missingFFmpeg.localizedDescription, kind: .error)
            return
        }
        let path = url.path
        guard transcoding[path] == nil else { return }
        transcoding[path] = 0
        showToast(tr("Convirtiendo \(url.lastPathComponent) para macOS… solo pasa la primera vez.",
                     "Converting \(url.lastPathComponent) for macOS… this only happens once."), kind: .info)
        Task {
            do {
                let out = try await Transcoder.transcode(url) { p in
                    Task { @MainActor in AppModel.shared.transcoding[path] = p }
                }
                transcoding[path] = nil
                finishShow(path: path, playable: out, kind: .video, ids: ids, animated: true, sync: sync)
            } catch {
                transcoding[path] = nil
                showToast(error.localizedDescription, kind: .error)
            }
        }
    }

    private var warnedSystemWallpaper = false

    /// macOS no aceptó el fotograma como fondo del sistema. Se avisa una vez por sesión.
    private func warnSystemWallpaperBlocked() {
        guard !warnedSystemWallpaper else { return }
        warnedSystemWallpaper = true
        if SystemWallpaper.managedPicturePath != nil {
            showToast(tr("Tu organización fija el fondo de macOS. Aura sigue animando el escritorio, pero en Mission Control o al cambiar de app puede verse el fondo de la organización.",
                         "Your organization sets the macOS wallpaper. Aura still animates the desktop, but Mission Control or app switching may show your organization's wallpaper."),
                      kind: .info)
        } else {
            showToast(tr("macOS no aceptó el fotograma como fondo del sistema.",
                         "macOS did not accept the frame as the system wallpaper."), kind: .error)
        }
    }

    private func restoreWallpapers() {
        var shown = false
        for d in displays {
            if let path = config.wallpaper(for: d.id), FileManager.default.fileExists(atPath: path) {
                show(path: path, on: [d.id], animated: false, sync: false)
                shown = true
            }
        }
        if shown { applyPauseState() }
    }

    func stop() {
        engine.clear()
        config.current = nil
        config.wallpapers = [:]
        publishStatus()
    }

    func next() {
        let pool = rotationPool(forSwitcher: false)
        var seq = config.seqIndex
        guard let item = LibraryScanner.nextInRotation(pool: pool, current: currentPath, order: config.order, seqIndex: &seq) else {
            showToast(tr("Tu biblioteca está vacía.", "Your library is empty."), kind: .info)
            return
        }
        config.seqIndex = seq
        apply(path: item.path, target: "*")
    }

    /// Vuelve al fondo anterior del historial.
    func prev() {
        let h = config.history
        guard h.count >= 2 else {
            showToast(tr("No hay un fondo anterior.", "There's no previous wallpaper."), kind: .info)
            return
        }
        let cursor = (historyCursor ?? (h.count - 1)) - 1
        guard cursor >= 0 else { return }
        historyCursor = cursor
        apply(path: h[cursor], target: "*", fromHistory: true)
    }

    // MARK: Pausa y audio

    var isPaused: Bool { userPaused || !pauseReasons.isEmpty }

    func togglePause() { setUserPaused(!userPaused) }

    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        applyPauseState()
    }

    private var pauseSettings: PauseMonitor.Settings {
        .init(autoPause: config.autoPause, mode: config.autoPauseMode, smartPause: config.smartPause,
              pauseOnBattery: config.pauseOnBattery, pauseOnLowPower: config.pauseOnLowPower)
    }

    func applyPauseState() {
        var reasons = Array(pauseMonitor.systemReasons).sorted { $0.rawValue < $1.rawValue }
        if userPaused { reasons.insert(.user, at: 0) }
        if reasons != pauseReasons { pauseReasons = reasons }
        if coveredDisplays != pauseMonitor.coveredDisplays { coveredDisplays = pauseMonitor.coveredDisplays }
        engine.globalPaused = !reasons.isEmpty
        engine.pausedDisplays = pauseMonitor.coveredDisplays
        publishStatus()
    }

    func setVolume(_ v: Int) {
        config.volume = min(100, max(0, v))
        if config.volume > 0 && config.mute { config.mute = false }
    }

    func toggleMute() { config.mute.toggle() }

    // MARK: Rotación

    func rotationPool(forSwitcher: Bool) -> [WallpaperItem] {
        let favs = Set(config.favorites)
        if forSwitcher {
            let sorted = sortedLibrary
            if config.switcherOnlyFavorites {
                let f = sorted.filter { favs.contains($0.path) }
                return f.isEmpty ? sorted : f
            }
            return sorted
        }
        return LibraryScanner.rotationPool(sortedLibrary, favorites: favs, onlyFavorites: config.rotationOnlyFavorites,
                                           filter: config.rotationMediaFilter)
    }

    func restartRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard config.rotation else { return }
        let t = Timer(timeInterval: TimeInterval(max(1, config.interval) * 60), repeats: true) { _ in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                // No cambia de fondo mientras está en pausa por el usuario o por bloqueo.
                if model.userPaused || model.pauseReasons.contains(.locked) || model.pauseReasons.contains(.screenSleep) { return }
                model.next()
            }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        rotationTimer = t
    }

    // MARK: Auto-tema

    nonisolated private func applyAutoTheme(for path: String, config cfg: AuraConfig) async {
        guard let thumb = await Thumbnailer.shared.thumbnail(for: path),
              let pixels = Thumbnailer.samplePixels(thumb),
              let palette = Palette.analyze(rgba: pixels) else { return }
        let c = palette.dominant
        await MainActor.run {
            self.accent = Color(red: c.r, green: c.g, blue: c.b)
        }
        if cfg.autoTheme {
            switch cfg.themeMode {
            case .auto: Appearance.setSystemDark(palette.isDark)
            case .dark: Appearance.setSystemDark(true)
            case .light: Appearance.setSystemDark(false)
            case .manual: break
            }
        }
        if cfg.systemAccent { Appearance.setSystemAccent(c) }
    }

    // MARK: Configuración

    private func configChanged(from old: AuraConfig) {
        if config.language != old.language { Localizer.current = config.language }
        if config.volume != old.volume { engine.volume = Float(config.volume) / 100 }
        if config.mute != old.mute { engine.muted = config.mute }
        if config.rotation != old.rotation || config.interval != old.interval { restartRotation() }
        if config.scaling != old.scaling {
            for d in displays { engine.setScaling(config.scaling(for: d.id), for: d.id) }
        }
        if config.autoPause != old.autoPause || config.autoPauseMode != old.autoPauseMode ||
            config.smartPause != old.smartPause || config.pauseOnBattery != old.pauseOnBattery ||
            config.pauseOnLowPower != old.pauseOnLowPower {
            pauseMonitor.settings = pauseSettings
            pauseMonitor.refreshPower()
            pauseMonitor.refreshCoverage()
            applyPauseState()
        }
        if config.autostart != old.autostart, let error = LoginItem.set(config.autostart) {
            showToast(tr("No se pudo cambiar el inicio automático: \(error)", "Could not change launch at login: \(error)"), kind: .error)
        }
        if config.themeMode != old.themeMode || (config.autoTheme && !old.autoTheme) {
            if let p = currentPath {
                let cfg = config
                Task.detached { await self.applyAutoTheme(for: p, config: cfg) }
            }
        }
        if config.switcherHotkey != old.switcherHotkey {
            NotificationCenter.default.post(name: .auraHotkeySettingChanged, object: nil)
        }
        publishStatus()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        ConfigStore.save(config)
    }

    func setScaling(_ mode: ScalingMode, for displayID: String) {
        if displayID == "*" {
            config.scaling = ["*": mode]
        } else {
            config.scaling[displayID] = mode
        }
    }

    // MARK: Avisos

    func showToast(_ message: String, kind: Toast.Kind = .info, action: (String, () -> Void)? = nil) {
        var t = Toast(kind: kind, message: message)
        if let action { t.actionTitle = action.0; t.action = action.1 }
        toast = t
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if self?.toast?.id == t.id { self?.toast = nil } }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (kind == .error ? 7 : 4), execute: work)
        if kind == .error { NSLog("Aura: \(message)") }
    }

    // MARK: Estado para la CLI

    func status() -> AuraStatus {
        AuraStatus(
            running: true,
            paused: isPaused,
            pauseReasons: pauseReasons.map(\.rawValue),
            current: currentPath,
            displays: displays.map { d in
                .init(id: d.id, name: d.name, resolution: d.resolutionLabel,
                      wallpaper: engine.assignment(for: d.id)?.path,
                      scaling: config.scaling(for: d.id).rawValue,
                      playing: engine.assignment(for: d.id)?.kind == .video && !isPaused && !coveredDisplays.contains(d.id))
            },
            volume: config.volume,
            muted: config.mute,
            rotation: config.rotation,
            rotationInterval: config.interval,
            themeMode: config.themeMode.rawValue,
            libraryCount: library.count,
            updated: Date()
        )
    }

    private var statusWork: DispatchWorkItem?

    func publishStatus() {
        statusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.status().save() }
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        NotificationCenter.default.post(name: .auraStateChanged, object: nil)
    }
}

extension Notification.Name {
    static let auraStateChanged = Notification.Name("aura.stateChanged")
    static let auraHotkeySettingChanged = Notification.Name("aura.hotkeySettingChanged")
}
