import AppKit
import SwiftUI
import AuraCore

@MainActor
final class ExploreState: ObservableObject {
    @Published var query = OnlineQuery(source: .bing)
    @Published private(set) var items: [OnlineItem] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    @Published var searchText = ""

    private var task: Task<Void, Never>?
    /// Búsquedas recordadas por fuente al cambiar de pestaña.
    private var savedQueries: [OnlineSource: OnlineQuery] = [:]

    func select(source: OnlineSource) {
        guard source != query.source else { return }
        savedQueries[query.source] = query
        query = savedQueries[source] ?? OnlineQuery(source: source)
        searchText = query.search
        reload()
    }

    func reload() {
        query.page = 1
        query.search = searchText
        items = []
        hasMore = false
        load()
    }

    func loadMore() {
        guard hasMore, !loading else { return }
        query.page += 1
        load()
    }

    private func load() {
        task?.cancel()
        loading = true
        error = nil
        let q = query
        task = Task {
            do {
                let page = try await OnlineCatalogs.fetch(q)
                guard !Task.isCancelled, q.source == self.query.source else { return }
                let existing = Set(self.items.map(\.id))
                self.items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                self.hasMore = page.hasMore && !page.items.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                if q.page > 1 { self.query.page -= 1 }
            }
            self.loading = false
        }
    }
}

