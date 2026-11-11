import AppKit
import AuraCore

// `aura` — controla Aura desde la terminal o desde atajos de teclado.
// Se comunica con la app por notificaciones distribuidas; si la app no está
// abierta, la inicia en segundo plano y reintenta.

func printErr(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

@MainActor
func printHelp() {
    print(tr("""
    Aura para macOS — fondos animados

    Uso: aura <comando> [argumentos]

      (sin comando)          Abre la ventana de Aura
      next                   Cambia al siguiente fondo
      prev                   Vuelve al fondo anterior
      toggle-pause | pause   Pausa o reanuda la reproducción
      resume                 Reanuda la reproducción
      apply <archivo> [pantalla]
                             Aplica un video o imagen (a todas o a una pantalla)
      stop                   Detiene el fondo animado
      switcher               Abre el selector rápido
      volume <0-100>         Cambia el volumen
      mute                   Silencia o activa el sonido
      mode <auto|dark|light|manual>
                             Modo de tema según el fondo
      status [--json]        Muestra el estado actual
      rescan                 Vuelve a leer las carpetas de la biblioteca
      displays               Lista las pantallas conectadas
      quit                   Cierra Aura
      --version              Muestra la versión
      help                   Muestra esta ayuda
    """, """
    Aura for macOS — live wallpapers

    Usage: aura <command> [arguments]

      (no command)           Open the Aura window
      next                   Switch to the next wallpaper
      prev                   Go back to the previous wallpaper
      toggle-pause | pause   Pause or resume playback
      resume                 Resume playback
      apply <file> [display] Apply a video or image (to all or one display)
      stop                   Stop the live wallpaper
      switcher               Open the quick switcher
      volume <0-100>         Set the volume
      mute                   Toggle mute
      mode <auto|dark|light|manual>
                             Theme mode based on the wallpaper
      status [--json]        Show the current status
      rescan                 Rescan the library folders
      displays               List connected displays
      quit                   Quit Aura
      --version              Print the version
      help                   Show this help
    """))
}

@MainActor
func appIsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: AuraPaths.bundleIdentifier).isEmpty
}

/// Aura.app que contiene a este comando (…/Aura.app/Contents/Helpers/aura).
/// Funciona aunque `aura` sea un enlace simbólico, como en Homebrew.
func bundledAppURL() -> URL? {
    guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app",
          FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/Aura").path) else { return nil }
    return app
}

/// Abre la app (en segundo plano si `hidden`).
@MainActor
func launchApp(hidden: Bool) -> Bool {
    guard let url = bundledAppURL()
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: AuraPaths.bundleIdentifier) else {
        printErr(tr("No se encontró Aura.app. Instálala con ./scripts/install.sh o brew install.",
                    "Aura.app was not found. Install it with ./scripts/install.sh or brew install."))
        return false
    }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = !hidden
    if hidden { cfg.arguments = ["--daemon"] }
    let done = Box<Bool?>(nil)
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
        if let error { printErr(error.localizedDescription) }
        done.value = (error == nil)
    }
    // Hace girar el run loop mientras macOS abre la app.
    let deadline = Date().addingTimeInterval(10)
    while done.value == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return done.value ?? false
}

/// Envía un comando y espera la respuesta.
@MainActor
func send(_ cmd: IPCCommand, _ arg: String? = nil, timeout: TimeInterval = 3) -> (ok: Bool, message: String)? {
    let rid = UUID().uuidString
    let result = Box<(Bool, String)?>(nil)
    let center = DistributedNotificationCenter.default()
    let token = center.addObserver(forName: IPC.replyName, object: nil, queue: nil) { note in
        guard let info = note.userInfo, info[IPC.Key.replyID] as? String == rid else { return }
        result.value = ((info[IPC.Key.ok] as? String) == "1", info[IPC.Key.message] as? String ?? "")
    }
    defer { center.removeObserver(token) }

    var info: [String: String] = [IPC.Key.command: cmd.rawValue, IPC.Key.replyID: rid]
    if let arg { info[IPC.Key.argument] = arg }
    center.postNotificationName(IPC.commandName, object: nil, userInfo: info, deliverImmediately: true)

    let deadline = Date().addingTimeInterval(timeout)
    while result.value == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return result.value.map { (ok: $0.0, message: $0.1) }
}

/// Asegura que la app esté corriendo y responda.
@MainActor
func ensureRunning() -> Bool {
    if appIsRunning(), send(.ping, timeout: 1.5) != nil { return true }
    guard launchApp(hidden: true) else { return false }
    for _ in 0..<40 {
        if send(.ping, timeout: 0.5) != nil { return true }
    }
    printErr(tr("Aura no respondió.", "Aura did not respond."))
    return false
}

@MainActor
func run(_ cmd: IPCCommand, _ arg: String? = nil, quiet: Bool = false) -> Int32 {
    guard ensureRunning() else { return 1 }
    guard let reply = send(cmd, arg, timeout: 5) else {
        printErr(tr("Sin respuesta de Aura.", "No response from Aura."))
        return 1
    }
    if !reply.message.isEmpty && !quiet {
        if reply.ok { print(reply.message) } else { printErr(reply.message) }
    }
    return reply.ok ? 0 : 1
}

