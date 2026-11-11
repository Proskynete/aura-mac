import AppKit
import AuraCore

/// Recibe los comandos de `aura` (terminal o atajos de teclado) y responde.
@MainActor
final class CommandServer {
    private var token: NSObjectProtocol?

    func start() {
        token = DistributedNotificationCenter.default().addObserver(
            forName: IPC.commandName, object: nil, queue: .main
        ) { note in
            let info = note.userInfo ?? [:]
            let cmd = info[IPC.Key.command] as? String ?? ""
            let arg = info[IPC.Key.argument] as? String
            let rid = info[IPC.Key.replyID] as? String
            MainActor.assumeIsolated {
                let (ok, msg) = CommandServer.handle(cmd, arg)
                if let rid { CommandServer.reply(rid, ok: ok, message: msg) }
            }
        }
    }

    private static func reply(_ rid: String, ok: Bool, message: String) {
        DistributedNotificationCenter.default().postNotificationName(
            IPC.replyName, object: nil,
            userInfo: [IPC.Key.replyID: rid, IPC.Key.ok: ok ? "1" : "0", IPC.Key.message: message],
            deliverImmediately: true
        )
    }

    static func handle(_ raw: String, _ arg: String?) -> (Bool, String) {
        let model = AppModel.shared
        guard let cmd = IPCCommand(rawValue: raw) else {
            return (false, tr("Comando desconocido: \(raw)", "Unknown command: \(raw)"))
        }
        switch cmd {
        case .ping:
            return (true, "pong")
        case .show:
            AppDelegate.shared?.showMainWindow()
            return (true, "")
        case .switcher:
            AppDelegate.shared?.toggleSwitcher()
            return (true, "")
        case .next:
            model.next()
            return (true, model.currentPath.map { tr("Fondo: \($0)", "Wallpaper: \($0)") } ?? "")
        case .prev:
            model.prev()
            return (true, model.currentPath.map { tr("Fondo: \($0)", "Wallpaper: \($0)") } ?? "")
        case .togglePause:
            model.togglePause()
            return (true, model.userPaused ? tr("En pausa", "Paused") : tr("Reproduciendo", "Playing"))
        case .pause:
            model.setUserPaused(true)
            return (true, tr("En pausa", "Paused"))
        case .resume:
            model.setUserPaused(false)
            return (true, tr("Reproduciendo", "Playing"))
        case .stop:
            model.stop()
            return (true, tr("Fondo detenido", "Wallpaper stopped"))
        case .apply:
            guard let arg, !arg.isEmpty else { return (false, tr("Falta la ruta del archivo.", "Missing file path.")) }
            // Formato: "ruta" o "ruta\u{1F}pantalla"
            let parts = arg.components(separatedBy: "\u{1F}")
            let path = (parts[0] as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                return (false, tr("No existe: \(path)", "Not found: \(path)"))
            }
            var target = "*"
            if parts.count > 1, !parts[1].isEmpty, parts[1] != "*" {
                let wanted = parts[1].lowercased()
                guard let d = model.displays.first(where: {
                    $0.id.lowercased() == wanted || $0.name.lowercased().contains(wanted)
                }) else {
                    return (false, tr("No hay una pantalla llamada \(parts[1]).", "No display named \(parts[1])."))
                }
                target = d.id
            }
            model.apply(path: path, target: target)
            return (true, tr("Aplicado: \(path)", "Applied: \(path)"))
        case .status:
            return (true, model.status().jsonString())
        case .volume:
            guard let arg, let v = Int(arg) else { return (false, tr("Uso: aura volume 0-100", "Usage: aura volume 0-100")) }
            model.setVolume(v)
            return (true, tr("Volumen: \(model.config.volume)%", "Volume: \(model.config.volume)%"))
        case .mute:
            model.toggleMute()
            return (true, model.config.mute ? tr("Silenciado", "Muted") : tr("Con sonido", "Unmuted"))
        case .themeMode:
            guard let arg else { return (true, model.config.themeMode.rawValue) }
            let map: [String: ThemeMode] = [
                "auto": .auto, "dark": .dark, "oscuro": .dark, "light": .light, "claro": .light,
                "manual": .manual, "system": .manual, "sistema": .manual,
            ]
            guard let mode = map[arg.lowercased()] else {
                return (false, tr("Modos: auto, dark, light, manual", "Modes: auto, dark, light, manual"))
            }
            model.config.themeMode = mode
            return (true, tr("Modo de tema: \(mode.rawValue)", "Theme mode: \(mode.rawValue)"))
        case .rescan:
            model.rescan()
            return (true, "")
        case .quit:
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NSApp.terminate(nil)
            }
            return (true, "")
        }
    }
}
