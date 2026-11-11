import Foundation

/// Rutas estándar de macOS que usa Aura.
public enum AuraPaths {
    public static let bundleIdentifier = "io.github.aura.macos"

    private static var fm: FileManager { .default }

    public static var home: URL { fm.homeDirectoryForCurrentUser }

    /// ~/Library/Application Support/Aura
    public static var supportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return ensure(base.appendingPathComponent("Aura", isDirectory: true))
    }

    /// ~/Library/Caches/Aura
    public static var cacheDir: URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Caches")
        return ensure(base.appendingPathComponent("Aura", isDirectory: true))
    }

    public static var configFile: URL { supportDir.appendingPathComponent("config.json") }

    /// Estado que la app publica para `aura status` cuando no hay respuesta por IPC.
    public static var stateFile: URL { supportDir.appendingPathComponent("state.json") }

    /// Miniaturas de la biblioteca local.
    public static var thumbsDir: URL { ensure(cacheDir.appendingPathComponent("thumbs", isDirectory: true)) }

    /// Miniaturas y JSON de los catálogos online.
    public static var onlineCacheDir: URL { ensure(cacheDir.appendingPathComponent("online", isDirectory: true)) }

    /// Videos .webm/.mkv/.avi convertidos a un formato que AVFoundation reproduce.
    public static var transcodeDir: URL { ensure(cacheDir.appendingPathComponent("transcoded", isDirectory: true)) }

    /// Fotogramas usados como fondo del sistema (Mission Control, pantalla de bloqueo).
    /// Viven fuera de ~/Library/Caches (macOS puede vaciarla cuando quiera y el
    /// desinstalador la borra): así el fondo de macOS sigue funcionando aunque se
    /// elimine Aura. La carpeta es oculta, por lo que la biblioteca no la escanea.
    public static var framesDir: URL { ensure(downloadsDir.appendingPathComponent(".system-frames", isDirectory: true)) }

    /// Ubicación anterior de los fotogramas (se usaba hasta noviembre de 2026).
    public static var legacyFramesDir: URL { cacheDir.appendingPathComponent("frames", isDirectory: true) }

    /// Archivos que Aura generó para el fondo de macOS (no son el fondo "original" del usuario).
    public static func isAuraGeneratedFrame(_ path: String) -> Bool {
        path.hasPrefix(framesDir.path + "/") || path.hasPrefix(cacheDir.path + "/")
    }

    /// ~/Pictures
    public static var picturesDir: URL {
        fm.urls(for: .picturesDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Pictures")
    }

    /// ~/Movies
    public static var moviesDir: URL {
        fm.urls(for: .moviesDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Movies")
    }

    /// Carpeta visible en Finder donde se guardan las descargas: ~/Pictures/Wallpapers/Aura
    public static var downloadsDir: URL {
        ensure(picturesDir.appendingPathComponent("Wallpapers/Aura", isDirectory: true))
    }

    /// Carpetas de biblioteca por defecto: la de descargas y las carpetas de fondos que ya existan.
    public static func defaultLibraryDirs() -> [String] {
        var dirs: [String] = [downloadsDir.path]
        let candidates = [
            picturesDir.appendingPathComponent("Wallpapers"),
            picturesDir.appendingPathComponent("Wallpaper"),
            picturesDir.appendingPathComponent("Fondos"),
            moviesDir.appendingPathComponent("Wallpapers"),
            moviesDir.appendingPathComponent("Fondos"),
            home.appendingPathComponent("Wallpapers"),
        ]
        for c in candidates where fm.fileExists(atPath: c.path) {
            if !dirs.contains(c.path) { dirs.append(c.path) }
        }
        return dirs
    }

    @discardableResult
    public static func ensure(_ url: URL) -> URL {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Escritura atómica (archivo temporal + rename) para no dejar JSON a medias.
    public static func atomicWrite(_ data: Data, to url: URL) throws {
        ensure(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }
}