struct ExploreView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var downloads: DownloadManager
    @StateObject private var state = ExploreState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { if state.items.isEmpty && !state.loading { state.reload() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Explorar", "Explore")).font(.title2.weight(.semibold))
                if state.loading { ProgressView().controlSize(.small) }
                Spacer()
                if OnlineCatalogs.supportsSearch(state.query.source) {
                    TextField(tr("Buscar en \(state.query.source.displayName)", "Search \(state.query.source.displayName)"),
                              text: $state.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { state.reload() }
                }
                Button { state.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(tr("Recargar", "Reload"))
            }

            HStack(spacing: 6) {
                ForEach(OnlineSource.allCases) { src in
                    let selected = state.query.source == src
                    Button { state.select(source: src) } label: {
                        Label(src.displayName, systemImage: src.isLive ? "play.rectangle" : "photo")
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            filters
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var filters: some View {
        let src = state.query.source
        let cats = OnlineCatalogs.categories(for: src).map { Choice(id: $0.0, label: tr($0.1, $0.2)) }
        let resolutions = OnlineCatalogs.resolutions(for: src).map { Choice(id: $0.0, label: $0.1) }
        let sortings = WallhavenCatalog.sortings.map { Choice(id: $0.0, label: tr($0.1, $0.2)) }
        if !cats.isEmpty || !resolutions.isEmpty || src == .wallhaven {
            HStack(spacing: 14) {
                if !cats.isEmpty {
                    Picker(tr("Categoría", "Category"), selection: $state.query.category) {
                        ForEach(cats) { c in Text(c.label).tag(c.id) }
                    }
                    .frame(maxWidth: 230)
                }
                if !resolutions.isEmpty {
                    Picker(tr("Resolución", "Resolution"), selection: $state.query.resolution) {
                        ForEach(resolutions) { r in Text(r.label).tag(r.id) }
                    }
                    .frame(maxWidth: 280)
                }
                if src == .wallhaven {
                    Picker(tr("Orden", "Sort"), selection: $state.query.sorting) {
                        ForEach(sortings) { s in Text(s.label).tag(s.id) }
                    }
                    .frame(maxWidth: 220)
                }
                Spacer()
                DisplayTargetChips()
            }
            .onChange(of: state.query.category) { _, _ in state.reload() }
            .onChange(of: state.query.resolution) { _, _ in state.reload() }
            .onChange(of: state.query.sorting) { _, _ in state.reload() }
        } else {
            HStack {
                Text(src == .bing ? tr("Fotos diarias de Bing en 4K, con archivo histórico.", "Bing's daily 4K photos, with the full archive.")
                                  : tr("Colección curada de fondos minimalistas.", "A curated collection of minimalist wallpapers."))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                DisplayTargetChips()
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let error = state.error, state.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 38)).foregroundStyle(.secondary)
                Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
                Button(tr("Reintentar", "Retry")) { state.reload() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.items.isEmpty {
            ProgressView(tr("Cargando…", "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 16)], spacing: 18) {
                    ForEach(state.items) { item in
                        OnlineCard(item: item)
                            .onAppear { if item.id == state.items.last?.id { state.loadMore() } }
                    }
                }
                .padding(20)
                if state.loading {
                    ProgressView().padding(.bottom, 24)
                } else if let error = state.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                } else if !state.hasMore {
                    Text(tr("No hay más resultados.", "No more results.")).font(.caption).foregroundStyle(.tertiary).padding(.bottom, 24)
                }
            }
        }
    }
}

struct OnlineCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var downloads: DownloadManager
    let item: OnlineItem
    @ViewState private var hovering = false

    var body: some View {
        let local: URL? = item.downloadedURL
        return VStack(alignment: .leading, spacing: 8) {
            OnlineCardThumb(item: item, local: local, hovering: hovering)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                HStack {
                    Text(item.author).lineLimit(1)
                    if let date = item.date {
                        Spacer()
                        Text(date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .contextMenu { menu(local: local) }
        .help(item.title)
    }

    @ViewBuilder private func menu(local: URL?) -> some View {
        if let local {
            Button(tr("Aplicar", "Apply")) { model.apply(path: local.path) }
            Button(tr("Mostrar en Finder", "Show in Finder")) { revealInFinder(local.path) }
        } else {
            Button(tr("Descargar y aplicar", "Download and apply")) { downloads.start(item, apply: true) }
            Button(tr("Solo descargar", "Download only")) { downloads.start(item, apply: false) }
        }
        Divider()
        Button(tr("Copiar enlace", "Copy link")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.fullURL, forType: .string)
        }
    }
}

private struct OnlineCardThumb: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var downloads: DownloadManager
    let item: OnlineItem
    let local: URL?
    let hovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return RemoteThumbnail(item: item)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(shape)
            .overlay(alignment: .topLeading) { badges }
            .overlay { actions(shape: shape) }
            .shadow(color: Color.black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: 3)
    }

    private var badges: some View {
        let res: String = item.resolution.components(separatedBy: " (").first ?? item.resolution
        return HStack(spacing: 4) {
            Badge(text: res, systemImage: item.isVideo ? "play.fill" : "photo")
            if local != nil {
                Badge(text: tr("Descargado", "Downloaded"), systemImage: "checkmark", tint: Color.green.opacity(0.85))
            }
        }
        .padding(8)
    }

    @ViewBuilder private func actions(shape: RoundedRectangle) -> some View {
        if let progress = downloads.progress(for: item) {
            ZStack {
                shape.fill(Color.black.opacity(0.45))
                VStack(spacing: 8) {
                    ProgressView(value: progress).frame(width: 140).tint(.white)
                    Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.white)
                    Button(tr("Cancelar", "Cancel")) { downloads.cancel(item) }
                        .controlSize(.small)
                }
            }
        } else if hovering {
            ZStack {
                shape.fill(Color.black.opacity(0.35))
                hoverButtons
            }
        }
    }

    @ViewBuilder private var hoverButtons: some View {
        HStack(spacing: 10) {
            if let local {
                Button { model.apply(path: local.path) } label: {
                    Label(tr("Aplicar", "Apply"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { downloads.start(item, apply: true) } label: {
                    Label(tr("Aplicar", "Apply"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help(tr("Descargar y aplicar", "Download and apply"))
                Button { downloads.start(item, apply: false) } label: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .help(tr("Solo descargar", "Download only"))
            }
        }
    }
}

/// Opción de un selector (id interno + texto visible).
struct Choice: Identifiable, Hashable {
    let id: String
    let label: String
}
