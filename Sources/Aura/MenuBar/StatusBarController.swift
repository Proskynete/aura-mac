import AppKit
import SwiftUI
import AuraCore

/// Ícono en la barra de menú con controles rápidos (equivale a la bandeja del original).
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        menu.delegate = self
        if let button = item.button {
            button.image = Self.icon(paused: false)
            button.imagePosition = .imageOnly
            button.toolTip = "Aura"
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observer = NotificationCenter.default.addObserver(forName: .auraStateChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
    }

    static func icon(paused: Bool) -> NSImage? {
        let name = paused ? "pause.circle" : "sparkles.tv"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Aura")
            ?? NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Aura")
        img?.isTemplate = true
        return img
    }

    private func refreshIcon() {
        let model = AppModel.shared
        item.button?.image = Self.icon(paused: model.isPaused && model.currentPath != nil)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let action = AppModel.shared.config.trayClickAction
        if isRight || action == .menu {
            showMenu()
            return
        }
        switch action {
        case .switcher: AppDelegate.shared?.toggleSwitcher()
        case .mainWindow: AppDelegate.shared?.showMainWindow()
        case .menu: showMenu()
        }
    }

    private func showMenu() {
        rebuildMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        let model = AppModel.shared
        menu.removeAllItems()

        // Encabezado: fondo actual y estado
        let title: String
        if let p = model.currentPath {
            title = (p as NSString).lastPathComponent
        } else {
            title = tr("Sin fondo animado", "No live wallpaper")
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if model.currentPath != nil {
            let state = model.isPaused
                ? tr("En pausa", "Paused") + (model.pauseReasons.isEmpty ? "" : " · " + model.pauseReasons.map(\.label).joined(separator: ", "))
                : (model.coveredDisplays.isEmpty ? tr("Reproduciendo", "Playing") : tr("Reproduciendo · pausado donde hay ventanas", "Playing · paused where windows cover it"))
            let s = NSMenuItem(title: state, action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        menu.addItem(.separator())

        add(model.userPaused ? tr("Reanudar", "Resume") : tr("Pausar", "Pause"), "p", #selector(togglePause),
            symbol: model.userPaused ? "play.fill" : "pause.fill")
        add(tr("Siguiente fondo", "Next wallpaper"), "n", #selector(nextWallpaper), symbol: "forward.fill")
        add(tr("Fondo anterior", "Previous wallpaper"), "b", #selector(prevWallpaper), symbol: "backward.fill")
        add(tr("Selector rápido…", "Quick switcher…"), "s", #selector(openSwitcher), symbol: "square.grid.3x3.fill")
        menu.addItem(.separator())

        // Volumen
        let volItem = NSMenuItem()
        let host = NSHostingView(rootView: MenuVolumeView())
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 34)
        volItem.view = host
        menu.addItem(volItem)

        // Rotación
        let rot = NSMenuItem(title: tr("Rotación automática", "Auto rotation"), action: #selector(toggleRotation), keyEquivalent: "")
        rot.target = self
        rot.state = model.config.rotation ? .on : .off
        menu.addItem(rot)
        menu.addItem(.separator())

        add(tr("Abrir Aura", "Open Aura"), "o", #selector(openMain), symbol: "macwindow")
        add(tr("Detener fondo", "Stop wallpaper"), "", #selector(stopWallpaper), symbol: "stop.fill")
        menu.addItem(.separator())
        add(tr("Salir de Aura", "Quit Aura"), "q", #selector(quit), symbol: nil)
    }

    private func add(_ title: String, _ key: String, _ action: Selector, symbol: String?) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(mi)
    }

    @objc private func togglePause() { AppModel.shared.togglePause() }
    @objc private func nextWallpaper() { AppModel.shared.next() }
    @objc private func prevWallpaper() { AppModel.shared.prev() }
    @objc private func openSwitcher() { AppDelegate.shared?.toggleSwitcher() }
    @objc private func openMain() { AppDelegate.shared?.showMainWindow() }
    @objc private func stopWallpaper() { AppModel.shared.stop() }
    @objc private func toggleRotation() { AppModel.shared.config.rotation.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Control de volumen dentro del menú.
private struct MenuVolumeView: View {
    @ObservedObject var model = AppModel.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.toggleMute()
            } label: {
                Image(systemName: model.config.mute || model.config.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            Slider(value: Binding(
                get: { Double(model.config.mute ? 0 : model.config.volume) },
                set: { model.setVolume(Int($0)) }
            ), in: 0...100)
            .controlSize(.small)
            Text("\(model.config.mute ? 0 : model.config.volume)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 34)
    }
}
