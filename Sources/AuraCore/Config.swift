import Foundation

// MARK: - Enums de configuración (mismos nombres y valores que el Aura original)

public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    /// Claro u oscuro según la luminancia del fondo.
    case auto
    case dark
    case light
    /// No tocar la apariencia del sistema.
    case manual
}

public enum SwitcherStyle: String, Codable, CaseIterable, Sendable {
    case classic
    case cinematic
    case honeycomb
}

public enum SwitcherPosition: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right, center
}

/// Cuánto debe taparse una pantalla para pausar el fondo automáticamente.
public enum AutoPauseMode: String, Codable, CaseIterable, Sendable {
    /// Solo con la pantalla completamente cubierta (apps a pantalla completa).
    case full
    /// Ventanas maximizadas o a pantalla completa.
    case maximized
    /// Ventanas que cubren al menos un cuarto de la pantalla (por defecto).
    case partial
    /// Cualquier ventana visible.
    case anyWindow = "any_window"

    /// `coverage` es la fracción cubierta de la pantalla (0…1).
    public func shouldPause(coverage: Double) -> Bool {
        let c = min(max(coverage, 0), 1)
        switch self {
        case .full: return c >= 0.95
        // La barra de menú y el Dock quedan visibles con una ventana "maximizada".
        case .maximized: return c >= 0.85
        case .partial: return c >= 0.25
        case .anyWindow: return c > 0.01
        }
    }
}

public enum RotationMediaFilter: String, Codable, CaseIterable, Sendable {
    case all, live, `static`
}

public enum RotationOrder: String, Codable, CaseIterable, Sendable {
    case random, sequential
}

/// Cómo se ajusta el fondo a cada pantalla.
public enum ScalingMode: String, Codable, CaseIterable, Sendable {
    case fit, fill, stretch
}

public enum LibrarySort: String, Codable, CaseIterable, Sendable {
    case newest, oldest, name, size
}

/// Qué hace el clic izquierdo en el ícono de la barra de menú.
public enum TrayClickAction: String, Codable, CaseIterable, Sendable {
    case menu
    case switcher
    case mainWindow = "main_window"
}

// MARK: - Configuración

/// Configuración persistente, guardada en ~/Library/Application Support/Aura/config.json.
/// Todos los campos se decodifican con valor por defecto para que agregar
/// opciones nuevas nunca invalide una configuración existente.
public struct AuraConfig: Codable, Equatable, Sendable {
    public static let currentVersion = "1.0.0"

    public var version: String = AuraConfig.currentVersion

    /// Fondo aplicado a todas las pantallas (`output == "*"`).
    public var current: String? = nil
    /// Fondos por pantalla: UUID de pantalla → ruta.
    public var wallpapers: [String: String] = [:]
    /// Pantalla destino al aplicar desde la biblioteca: "*" o UUID.
    public var output: String = "*"
    /// Ajuste por pantalla: UUID → modo. "*" es el valor general.
    public var scaling: [String: ScalingMode] = [:]

    public var dirs: [String] = AuraPaths.defaultLibraryDirs()
    public var favorites: [String] = []
    public var librarySort: LibrarySort = .newest

    // Apariencia
    /// Apagado por defecto: cambia el modo claro/oscuro de todo macOS y pide
    /// permiso para controlar "Eventos del Sistema". El usuario lo activa en Ajustes.
    public var autoTheme: Bool = false
    public var themeMode: ThemeMode = .auto
    /// Aproxima el color de acento de macOS al color dominante del fondo.
    public var systemAccent: Bool = false
    /// Usa un fotograma del fondo como fondo de escritorio de macOS
    /// (se ve en Mission Control, en el cambio de escritorios y al bloquear).
    public var syncSystemWallpaper: Bool = true

    // Rotación
    public var rotation: Bool = false
    /// Minutos entre cambios.
    public var interval: Int = 30
    public var order: RotationOrder = .random
    public var seqIndex: Int = 0
    public var rotationOnlyFavorites: Bool = false
    public var rotationMediaFilter: RotationMediaFilter = .all

    // Audio
    public var mute: Bool = true
    /// 0…100
    public var volume: Int = 100

    // Rendimiento
    /// Pausa cuando hay ventanas tapando el fondo (según `autoPauseMode`).
    public var autoPause: Bool = true
    public var autoPauseMode: AutoPauseMode = .partial
    /// Pausa con apps a pantalla completa o juegos.
    public var smartPause: Bool = true
    public var pauseOnBattery: Bool = false
    public var pauseOnLowPower: Bool = true
    /// Convierte .webm/.mkv/.avi con ffmpeg (si está instalado) para poder reproducirlos.
    public var transcodeUnsupported: Bool = true

    // General
    public var keepRunningOnClose: Bool = true
    public var autostart: Bool = false
    public var language: AppLanguage = .auto
    public var trayClickAction: TrayClickAction = .menu

    // Selector rápido
    public var switcherOnlyFavorites: Bool = false
    public var switcherPosition: SwitcherPosition = .center
    public var switcherStyle: SwitcherStyle = .honeycomb
    /// Atajo global ⌃⌥Espacio para abrir el selector.
    public var switcherHotkey: Bool = true

