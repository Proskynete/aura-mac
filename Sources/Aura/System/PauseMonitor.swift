import AppKit
import IOKit.ps
import AuraCore

/// Motivos por los que el fondo puede estar en pausa.
enum PauseReason: String, CaseIterable {
    case user
    case battery
    case lowPower = "low_power"
    case screenSleep = "screen_sleep"
    case locked
    case sessionInactive = "session_inactive"

    var label: String {
        switch self {
        case .user: return tr("pausado por ti", "paused by you")
        case .battery: return tr("usando batería", "on battery")
        case .lowPower: return tr("modo de bajo consumo", "Low Power Mode")
        case .screenSleep: return tr("pantalla en reposo", "display asleep")
        case .locked: return tr("sesión bloqueada", "screen locked")
        case .sessionInactive: return tr("otro usuario activo", "another user is active")
        }
    }
}

/// Observa energía, bloqueo/reposo y la cobertura de ventanas sobre cada
/// pantalla. No necesita permisos: CGWindowList entrega la posición de las
/// ventanas sin pedir grabación de pantalla.
@MainActor
final class PauseMonitor {
    struct Settings {
        var autoPause: Bool
        var mode: AutoPauseMode
        var smartPause: Bool
        var pauseOnBattery: Bool
        var pauseOnLowPower: Bool
    }

    var settings: Settings
    /// Motivos globales activos (sin contar `.user`, que maneja el modelo).
    private(set) var systemReasons: Set<PauseReason> = []
    /// Pantallas tapadas.
    private(set) var coveredDisplays: Set<String> = []
    private(set) var onBattery = false

    var displays: () -> [DisplayInfo] = { [] }
    /// La ventana de fondo de una pantalla está visible (no en un espacio a pantalla completa).
    var isWallpaperVisible: (String) -> Bool = { _ in true }
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var tick = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        let local = NotificationCenter.default

        func on(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { block() }
            }
            observers.append((center, token))
        }

        on(ws, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.set(.screenSleep, true) }
        on(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.set(.screenSleep, false) }
        on(ws, NSWorkspace.willSleepNotification) { [weak self] in self?.set(.screenSleep, true) }
        on(ws, NSWorkspace.didWakeNotification) { [weak self] in self?.set(.screenSleep, false) }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.set(.sessionInactive, true) }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.set(.sessionInactive, false) }
        on(dist, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.set(.locked, true) }
        on(dist, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.set(.locked, false) }
        on(local, Notification.Name.NSProcessInfoPowerStateDidChange) { [weak self] in self?.refreshPower() }
        // Cambios de app o de escritorio: recalcula la cobertura al instante.
        on(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.refreshCoverage() }
        on(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.refreshCoverage() }

        refreshPower()
        refreshCoverage()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                self.refreshCoverage()
                if self.tick % 5 == 0 { self.refreshPower() }
            }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func set(_ reason: PauseReason, _ active: Bool) {
        let before = systemReasons
        if active { systemReasons.insert(reason) } else { systemReasons.remove(reason) }
        if before != systemReasons { onChange?() }
    }

    func refreshPower() {
        onBattery = Self.isOnBattery()
        let before = systemReasons
        if settings.pauseOnBattery && onBattery { systemReasons.insert(.battery) } else { systemReasons.remove(.battery) }
        if settings.pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled {
            systemReasons.insert(.lowPower)
        } else {
            systemReasons.remove(.lowPower)
        }
        if before != systemReasons { onChange?() }
    }

    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    // MARK: Cobertura de ventanas

    func refreshCoverage() {
        var covered = Set<String>()
        let screens = displays()
        let needCoverage = settings.autoPause || settings.smartPause
        let rects = needCoverage ? visibleWindowRects() : []

        for d in screens {
            // Espacio a pantalla completa en esa pantalla: nuestra ventana no se ve.
            if settings.smartPause && !isWallpaperVisible(d.id) {
                covered.insert(d.id)
                continue
            }
            guard needCoverage else { continue }
            let c = Self.coverage(of: d.cgBounds, by: rects)
            if settings.smartPause && c >= 0.95 { covered.insert(d.id); continue }
            if settings.autoPause && settings.mode.shouldPause(coverage: c) { covered.insert(d.id) }
        }
        if covered != coveredDisplays {
            coveredDisplays = covered
            onChange?()
        }
    }

    /// Rectángulos (coordenadas Quartz) de ventanas normales visibles de otras apps.
    private func visibleWindowRects() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var rects: [CGRect] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 80, rect.height > 80 else { continue }
            rects.append(rect)
        }
        return rects
    }

    /// Fracción de la pantalla cubierta por la unión de ventanas (muestreo en rejilla).
    static func coverage(of screen: CGRect, by rects: [CGRect]) -> Double {
        let relevant = rects.compactMap { r -> CGRect? in
            let i = r.intersection(screen)
            return i.isNull || i.isEmpty ? nil : i
        }
        guard !relevant.isEmpty else { return 0 }
        let cols = 48, rows = 30
        var hits = 0
        for row in 0..<rows {
            let y = screen.minY + (CGFloat(row) + 0.5) * screen.height / CGFloat(rows)
            for col in 0..<cols {
                let x = screen.minX + (CGFloat(col) + 0.5) * screen.width / CGFloat(cols)
                let p = CGPoint(x: x, y: y)
                if relevant.contains(where: { $0.contains(p) }) { hits += 1 }
            }
        }
        return Double(hits) / Double(cols * rows)
    }
}
