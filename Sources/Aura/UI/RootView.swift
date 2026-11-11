import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AuraCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case library, explore, monitors, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return tr("Biblioteca", "Library")
        case .explore: return tr("Explorar", "Explore")
        case .monitors: return tr("Pantallas", "Displays")
        case .settings: return tr("Ajustes", "Settings")
        case .about: return tr("Acerca de", "About")
        }
    }

    var icon: String {
        switch self {
        case .library: return "photo.stack"
        case .explore: return "globe"
        case .monitors: return "display.2"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var selection: SidebarItem? = .library

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach([SidebarItem.library, .explore, .monitors]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                Section {
                    ForEach([SidebarItem.settings, .about]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarStatus() }
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch selection ?? .library {
                    case .library: LibraryView()
                    case .explore: ExploreView()
                    case .monitors: MonitorsView()
                    case .settings: SettingsView()
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                NowPlayingBar()
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(toast: toast) { model.toast = nil }
                        .padding(.bottom, 78)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        }
        .tint(model.accent)
        // Fuerza el redibujo de los textos al cambiar de idioma.
        .id(model.config.language)
        .onReceive(NotificationCenter.default.publisher(for: .auraNavigate)) { note in
            if let item = note.object as? SidebarItem { selection = item }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let box = Box<[URL]>([])
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.mutate { $0.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { AppModel.shared.importFiles(box.value) }
        }
        return true
    }
}

/// Estado compacto al pie de la barra lateral.
private struct SidebarStatus: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.currentPath == nil ? Color.gray : (model.isPaused ? Color.orange : Color.green))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText).font(.caption.weight(.medium))
                Text(tr("\(model.library.count) fondos", "\(model.library.count) wallpapers"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        if model.currentPath == nil { return tr("Sin fondo", "No wallpaper") }
        if model.isPaused { return tr("En pausa", "Paused") }
        if !model.coveredDisplays.isEmpty && model.coveredDisplays.count >= model.displays.count {
            return tr("En espera (tapado)", "Idle (covered)")
        }
        return tr("Reproduciendo", "Playing")
    }
}

/// Barra inferior: fondo actual, controles de reproducción y volumen.
struct NowPlayingBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            if let path = model.currentPath {
                ThumbnailImage(path: path)
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text((path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path)
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Image(systemName: "sparkles.tv").font(.title2).foregroundStyle(.secondary)
                Text(tr("Elige un fondo de la biblioteca", "Pick a wallpaper from the library"))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 4) {
                Button { model.prev() } label: { Image(systemName: "backward.fill") }
                    .help(tr("Fondo anterior", "Previous wallpaper"))
                Button { model.togglePause() } label: {
                    Image(systemName: model.userPaused ? "play.fill" : "pause.fill").frame(width: 18)
                }
                .help(model.userPaused ? tr("Reanudar", "Resume") : tr("Pausar", "Pause"))
                Button { model.next() } label: { Image(systemName: "forward.fill") }
                    .help(tr("Siguiente fondo", "Next wallpaper"))
                Button { model.stop() } label: { Image(systemName: "stop.fill") }
                    .help(tr("Detener", "Stop"))
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .disabled(model.library.isEmpty && model.currentPath == nil)

            Divider().frame(height: 22)

            HStack(spacing: 6) {
                Button { model.toggleMute() } label: {
                    Image(systemName: model.config.mute || model.config.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(model.config.mute ? tr("Activar sonido", "Unmute") : tr("Silenciar", "Mute"))
                Slider(value: Binding(
                    get: { Double(model.config.mute ? 0 : model.config.volume) },
                    set: { model.setVolume(Int($0)) }
                ), in: 0...100)
                .frame(width: 110)
                Text("\(model.config.mute ? 0 : model.config.volume)%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let item = model.currentItem {
            parts.append(item.isVideo ? tr("Video", "Video") : tr("Imagen", "Image"))
            parts.append(item.sizeFormatted)
        }
        if model.isPaused {
            parts.append(model.pauseReasons.map(\.label).joined(separator: ", "))
        } else if !model.coveredDisplays.isEmpty {
            parts.append(tr("pausado en \(model.coveredDisplays.count) pantalla(s) tapada(s)",
                            "paused on \(model.coveredDisplays.count) covered display(s)"))
        }
        if let p = model.currentPath, let t = model.transcoding[p] {
            parts.append(tr("convirtiendo \(Int(t * 100))%", "converting \(Int(t * 100))%"))
        }
        return parts.joined(separator: " · ")
    }
}
