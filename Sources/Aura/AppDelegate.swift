import AppKit
import CoreServices
import SwiftUI
import AuraCore

@main
enum AuraMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    private let model = AppModel.shared
    private let commands = CommandServer()
    private var statusBar: StatusBarController?
    private var mainWindow: NSWindow?
    private var switcherPanel: SwitcherPanel?
    private let switcherState = SwitcherState()
    private var hotKey: HotKey?
    private var hotkeyObserver: NSObjectProtocol?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Una sola instancia: si ya hay otra, le pide mostrar la ventana y sale.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AuraPaths.bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                IPC.commandName, object: nil, userInfo: [IPC.Key.command: IPCCommand.show.rawValue], deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        buildMainMenu()
        commands.start()
        model.start()
        statusBar = StatusBarController()
        switcherState.close = { [weak self] in self?.hideSwitcher() }
        configureHotKey()
        hotkeyObserver = NotificationCenter.default.addObserver(forName: .auraHotkeySettingChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureHotKey() }
        }

        let hidden = CommandLine.arguments.contains("--daemon") || CommandLine.arguments.contains("--hidden")
        if !hidden && !Self.launchedAsLoginItem() {
            showMainWindow()
        }
    }

    /// Al iniciar con la sesión, macOS envía el evento "open application" marcado como ítem de inicio.
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Ventana principal

    func showMainWindow() {
        if mainWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: model.config.windowWidth, height: model.config.windowHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "Aura"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 560)
            w.setFrameAutosaveName("AuraMainWindow")
            w.contentView = NSHostingView(rootView: RootView().environmentObject(model).environmentObject(model.downloads))
            w.delegate = self
            if !w.setFrameUsingName("AuraMainWindow") { w.center() }
            mainWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        if let size = mainWindow?.frame.size {
            model.config.windowWidth = size.width
            model.config.windowHeight = size.height
        }
        if model.config.keepRunningOnClose {
            // Sigue en la barra de menú sin ícono en el Dock.
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: Selector rápido

    func toggleSwitcher() {
        if let panel = switcherPanel, panel.isVisible {
            hideSwitcher()
            return
        }
        switcherState.reload()
        if switcherPanel == nil { switcherPanel = SwitcherPanel(state: switcherState) }
        switcherPanel?.present()
    }

    private func hideSwitcher() {
        guard let panel = switcherPanel, panel.isVisible else { return }
        panel.dismiss()
    }

    private func configureHotKey() {
        hotKey = nil
        if model.config.switcherHotkey {
            hotKey = HotKey { [weak self] in self?.toggleSwitcher() }
        }
    }

    // MARK: Menú principal (necesario para ⌘Q, ⌘W y copiar/pegar en los campos)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Acerca de Aura", "About Aura"), action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Ajustes…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Ocultar Aura", "Hide Aura"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Salir de Aura", "Quit Aura"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("Edición", "Edit"))
        edit.addItem(withTitle: tr("Deshacer", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: tr("Rehacer", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Cortar", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Copiar", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Pegar", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Seleccionar todo", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let controlItem = NSMenuItem()
        let control = NSMenu(title: tr("Fondo", "Wallpaper"))
        control.addItem(withTitle: tr("Pausar / reanudar", "Pause / Resume"), action: #selector(menuTogglePause), keyEquivalent: "p").target = self
        control.addItem(withTitle: tr("Siguiente", "Next"), action: #selector(menuNext), keyEquivalent: "]").target = self
        control.addItem(withTitle: tr("Anterior", "Previous"), action: #selector(menuPrev), keyEquivalent: "[").target = self
        control.addItem(withTitle: tr("Selector rápido", "Quick Switcher"), action: #selector(menuSwitcher), keyEquivalent: "k").target = self
        controlItem.submenu = control
        main.addItem(controlItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: tr("Ventana", "Window"))
        window.addItem(withTitle: tr("Cerrar", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: tr("Minimizar", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        showMainWindow()
        NotificationCenter.default.post(name: .auraNavigate, object: SidebarItem.about)
    }

    @objc private func showSettings() {
        showMainWindow()
        NotificationCenter.default.post(name: .auraNavigate, object: SidebarItem.settings)
    }

    @objc private func menuTogglePause() { model.togglePause() }
    @objc private func menuNext() { model.next() }
    @objc private func menuPrev() { model.prev() }
    @objc private func menuSwitcher() { toggleSwitcher() }
}

extension Notification.Name {
    static let auraNavigate = Notification.Name("aura.navigate")
}