    // Ventana
    public var windowWidth: Double = 1040
    public var windowHeight: Double = 700

    /// Historial de fondos aplicados (para `aura prev`).
    public var history: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, current, wallpapers, output, scaling, dirs, favorites
        case librarySort = "library_sort"
        case autoTheme = "auto_theme"
        case themeMode = "theme_mode"
        case systemAccent = "system_accent"
        case syncSystemWallpaper = "sync_system_wallpaper"
        case rotation, interval, order
        case seqIndex = "seq_index"
        case rotationOnlyFavorites = "rotation_only_favorites"
        case rotationMediaFilter = "rotation_media_filter"
        case mute, volume
        case autoPause = "auto_pause"
        case autoPauseMode = "auto_pause_mode"
        case smartPause = "smart_pause"
        case pauseOnBattery = "pause_on_battery"
        case pauseOnLowPower = "pause_on_low_power"
        case transcodeUnsupported = "transcode_unsupported"
        case keepRunningOnClose = "keep_running_on_close"
        case autostart, language
        case trayClickAction = "tray_click_action"
        case switcherOnlyFavorites = "switcher_only_favorites"
        case switcherPosition = "switcher_position"
        case switcherStyle = "switcher_style"
        case switcherHotkey = "switcher_hotkey"
        case windowWidth = "window_width"
        case windowHeight = "window_height"
        case history
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T {
            // Un valor inválido (p. ej. un enum desconocido) cae al valor por defecto
            // en vez de descartar toda la configuración.
            let decoded: T?? = try? c.decodeIfPresent(T.self, forKey: key)
            return (decoded ?? nil) ?? current
        }
        version = v(.version, version)
        current = v(.current, current)
        wallpapers = v(.wallpapers, wallpapers)
        output = v(.output, output)
        scaling = v(.scaling, scaling)
        dirs = v(.dirs, dirs)
        favorites = v(.favorites, favorites)
        librarySort = v(.librarySort, librarySort)
        autoTheme = v(.autoTheme, autoTheme)
        themeMode = v(.themeMode, themeMode)
        systemAccent = v(.systemAccent, systemAccent)
        syncSystemWallpaper = v(.syncSystemWallpaper, syncSystemWallpaper)
        rotation = v(.rotation, rotation)
        interval = max(1, v(.interval, interval))
        order = v(.order, order)
        seqIndex = v(.seqIndex, seqIndex)
        rotationOnlyFavorites = v(.rotationOnlyFavorites, rotationOnlyFavorites)
        rotationMediaFilter = v(.rotationMediaFilter, rotationMediaFilter)
        mute = v(.mute, mute)
        volume = min(100, max(0, v(.volume, volume)))
        autoPause = v(.autoPause, autoPause)
        autoPauseMode = v(.autoPauseMode, autoPauseMode)
        smartPause = v(.smartPause, smartPause)
        pauseOnBattery = v(.pauseOnBattery, pauseOnBattery)
        pauseOnLowPower = v(.pauseOnLowPower, pauseOnLowPower)
        transcodeUnsupported = v(.transcodeUnsupported, transcodeUnsupported)
        keepRunningOnClose = v(.keepRunningOnClose, keepRunningOnClose)
        autostart = v(.autostart, autostart)
        language = v(.language, language)
        trayClickAction = v(.trayClickAction, trayClickAction)
        switcherOnlyFavorites = v(.switcherOnlyFavorites, switcherOnlyFavorites)
        switcherPosition = v(.switcherPosition, switcherPosition)
        switcherStyle = v(.switcherStyle, switcherStyle)
        switcherHotkey = v(.switcherHotkey, switcherHotkey)
        windowWidth = v(.windowWidth, windowWidth)
        windowHeight = v(.windowHeight, windowHeight)
        history = v(.history, history)
    }

    /// Modo de ajuste para una pantalla (cae al valor general "*" y luego a Fill).
    public func scaling(for displayID: String) -> ScalingMode {
        scaling[displayID] ?? scaling["*"] ?? .fill
    }

    /// Fondo que corresponde a una pantalla.
    public func wallpaper(for displayID: String) -> String? {
        wallpapers[displayID] ?? current
    }

    public mutating func pushHistory(_ path: String) {
        history.removeAll { $0 == path }
        history.append(path)
        if history.count > 50 { history.removeFirst(history.count - 50) }
    }
}

// MARK: - Carga y guardado

public enum ConfigStore {
    public static func load() -> AuraConfig {
        let url = AuraPaths.configFile
        guard let data = try? Data(contentsOf: url) else { return AuraConfig() }
        do {
            return try JSONDecoder().decode(AuraConfig.self, from: data)
        } catch {
            // Conserva el archivo dañado para que el usuario no pierda sus ajustes.
            let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return AuraConfig()
        }
    }

    public static func save(_ config: AuraConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? AuraPaths.atomicWrite(data, to: AuraPaths.configFile)
        }
    }
}
