import SwiftUI
import AppKit
import AuraCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, live, still, favorites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Todo", "All")
        case .live: return tr("Animados", "Live")
        case .still: return tr("Imágenes", "Images")
        case .favorites: return tr("Favoritos", "Favorites")
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var search = ""
    @ViewState private var filter: LibraryFilter = .all
    @ViewState private var pendingTrash: WallpaperItem? = nil

    private var items: [WallpaperItem] {
        let favs = Set(model.config.favorites)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.sortedLibrary.filter { item in
            switch filter {
            case .all: break
            case .live: if !item.isVideo { return false }
            case .still: if item.isVideo { return false }
            case .favorites: if !favs.contains(item.path) { return false }
            }
            return q.isEmpty || item.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.library.isEmpty {
                emptyState
            } else if items.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)], spacing: 18) {
                        ForEach(items) { item in
                            LibraryCard(item: item, onTrash: { pendingTrash = item })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .confirmationDialog(
            tr("¿Mover \"\(pendingTrash?.name ?? "")\" a la papelera?", "Move \"\(pendingTrash?.name ?? "")\" to the Trash?"),
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button(tr("Mover a la papelera", "Move to Trash"), role: .destructive) {
                if let item = pendingTrash { model.moveToTrash(item) }
                pendingTrash = nil
            }
            Button(tr("Cancelar", "Cancel"), role: .cancel) { pendingTrash = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(tr("Biblioteca", "Library")).font(.title2.weight(.semibold))
                if model.isScanning { ProgressView().controlSize(.small) }
                Spacer()
                TextField(tr("Buscar", "Search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Menu {
                    Picker(tr("Ordenar", "Sort"), selection: $model.config.librarySort) {
                        Text(tr("Más recientes", "Newest")).tag(LibrarySort.newest)
                        Text(tr("Más antiguos", "Oldest")).tag(LibrarySort.oldest)
                        Text(tr("Nombre", "Name")).tag(LibrarySort.name)
                        Text(tr("Tamaño", "Size")).tag(LibrarySort.size)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(tr("Ordenar", "Sort"))
                Button { pickFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .help(tr("Agregar carpeta", "Add folder"))
                Button { openInFinder(AuraPaths.downloadsDir.path) } label: { Image(systemName: "folder") }
                    .help(tr("Abrir la carpeta de Aura en Finder", "Open Aura's folder in Finder"))
                Button { model.rescan() } label: { Image(systemName: "arrow.clockwise") }
                    .help(tr("Volver a escanear", "Rescan"))
            }
            .buttonStyle(.borderless)

            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
                Spacer()
                DisplayTargetChips()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(tr("Tu biblioteca está vacía", "Your library is empty")).font(.title3.weight(.semibold))
            Text(tr("Arrastra videos o imágenes a esta ventana, agrega una carpeta o descarga fondos en Explorar.",
                    "Drag videos or images into this window, add a folder or download wallpapers in Explore."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack {
                Button(tr("Agregar carpeta…", "Add folder…")) { pickFolder() }
                Button(tr("Ir a Explorar", "Go to Explore")) {
                    NotificationCenter.default.post(name: .auraNavigate, object: SidebarItem.explore)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Agregar", "Add")
        if panel.runModal() == .OK {
            for url in panel.urls { model.addFolder(url) }
        }
    }
}

/// Selector de pantalla destino: "Todas" o una en particular.
struct DisplayTargetChips: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.displays.count > 1 {
            HStack(spacing: 6) {
                Text(tr("Aplicar en:", "Apply to:")).font(.caption).foregroundStyle(.secondary)
                chip("*", tr("Todas", "All"), icon: "rectangle.on.rectangle")
                ForEach(model.displays) { d in
                    chip(d.id, d.name, icon: d.isMain ? "display" : "rectangle")
                }
            }
        }
    }

    private func chip(_ id: String, _ title: String, icon: String) -> some View {
        let selected = model.selectedDisplay == id
        return Button {
            model.selectedDisplay = id
            model.config.output = id
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
        }
        .buttonStyle(.plain)
    }
}

struct LibraryCard: View {
    @EnvironmentObject var model: AppModel
    let item: WallpaperItem
    var onTrash: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryCardThumb(item: item, hovering: hovering)
            LibraryCardFooter(item: item)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onTapGesture { model.apply(path: item.path) }
        .contextMenu { menu }
        .help(item.name)
    }

    @ViewBuilder private var menu: some View {
        Button(tr("Aplicar a todas las pantallas", "Apply to all displays")) { model.apply(path: item.path, target: "*") }
        if model.displays.count > 1 {
            ForEach(model.displays) { d in
                Button(tr("Aplicar en \(d.name)", "Apply on \(d.name)")) { model.apply(path: item.path, target: d.id) }
            }
        }
        Divider()
        Button(model.isFavorite(item.path) ? tr("Quitar de favoritos", "Remove from favorites") : tr("Agregar a favoritos", "Add to favorites")) {
            model.toggleFavorite(item.path)
        }
        Button(tr("Mostrar en Finder", "Show in Finder")) { revealInFinder(item.path) }
        Divider()
        Button(tr("Mover a la papelera…", "Move to Trash…"), role: .destructive) { onTrash() }
    }
}

private struct LibraryCardThumb: View {
    @EnvironmentObject var model: AppModel
    let item: WallpaperItem
    let hovering: Bool

    var body: some View {
        let inUse: Bool = model.currentPaths.contains(item.path)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let ring: AnyShapeStyle = inUse ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear)
        return ZStack {
            ThumbnailImage(path: item.path)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(shape)
            if hovering {
                shape.fill(Color.black.opacity(0.3))
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
            }
        }
        .overlay(alignment: .topLeading) { badges(inUse: inUse) }
        .overlay(alignment: .topTrailing) { favoriteButton }
        .overlay(shape.strokeBorder(ring, lineWidth: 2.5))
        .shadow(color: Color.black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: 3)
        .scaleEffect(hovering ? 1.015 : 1)
    }

    private func badges(inUse: Bool) -> some View {
        let needsConvert: Bool = MediaTypes.needsTranscode(item.url) && Transcoder.playableURL(for: item.url) == nil
        return HStack(spacing: 4) {
            Badge(text: item.isVideo ? tr("Video", "Video") : tr("Imagen", "Image"),
                  systemImage: item.isVideo ? "play.fill" : "photo")
            if inUse {
                Badge(text: tr("En uso", "In use"), systemImage: "checkmark", tint: Color.green.opacity(0.85))
            }
            if needsConvert {
                Badge(text: item.url.pathExtension.uppercased(), systemImage: "arrow.triangle.2.circlepath",
                      tint: Color.orange.opacity(0.85))
            }
        }
        .padding(8)
    }

    private var favoriteButton: some View {
        let fav: Bool = model.isFavorite(item.path)
        return Button { model.toggleFavorite(item.path) } label: {
            Image(systemName: fav ? "star.fill" : "star")
                .foregroundStyle(fav ? Color.yellow : Color.white)
                .padding(6)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .opacity(hovering || fav ? 1 : 0)
        .help(tr("Favorito", "Favorite"))
    }
}

private struct LibraryCardFooter: View {
    let item: WallpaperItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(item.sizeFormatted).font(.caption).foregroundStyle(.secondary)
            Button { revealInFinder(item.path) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(tr("Mostrar en Finder", "Show in Finder"))
        }
        .padding(.horizontal, 2)
    }
}
