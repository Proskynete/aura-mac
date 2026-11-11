import AppKit
import ServiceManagement
import AuraCore

/// Fondo de escritorio "real" de macOS. Aura lo iguala a un fotograma del
/// fondo animado para que Mission Control, el cambio de escritorios y la
/// pantalla de bloqueo se vean coherentes. Guarda el fondo original para
/// poder restaurarlo.
enum SystemWallpaper {
    private static var originalsFile: URL { AuraPaths.supportDir.appendingPathComponent("original_wallpapers.json") }

    /// Registra el fondo original de cada pantalla la primera vez.
    @MainActor
    static func rememberOriginals() {
        var originals = loadOriginals()
        var changed = false
        for screen in NSScreen.screens {
            guard let did = DisplayInfo.displayID(of: screen) else { continue }
            let key = DisplayInfo.uuid(for: did)
            if originals[key] == nil, let url = NSWorkspace.shared.desktopImageURL(for: screen),
               !AuraPaths.isAuraGeneratedFrame(url.path) {
                originals[key] = url.path
                changed = true
            }
        }
        if changed, let data = try? JSONEncoder().encode(originals) {
            try? AuraPaths.atomicWrite(data, to: originalsFile)
        }
    }

    private static func loadOriginals() -> [String: String] {
        guard let data = try? Data(contentsOf: originalsFile) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    @MainActor
    static func restoreOriginals() -> Bool {
        let originals = loadOriginals()
        var restored = false
        for screen in NSScreen.screens {
            guard let did = DisplayInfo.displayID(of: screen),
                  let path = originals[DisplayInfo.uuid(for: did)],
                  FileManager.default.fileExists(atPath: path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            restored = true
        }
        return restored
    }

    /// Fondo que la organización impone por MDM (perfil `com.apple.desktop`), si lo hay.
    /// Con esa política macOS puede volver a poner su imagen por encima de la de Aura.
    static var managedPicturePath: String? {
        let user = NSUserName()
        let candidates = [
            "/Library/Managed Preferences/\(user)/com.apple.desktop.plist",
            "/Library/Managed Preferences/com.apple.desktop.plist",
        ]
        for file in candidates {
            if let dict = NSDictionary(contentsOfFile: file),
               let path = dict["override-picture-path"] as? String, !path.isEmpty {
                return path
            }
        }
        return nil
    }

    /// Usa la imagen (o un fotograma del video) como fondo del sistema.
    /// Devuelve `false` si macOS no quedó con esa imagen en alguna pantalla.
    @discardableResult
    static func sync(path: String, kind: MediaKind, playableURL: URL, displayIDs: [String]) async -> Bool {
        let source = URL(fileURLWithPath: path)
        let imageURL: URL?
        switch kind {
        case .image:
            // macOS acepta jpg/png/heic directamente; el resto se convierte a JPEG.
            let ext = source.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff"].contains(ext) {
                imageURL = source
            } else {
                imageURL = await frameFile(for: path) {
                    WallpaperEngine.loadImage(source, maxPixelSize: 6016)
                }
            }
        case .video:
            imageURL = await frameFile(for: path) {
                await Thumbnailer.frame(of: playableURL, width: 0)
            }
        }
        guard let imageURL else {
            NSLog("Aura: no se pudo generar el fotograma para el fondo de macOS (\(source.lastPathComponent))")
            return false
        }
        return await MainActor.run {
            var allApplied = true
            for screen in NSScreen.screens {
                guard let did = DisplayInfo.displayID(of: screen),
                      displayIDs.contains(DisplayInfo.uuid(for: did)) else { continue }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true,
                    ])
                } catch {
                    NSLog("Aura: macOS rechazó el fondo en \(screen.localizedName): \(error.localizedDescription)")
                }
                if NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL != imageURL.standardizedFileURL {
                    allApplied = false
                }
            }
            pruneFrames()
            return allApplied
        }
    }

    private static func frameFile(for path: String, make: () async -> CGImage?) async -> URL? {
        // Un nombre distinto por fondo: macOS no recarga el fondo si la ruta no cambia.
        let out = AuraPaths.framesDir.appendingPathComponent("\(Thumbnailer.key(for: path)).jpg")
        let fm = FileManager.default
        if fm.fileExists(atPath: out.path) {
            // Se marca como reciente para que la limpieza no lo borre mientras se usa.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: out.path)
            return out
        }
        guard let img = await make() else { return nil }
        return Thumbnailer.write(img, to: out, quality: 0.9)
    }

    /// Los fotogramas vivían en ~/Library/Caches/Aura/frames. macOS guarda un fondo
    /// por cada escritorio (Space) y solo se puede cambiar el del escritorio visible,
    /// así que otros escritorios pueden seguir apuntando a la ruta vieja. Se mueven
    /// los archivos a la carpeta nueva y la ruta vieja queda como enlace simbólico a
    /// ella: los nombres no cambian, así que esas referencias siguen funcionando.
    static func migrateLegacyFrames() {
        let fm = FileManager.default
        let legacy = AuraPaths.legacyFramesDir
        let target = AuraPaths.framesDir
        if let dest = try? fm.destinationOfSymbolicLink(atPath: legacy.path) {
            if dest == target.path { return }
            try? fm.removeItem(at: legacy)
        } else if fm.fileExists(atPath: legacy.path) {
            let files = (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
            for f in files {
                let to = target.appendingPathComponent(f.lastPathComponent)
                if fm.fileExists(atPath: to.path) { try? fm.removeItem(at: f) } else { try? fm.moveItem(at: f, to: to) }
            }
            try? fm.removeItem(at: legacy)
        }
        AuraPaths.ensure(legacy.deletingLastPathComponent())
        do {
            try fm.createSymbolicLink(at: legacy, withDestinationURL: target)
        } catch {
            NSLog("Aura: no se pudo enlazar la carpeta antigua de fotogramas: \(error.localizedDescription)")
        }
    }

    /// Rutas de fotogramas que algún escritorio (Space) de macOS usa como fondo,
    /// según el registro de fondos de macOS 14+. Incluye escritorios no visibles.
    static func framesReferencedBySpaces() -> Set<String> {
        let index = AuraPaths.home.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: index),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
        var names = Set<String>()
        func walk(_ o: Any) {
            if let d = o as? [String: Any] { d.values.forEach(walk) }
            else if let a = o as? [Any] { a.forEach(walk) }
            else if let blob = o as? Data {
                if let inner = try? PropertyListSerialization.propertyList(from: blob, format: nil) { walk(inner) }
            } else if let s = o as? String, s.hasPrefix("file://"), let url = URL(string: s),
                      AuraPaths.isAuraGeneratedFrame(url.path) {
                names.insert(url.lastPathComponent)
            }
        }
        walk(root)
        return names
    }

    /// Conserva los 12 fotogramas más recientes y, siempre, los que macOS usa como
    /// fondo en alguna pantalla o en cualquier escritorio (Space).
    @MainActor
    private static func pruneFrames() {
        let fm = FileManager.default
        let visible = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.lastPathComponent }
        let inUse = framesReferencedBySpaces().union(visible)
        if let files = try? fm.contentsOfDirectory(at: AuraPaths.framesDir,
                                                   includingPropertiesForKeys: [.contentModificationDateKey]) {
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            for f in sorted.dropFirst(12) where !inUse.contains(f.lastPathComponent) {
                try? fm.removeItem(at: f)
            }
        }
    }
}

/// Apariencia del sistema según el fondo (equivalente al auto-tema de COSMIC).
enum Appearance {
    static var isSystemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// Cambia el modo claro/oscuro de macOS. La primera vez macOS pide permiso
    /// para que Aura controle "Eventos del Sistema".
    static func setSystemDark(_ dark: Bool) {
        guard isSystemDark != dark else { return }
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("Aura: no se pudo cambiar la apariencia: \(error)") }
        }
    }

    /// Aproxima el acento del sistema (macOS solo tiene 8 colores).
    static func setSystemAccent(_ color: RGB) {
        let accent = Palette.nearestSystemAccent(color)
        // El dominio global se escribe con `defaults` (-1 = grafito).
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "-g", "AppleAccentColor", "-int", "\(accent)"]
        try? task.run()
        task.waitUntilExit()
        // Las apps que escuchan este aviso actualizan el color al instante.
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleColorPreferencesChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleAquaColorVariantChanged"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}

/// Inicio con la sesión (ServiceManagement, macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
