import AppKit
import SwiftUI
import AuraCore

/// Estado del selector rápido (navegación con teclado).
@MainActor
final class SwitcherState: ObservableObject {
    @Published var items: [WallpaperItem] = []
    @Published var index = 0
    var close: () -> Void = {}

    /// Columnas del panal para moverse con ↑/↓.
    let honeycombColumns = 7

    func reload() {
        let model = AppModel.shared
        items = model.rotationPool(forSwitcher: true)
        if let current = model.currentPath, let i = items.firstIndex(where: { $0.path == current }) {
            index = i
        } else {
            index = 0
        }
    }

    /// Índice circular relativo a la selección.
    func wrapped(_ offset: Int) -> Int {
        let n = items.count
        guard n > 0 else { return 0 }
        let raw: Int = (index + offset) % n
        return raw < 0 ? raw + n : raw
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        index = wrapped(delta)
    }

    func confirm() {
        guard items.indices.contains(index) else { close(); return }
        AppModel.shared.apply(path: items[index].path)
        close()
    }

    func pick(_ i: Int) {
        index = i
        confirm()
    }
}

/// Panel flotante que cubre la pantalla donde está el puntero.
final class SwitcherPanel: NSPanel {
    let state: SwitcherState

    init(state: SwitcherState) {
        self.state = state
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: SwitcherView(state: state, model: AppModel.shared))
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let honeycomb = AppModel.shared.config.switcherStyle == .honeycomb
        switch Int(event.keyCode) {
        case 53: state.close()                                   // Esc
        case 36, 76, 49: state.confirm()                         // Return, Enter, Espacio
        case 123: state.move(-1)                                 // ←
        case 124: state.move(1)                                  // →
        case 125: state.move(honeycomb ? state.honeycombColumns : 1)   // ↓
        case 126: state.move(honeycomb ? -state.honeycombColumns : -1) // ↑
        default:
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        state.close()
    }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen { setFrame(screen.frame, display: true) }
        dismissToken += 1
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.15
        animator().alphaValue = 1
        NSAnimationContext.endGrouping()
    }

    /// Evita que un cierre pendiente oculte el panel si se volvió a abrir.
    private var dismissToken = 0

    func dismiss() {
        dismissToken += 1
        let token = dismissToken
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.12
        animator().alphaValue = 0
        NSAnimationContext.endGrouping()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard let self, self.dismissToken == token else { return }
            self.orderOut(nil)
        }
    }
}

// MARK: - Vistas

struct SwitcherView: View {
    @ObservedObject var state: SwitcherState
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.close() }

            if state.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.stack").font(.largeTitle)
                    Text(tr("Tu biblioteca está vacía", "Your library is empty")).font(.headline)
                    Text(tr("Agrega carpetas o descarga fondos desde Explorar.", "Add folders or download wallpapers from Explore."))
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(48)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var alignment: Alignment {
        switch model.config.switcherPosition {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        case .center: return .center
        }
    }

    @ViewBuilder private var content: some View {
        switch model.config.switcherStyle {
        case .classic: ClassicSwitcher(state: state, vertical: [.left, .right].contains(model.config.switcherPosition))
        case .cinematic: CinematicSwitcher(state: state)
        case .honeycomb: HoneycombSwitcher(state: state)
        }
    }
}

private struct SwitcherCaption: View {
    let item: WallpaperItem

