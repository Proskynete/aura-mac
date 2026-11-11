import SwiftUI
import AppKit
import AuraCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var customInterval = ""
    @ViewState private var ffmpegAvailable = Transcoder.isAvailable

    var body: some View {
        Form {
            general
            performance
            appearance
            rotation
            switcher
            folders
            formats
        }
        .formStyle(.grouped)
        .onAppear { ffmpegAvailable = Transcoder.isAvailable }
    }

    // MARK: General

    private var general: some View {
        Section(tr("General", "General")) {
            Picker(tr("Idioma", "Language"), selection: $model.config.language) {
                Text(tr("Automático (sistema)", "Automatic (system)")).tag(AppLanguage.auto)
                Text("Español").tag(AppLanguage.es)
                Text("English").tag(AppLanguage.en)
            }
            if Self.installedWithHomebrew {
                LabeledContent(tr("Abrir Aura al iniciar sesión", "Open Aura at login")) {
                    Text("brew services start aura-macos")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            } else {
                Toggle(tr("Abrir Aura al iniciar sesión", "Open Aura at login"), isOn: $model.config.autostart)
            }
            Toggle(isOn: $model.config.keepRunningOnClose) {
                Text(tr("Seguir en la barra de menú al cerrar la ventana", "Keep running in the menu bar when the window closes"))
                Text(tr("El fondo sigue animado aunque cierres la ventana.", "The wallpaper keeps playing after you close the window."))
            }
            Picker(tr("Clic en el ícono de la barra de menú", "Menu bar icon click"), selection: $model.config.trayClickAction) {
                Text(tr("Abrir el menú", "Open the menu")).tag(TrayClickAction.menu)
                Text(tr("Abrir el selector rápido", "Open the quick switcher")).tag(TrayClickAction.switcher)
                Text(tr("Abrir la ventana", "Open the window")).tag(TrayClickAction.mainWindow)
            }
        }
    }

    /// Con Homebrew la app vive en una carpeta versionada (Cellar) que cambia al actualizar,
    /// así que el inicio con la sesión se maneja con `brew services`.
    static var installedWithHomebrew: Bool {
        Bundle.main.bundlePath.contains("/Cellar/") || Bundle.main.bundlePath.contains("/opt/aura-macos/")
    }

    // MARK: Rendimiento

    private var performance: some View {
        Section {
            Toggle(isOn: $model.config.smartPause) {
                Text(tr("Pausa inteligente", "Smart pause"))
                Text(tr("Pausa con apps y juegos a pantalla completa (0 % de GPU).",
                        "Pauses with full-screen apps and games (0% GPU)."))
            }
            Toggle(isOn: $model.config.autoPause) {
                Text(tr("Pausar cuando hay ventanas encima", "Pause when windows cover it"))
                Text(tr("Cada pantalla se pausa por separado.", "Each display pauses independently."))
            }
            if model.config.autoPause {
                Picker(tr("Sensibilidad", "Sensitivity"), selection: $model.config.autoPauseMode) {
                    Text(tr("Solo pantalla cubierta por completo", "Only when fully covered")).tag(AutoPauseMode.full)
                    Text(tr("Ventanas maximizadas", "Maximized windows")).tag(AutoPauseMode.maximized)
                    Text(tr("Ventanas que tapan ¼ de la pantalla", "Windows covering ¼ of the screen")).tag(AutoPauseMode.partial)
                    Text(tr("Cualquier ventana visible", "Any visible window")).tag(AutoPauseMode.anyWindow)
                }
            }
            Toggle(isOn: $model.config.pauseOnBattery) {
                Text(tr("Pausar con batería", "Pause on battery"))
                Text(model.pauseMonitor.onBattery ? tr("Ahora estás usando batería.", "You're on battery right now.")
                                                  : tr("Ahora estás conectado a la corriente.", "You're plugged in right now."))
            }
            Toggle(tr("Pausar en modo de bajo consumo", "Pause in Low Power Mode"), isOn: $model.config.pauseOnLowPower)
            LabeledContent(tr("Decodificación", "Decoding")) {
                Text(tr("Por hardware (VideoToolbox), automática", "Hardware (VideoToolbox), automatic"))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("Rendimiento y energía", "Performance & power"))
        } footer: {
            Text(tr("Al bloquear la pantalla o cuando entra en reposo, el fondo siempre se pausa.",
                    "The wallpaper always pauses when the screen locks or sleeps."))
        }
    }

    // MARK: Apariencia

    private var appearance: some View {
        Section {
            Toggle(isOn: $model.config.autoTheme) {
                Text(tr("Tema automático según el fondo", "Automatic theme from the wallpaper"))
                Text(tr("macOS pedirá permiso una vez para controlar \"Eventos del Sistema\".",
                        "macOS will ask once for permission to control \"System Events\"."))
            }
            if model.config.autoTheme {
                Picker(tr("Modo", "Mode"), selection: $model.config.themeMode) {
                    Text(tr("Auto (claro u oscuro según la luminancia)", "Auto (light or dark by luminance)")).tag(ThemeMode.auto)
                    Text(tr("Siempre oscuro", "Always dark")).tag(ThemeMode.dark)
                    Text(tr("Siempre claro", "Always light")).tag(ThemeMode.light)
                    Text(tr("No cambiar la apariencia", "Don't change the appearance")).tag(ThemeMode.manual)
                }
            }
            Toggle(isOn: $model.config.systemAccent) {
                Text(tr("Color de acento del sistema según el fondo", "System accent color from the wallpaper"))
                Text(tr("Aproximado: macOS solo ofrece 8 colores. Algunas apps lo toman al reabrirse.",
                        "Approximate: macOS only offers 8 colors. Some apps pick it up after relaunching."))
            }
            Toggle(isOn: $model.config.syncSystemWallpaper) {
                Text(tr("Usar un fotograma como fondo de macOS", "Use a frame as the macOS wallpaper"))
                Text(tr("Se ve en Mission Control, al cambiar de escritorio y en la pantalla de bloqueo. Se mantiene aunque desinstales Aura.",
                        "Shows in Mission Control, when switching Spaces and on the lock screen. It stays even if you uninstall Aura."))
            }
            if model.config.syncSystemWallpaper, SystemWallpaper.managedPicturePath != nil {
                Label(tr("Tu organización administra el fondo de este Mac (MDM) y puede reemplazar el de Aura.",
                         "Your organization manages this Mac's wallpaper (MDM) and may replace Aura's."),
                      systemImage: "building.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(tr("Color de acento de Aura", "Aura accent color"))
                Spacer()
                Circle().fill(model.accent).frame(width: 16, height: 16)
            }
            Button(tr("Restaurar el fondo original de macOS", "Restore the original macOS wallpaper")) {
                if SystemWallpaper.restoreOriginals() {
                    model.showToast(tr("Fondo original restaurado.", "Original wallpaper restored."), kind: .success)
                } else {
                    model.showToast(tr("No hay un fondo original guardado.", "No original wallpaper was saved."), kind: .info)
                }
            }
        } header: {
            Text(tr("Apariencia", "Appearance"))
        }
    }

    // MARK: Rotación

    private var rotation: some View {
        Section(tr("Rotación automática", "Auto rotation")) {
            Toggle(tr("Cambiar de fondo automáticamente", "Change wallpaper automatically"), isOn: $model.config.rotation)
            if model.config.rotation {
                Picker(tr("Cada", "Every"), selection: $model.config.interval) {
                    ForEach(intervalOptions, id: \.self) { m in Text(intervalLabel(m)).tag(m) }
                }
                HStack {
                    TextField(tr("Minutos personalizados", "Custom minutes"), text: $customInterval)
                        .frame(width: 160)
                        .onSubmit(applyCustomInterval)
                    Button(tr("Usar", "Use"), action: applyCustomInterval)
                        .disabled(Int(customInterval) == nil)
                }
                Picker(tr("Orden", "Order"), selection: $model.config.order) {
                    Text(tr("Aleatorio", "Random")).tag(RotationOrder.random)
                    Text(tr("En orden", "Sequential")).tag(RotationOrder.sequential)
                }
                .pickerStyle(.segmented)
                Picker(tr("Qué fondos", "Which wallpapers"), selection: $model.config.rotationOnlyFavorites) {
                    Text(tr("Toda la biblioteca", "Whole library")).tag(false)
                    Text(tr("Solo favoritos", "Favorites only")).tag(true)
                }
                .pickerStyle(.segmented)
                Picker(tr("Tipo", "Type"), selection: $model.config.rotationMediaFilter) {
                    Text(tr("Todos", "All")).tag(RotationMediaFilter.all)
                    Text(tr("Solo animados", "Live only")).tag(RotationMediaFilter.live)
                    Text(tr("Solo imágenes", "Images only")).tag(RotationMediaFilter.static)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var intervalOptions: [Int] {
        var opts = [5, 10, 15, 30, 60, 120, 240, 720, 1440]
        if !opts.contains(model.config.interval) { opts.append(model.config.interval); opts.sort() }
        return opts
    }

    private func intervalLabel(_ m: Int) -> String {
        if m < 60 { return tr("\(m) minutos", "\(m) minutes") }
        if m % 60 == 0 {
            let h = m / 60
            return h == 1 ? tr("1 hora", "1 hour") : tr("\(h) horas", "\(h) hours")
        }
        return tr("\(m) minutos", "\(m) minutes")
    }

    private func applyCustomInterval() {
        guard let v = Int(customInterval.trimmingCharacters(in: .whitespaces)), v >= 1 else { return }
        model.config.interval = v
        customInterval = ""
    }

    // MARK: Selector rápido

    private var switcher: some View {
        Section {
            Picker(tr("Estilo", "Style"), selection: $model.config.switcherStyle) {
                Text(tr("Panal", "Honeycomb")).tag(SwitcherStyle.honeycomb)
                Text(tr("Cinemático", "Cinematic")).tag(SwitcherStyle.cinematic)
                Text(tr("Clásico", "Classic")).tag(SwitcherStyle.classic)
            }
            .pickerStyle(.segmented)
            Picker(tr("Posición", "Position"), selection: $model.config.switcherPosition) {
                Text(tr("Centro", "Center")).tag(SwitcherPosition.center)
                Text(tr("Arriba", "Top")).tag(SwitcherPosition.top)
                Text(tr("Abajo", "Bottom")).tag(SwitcherPosition.bottom)
                Text(tr("Izquierda", "Left")).tag(SwitcherPosition.left)
                Text(tr("Derecha", "Right")).tag(SwitcherPosition.right)
            }
            Picker(tr("Mostrar", "Show"), selection: $model.config.switcherOnlyFavorites) {
                Text(tr("Toda la biblioteca", "Whole library")).tag(false)
                Text(tr("Solo favoritos", "Favorites only")).tag(true)
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $model.config.switcherHotkey) {
                Text(tr("Atajo global ⌃⌥Espacio", "Global shortcut ⌃⌥Space"))
                Text(tr("Abre el selector desde cualquier app.", "Opens the switcher from any app."))
            }
            HStack {
                Button(tr("Probar el selector", "Try the switcher")) { AppDelegate.shared?.toggleSwitcher() }
                Button(tr("Copiar comando", "Copy command")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("aura switcher", forType: .string)
                    model.showToast(tr("Copiado: aura switcher", "Copied: aura switcher"), kind: .success)
                }
            }
        } header: {
            Text(tr("Selector rápido", "Quick switcher"))
        } footer: {
            Text(tr("También puedes asignar \"aura next\" o \"aura switcher\" a un atajo en Atajos de macOS.",
                    "You can also bind \"aura next\" or \"aura switcher\" to a shortcut in the macOS Shortcuts app."))
        }
    }

    // MARK: Carpetas

    private var folders: some View {
        Section {
            ForEach(model.config.dirs, id: \.self) { dir in
                HStack {
                    Image(systemName: dir == AuraPaths.downloadsDir.path ? "arrow.down.circle" : "folder")
                        .foregroundStyle(.secondary)
                    Text((dir as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    if !FileManager.default.fileExists(atPath: dir) {
                        Badge(text: tr("No existe", "Missing"), tint: .orange.opacity(0.8))
                    }
                    Spacer()
                    Button { openInFinder(dir) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.borderless)
                        .help(tr("Abrir en Finder", "Open in Finder"))
                    Button { model.removeFolder(dir) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help(tr("Quitar de la biblioteca", "Remove from library"))
                }
            }
            Button(tr("Agregar carpeta…", "Add folder…")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK { panel.urls.forEach(model.addFolder) }
            }
        } header: {
            Text(tr("Carpetas de la biblioteca", "Library folders"))
        } footer: {
            Text(tr("Las descargas se guardan en \((AuraPaths.downloadsDir.path as NSString).abbreviatingWithTildeInPath).",
                    "Downloads are saved to \((AuraPaths.downloadsDir.path as NSString).abbreviatingWithTildeInPath)."))
        }
    }

    // MARK: Formatos

    private var formats: some View {
        Section {
            LabeledContent(tr("Nativos", "Native")) {
                Text("MP4, MOV, M4V · JPG, PNG, HEIC, WebP").foregroundStyle(.secondary)
            }
            Toggle(isOn: $model.config.transcodeUnsupported) {
                Text(tr("Convertir WebM, MKV y AVI", "Convert WebM, MKV and AVI"))
                Text(tr("Se convierten una vez a HEVC con el codificador por hardware y quedan en caché.",
                        "They're converted once to HEVC with the hardware encoder and cached."))
            }
            LabeledContent("ffmpeg") {
                if ffmpegAvailable {
                    Label(tr("Instalado", "Installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    HStack {
                        Text("brew install ffmpeg").font(.callout.monospaced()).textSelection(.enabled)
                        Button(tr("Comprobar", "Check")) { ffmpegAvailable = Transcoder.isAvailable }
                    }
                }
            }
            Button(tr("Vaciar caché de miniaturas y conversiones", "Clear thumbnail and conversion cache")) {
                let fm = FileManager.default
                for dir in [AuraPaths.thumbsDir, AuraPaths.transcodeDir, AuraPaths.onlineCacheDir] {
                    try? fm.removeItem(at: dir)
                    AuraPaths.ensure(dir)
                }
                model.showToast(tr("Caché vaciada.", "Cache cleared."), kind: .success)
            }
        } header: {
            Text(tr("Formatos", "Formats"))
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            Text("Aura").font(.largeTitle.weight(.bold))
            Text(tr("Versión \(AuraConfig.currentVersion) para macOS", "Version \(AuraConfig.currentVersion) for macOS"))
                .foregroundStyle(.secondary)
            Text(tr("Fondos animados nativos para macOS, escritos en Swift con AVFoundation y SwiftUI.",
                    "Native live wallpapers for macOS, written in Swift with AVFoundation and SwiftUI."))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            VStack(spacing: 6) {
                Text(tr("Port de Aura, el gestor de fondos animados para COSMIC creado por Antwny.",
                        "A port of Aura, the live wallpaper manager for COSMIC created by Antwny."))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Link(tr("Proyecto original", "Original project"), destination: URL(string: "https://github.com/antwny/aura")!)
                    Link(tr("Canal de YouTube", "YouTube channel"), destination: URL(string: "https://www.youtube.com/@antwny")!)
                }
            }
            .padding(14)
            .card()
            Text(tr("Licencia GPL-3.0-or-later, igual que el original.", "Licensed GPL-3.0-or-later, like the original."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