@MainActor
func printStatus(json: Bool) -> Int32 {
    let running = appIsRunning()
    var status: AuraStatus?
    if running, let reply = send(.status, timeout: 2), reply.ok,
       let data = reply.message.data(using: .utf8) {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        status = try? dec.decode(AuraStatus.self, from: data)
    }
    if status == nil { status = AuraStatus.load() }
    if !running { status?.running = false }

    if json {
        print(status?.jsonString() ?? "{\"running\": false}")
        return 0
    }
    guard let s = status else {
        print(tr("Aura no está en ejecución.", "Aura is not running."))
        return 0
    }
    let yes = tr("sí", "yes"), no = tr("no", "no")
    print("Aura \(AuraConfig.currentVersion)")
    print(tr("  En ejecución: ", "  Running:      ") + (s.running ? yes : no))
    let paused = s.paused ? (tr("en pausa", "paused") + (s.pauseReasons.isEmpty ? "" : " (\(s.pauseReasons.joined(separator: ", ")))")) : tr("reproduciendo", "playing")
    print(tr("  Estado:       ", "  State:        ") + paused)
    print(tr("  Fondo:        ", "  Wallpaper:    ") + (s.current ?? "—"))
    print(tr("  Volumen:      ", "  Volume:       ") + "\(s.volume)%" + (s.muted ? tr(" (silenciado)", " (muted)") : ""))
    print(tr("  Rotación:     ", "  Rotation:     ") + (s.rotation ? tr("cada \(s.rotationInterval) min", "every \(s.rotationInterval) min") : no))
    print(tr("  Tema:         ", "  Theme:        ") + s.themeMode)
    print(tr("  Biblioteca:   ", "  Library:      ") + tr("\(s.libraryCount) fondos", "\(s.libraryCount) wallpapers"))
    for d in s.displays {
        let name = (d.wallpaper as NSString?)?.lastPathComponent ?? "—"
        print("  • \(d.name) [\(d.resolution), \(d.scaling)] \(name)\(d.playing ? " ▶︎" : "")")
    }
    return 0
}

// MARK: - Entrada

@main
enum AuraCLI {
    @MainActor
    static func main() {
        Localizer.current = ConfigStore.load().language

        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first?.lowercased() ?? "gui"
        if !args.isEmpty { args.removeFirst() }

        let code: Int32
        switch command {
        case "gui", "show", "open":
            if appIsRunning() {
                code = run(.show, quiet: true)
            } else {
                code = launchApp(hidden: false) ? 0 : 1
            }
        case "--daemon", "-d", "--hidden", "start":
            code = appIsRunning() ? 0 : (launchApp(hidden: true) ? 0 : 1)
        case "next": code = run(.next)
        case "prev", "previous": code = run(.prev)
        case "toggle-pause", "pause": code = run(.togglePause)
        case "resume", "play": code = run(.resume)
        case "stop": code = run(.stop)
        case "switcher", "hud", "menu": code = run(.switcher, quiet: true)
        case "apply":
            guard let file = args.first else {
                printErr(tr("Uso: aura apply <archivo> [pantalla]", "Usage: aura apply <file> [display]"))
                exit(2)
            }
            let path = URL(fileURLWithPath: (file as NSString).expandingTildeInPath,
                           relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.path
            let target = args.count > 1 ? args[1] : ""
            code = run(.apply, target.isEmpty ? path : "\(path)\u{1F}\(target)")
        case "volume", "vol":
            guard let v = args.first else { printErr(tr("Uso: aura volume 0-100", "Usage: aura volume 0-100")); exit(2) }
            code = run(.volume, v)
        case "mute": code = run(.mute)
        case "mode", "theme-mode": code = run(.themeMode, args.first)
        case "status": code = printStatus(json: args.contains("--json"))
        case "rescan": code = run(.rescan, quiet: true)
        case "displays", "monitors":
            if appIsRunning(), let reply = send(.status, timeout: 2), let data = reply.message.data(using: .utf8) {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                if let s = try? dec.decode(AuraStatus.self, from: data) {
                    for d in s.displays { print("\(d.name)\t\(d.resolution)\t\(d.id)") }
                }
            } else {
                var ids = [CGDirectDisplayID](repeating: 0, count: 16)
                var count: UInt32 = 0
                CGGetActiveDisplayList(16, &ids, &count)
                for id in ids.prefix(Int(count)) {
                    print("\(tr("Pantalla", "Display")) \(id)\t\(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id))")
                }
            }
            code = 0
        case "quit", "exit":
            code = appIsRunning() ? run(.quit, quiet: true) : 0
        case "--version", "-v", "version":
            print("aura \(AuraConfig.currentVersion) (macOS)")
            code = 0
        case "help", "--help", "-h":
            printHelp()
            code = 0
        default:
            printErr(tr("Comando desconocido: \(command)", "Unknown command: \(command)"))
            printHelp()
            code = 2
        }
        exit(code)
    }
}