    var body: some View {
        VStack(spacing: 4) {
            Text(item.name).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Badge(text: item.isVideo ? tr("Video", "Video") : tr("Imagen", "Image"),
                      systemImage: item.isVideo ? "play.fill" : "photo")
                Text(item.sizeFormatted).font(.caption).foregroundStyle(.secondary)
                if AppModel.shared.isFavorite(item.path) {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
            }
            Text(tr("← → para elegir · Enter para aplicar · Esc para cerrar", "← → to browse · Enter to apply · Esc to close"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Carrusel de cinco tarjetas con la central agrandada.
private struct ClassicSwitcher: View {
    @ObservedObject var state: SwitcherState
    let vertical: Bool

    var body: some View {
        let offsets = [-2, -1, 0, 1, 2]
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))
        VStack(spacing: 14) {
            layout {
                ForEach(offsets, id: \.self) { off in
                    ClassicCard(state: state, offset: off)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.index)
            SwitcherCaption(item: state.items[state.index])
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ClassicCard: View {
    @ObservedObject var state: SwitcherState
    let offset: Int

    var body: some View {
        let i: Int = state.wrapped(offset)
        let center: Bool = offset == 0
        let width: CGFloat = center ? 300 : 190
        let height: CGFloat = center ? 169 : 107
        let border: Color = center ? .white : Color.white.opacity(0.15)
        let fade: Double = center ? 1 : (abs(offset) == 1 ? 0.8 : 0.5)
        // Con menos de 5 fondos se ocultan las posiciones repetidas.
        let hidden: Bool = offset != 0 && abs(offset) >= state.items.count
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ThumbnailImage(path: state.items[i].path)
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(border, lineWidth: center ? 3 : 1))
            .shadow(color: Color.black.opacity(center ? 0.5 : 0.2), radius: center ? 20 : 8)
            .opacity(hidden ? 0 : fade)
            .onTapGesture { state.pick(i) }
    }
}

/// Vista previa grande con tira de miniaturas.
private struct CinematicSwitcher: View {
    @ObservedObject var state: SwitcherState

    var body: some View {
        let item = state.items[state.index]
        VStack(spacing: 16) {
            ThumbnailImage(path: item.path)
                .frame(width: 720, height: 405)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .id(item.path)
                .transition(.opacity)
            SwitcherCaption(item: item)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { i, it in
                            ThumbnailImage(path: it.path)
                                .frame(width: 112, height: 63)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(i == state.index ? Color.white : .clear, lineWidth: 2))
                                .opacity(i == state.index ? 1 : 0.6)
                                .id(i)
                                .onTapGesture { state.pick(i) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 720, height: 70)
                .onChange(of: state.index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
                .onAppear { proxy.scrollTo(state.index, anchor: .center) }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: state.index)
    }
}

/// Panal de hexágonos alrededor del fondo seleccionado.
private struct HoneycombSwitcher: View {
    @ObservedObject var state: SwitcherState
    private let size = CGSize(width: 132, height: 152)

    var body: some View {
        let cols = state.honeycombColumns
        let rows = 3
        let pageSize = cols * rows
        let page = state.index / pageSize
        let start = page * pageSize
        let end = min(start + pageSize, state.items.count)
        let pageCount = (state.items.count + pageSize - 1) / pageSize

        VStack(spacing: 18) {
            VStack(spacing: -size.height * 0.24) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<cols, id: \.self) { c in
                            let i = start + r * cols + c
                            if i < end {
                                cell(i)
                            } else {
                                Color.clear.frame(width: size.width, height: size.height)
                            }
                        }
                    }
                    .offset(x: r % 2 == 1 ? (size.width + 6) / 2 : 0)
                }
            }
            .padding(.trailing, (size.width + 6) / 2)
            SwitcherCaption(item: state.items[state.index])
            if pageCount > 1 {
                Text(tr("Página \(page + 1) de \(pageCount)", "Page \(page + 1) of \(pageCount)"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: state.index)
    }

    private func cell(_ i: Int) -> some View {
        let selected = i == state.index
        return ThumbnailImage(path: state.items[i].path)
            .frame(width: size.width, height: size.height)
            .clipShape(Hexagon())
            .overlay(Hexagon().stroke(selected ? Color.white : .white.opacity(0.12), lineWidth: selected ? 3 : 1))
            .scaleEffect(selected ? 1.08 : 1)
            .zIndex(selected ? 1 : 0)
            .shadow(color: .black.opacity(selected ? 0.55 : 0), radius: 14)
            .opacity(selected ? 1 : 0.78)
            .onTapGesture { state.pick(i) }
    }
}
