import Foundation

/// Fondos animados de livewallpapers4free.com mediante su API pública de WordPress.
public enum LiveWallpapers4FreeCatalog {
    static let apiBase = "https://livewallpapers4free.com/wp-json/wp/v2"
    static let pageSize = 36

    public static let categories: [(String, String, String)] = [
        ("all", "Todo", "All"),
        ("anime-live-wallpapers", "Anime", "Anime"),
        ("games-live-wallpapers", "Juegos", "Games"),
        ("fantasy-live-wallpapers", "Fantasía", "Fantasy"),
        ("movies-tv-live-wallpapers", "Películas / TV", "Movies / TV"),
        ("abstract-live-wallpapers", "Abstracto", "Abstract"),
        ("3d-live-wallpapers", "Animación 3D", "3D Animation"),
        ("sci-fi-live-wallpapers", "Ciencia ficción", "Sci-Fi"),
        ("nature-live-wallpapers", "Naturaleza", "Nature"),
    ]

    public static let resolutions: [(String, String)] = [
        ("hd", "1080p HD"),
        ("2k", "2K (2560×1440)"),
        ("4k", "4K (3840×2160)"),
        ("8k", "8K (7680×4320)"),
        ("5k", "5K (5984×2560)"),
        ("5k2k", "5K2K (5120×2160)"),
        ("qhd-ultrawide", "QHD UltraWide (3440×1440)"),
        ("dqhd-ultrawide", "DQHD UltraWide (5120×1440)"),
    ]

    enum Quality: String, CaseIterable {
        case hd, twoK = "2k", fourK = "4k", eightK = "8k", fiveK = "5k", fiveK2K = "5k2k"
        case qhdUltrawide = "qhd-ultrawide", dqhdUltrawide = "dqhd-ultrawide"

        var rank: Int {
            switch self {
            case .hd: return 1
            case .twoK: return 2
            case .qhdUltrawide: return 3
            case .fourK: return 4
            case .fiveK: return 5
            case .fiveK2K: return 6
            case .dqhdUltrawide: return 7
            case .eightK: return 8
            }
        }

        var label: String {
            LiveWallpapers4FreeCatalog.resolutions.first { $0.0 == rawValue }?.1 ?? "Live Wallpaper"
        }
    }

    struct Variant {
        let quality: Quality
        let url: String
    }

    actor CategoryCache {
        var ids: [String: Int]?
        func get() -> [String: Int]? { ids }
        func set(_ v: [String: Int]) { ids = v }
    }
    static let categoryCache = CategoryCache()

    static func categoryIDs() async throws -> [String: Int] {
        if let ids = await categoryCache.get() { return ids }
        guard let url = HTTP.url("\(apiBase)/categories", [("per_page", "100"), ("_fields", "id,slug")]) else {
            throw OnlineError.parse("LiveWallpapers4Free")
        }
        let (data, _) = try await HTTP.get(url, source: "LiveWallpapers4Free", timeout: 15)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OnlineError.parse("LiveWallpapers4Free")
        }
        var ids: [String: Int] = [:]
        for v in arr {
            if let slug = v["slug"] as? String, let id = v["id"] as? Int { ids[slug] = id }
        }
        await categoryCache.set(ids)
        return ids
    }

    public static func fetch(_ q: OnlineQuery) async throws -> OnlinePage {
        var params: [(String, String)] = [
            ("page", String(max(1, q.page))),
            ("per_page", String(pageSize)),
            ("_embed", "wp:featuredmedia"),
            ("_fields", "id,date,title,content,_links,_embedded"),
        ]
        let search = q.search.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty { params.append(("search", search)) }
        if !q.category.isEmpty && q.category != "all" {
            let ids = try await categoryIDs()
            guard let id = ids[q.category] else {
                throw OnlineError.badContent(tr("Categoría no disponible: \(q.category)", "Category unavailable: \(q.category)"))
            }
            params.append(("categories", String(id)))
        }
        guard let url = HTTP.url("\(apiBase)/posts", params) else { throw OnlineError.parse("LiveWallpapers4Free") }
        let (data, http) = try await HTTP.get(url, source: "LiveWallpapers4Free", timeout: 20,
                                              headers: ["Accept": "application/json"])
        let totalPages = Int(http.value(forHTTPHeaderField: "X-WP-TotalPages") ?? "") ?? q.page
        let quality = Quality(rawValue: q.resolution) ?? .fourK
        let items = try parsePosts(data, quality: quality)
        if items.isEmpty && q.page <= 1 { throw OnlineError.empty("LiveWallpapers4Free") }
        return OnlinePage(items: items, hasMore: q.page < totalPages)
    }

    static func parsePosts(_ data: Data, quality: Quality) throws -> [OnlineItem] {
        guard let posts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OnlineError.parse("LiveWallpapers4Free")
        }
        var items: [OnlineItem] = []
        for post in posts {
            if let item = parsePost(post, requested: quality), !items.contains(where: { $0.id == item.id }) {
                items.append(item)
            }
        }
        return items
    }

    static func parsePost(_ post: [String: Any], requested: Quality) -> OnlineItem? {
        guard let rawID = post["id"] as? Int,
              let titleObj = post["title"] as? [String: Any], let titleHTML = titleObj["rendered"] as? String,
              let contentObj = post["content"] as? [String: Any], let content = contentObj["rendered"] as? String,
              let embedded = post["_embedded"] as? [String: Any],
              let media = (embedded["wp:featuredmedia"] as? [[String: Any]])?.first else { return nil }

        let medium = ((media["media_details"] as? [String: Any])?["sizes"] as? [String: Any])?["medium"] as? [String: Any]
        guard let thumb = (medium?["source_url"] as? String) ?? (media["source_url"] as? String) else { return nil }

        let variants = parseDownloadVariants(content)
        guard let selected = selectVariant(variants, requested: requested) else { return nil }
        let date = (post["date"] as? String)?.split(separator: "T").first.map(String.init)

        return OnlineItem(
            id: "lw4free_\(rawID)",
            title: HTMLText.decodeEntities(titleHTML).trimmingCharacters(in: .whitespaces),
            author: "LiveWallpapers4Free",
            thumbURL: thumb,
            fullURL: selected.url,
            resolution: selected.quality.label,
            source: .liveWallpapers4Free,
            date: date
        )
    }

    /// Enlaces `<a class="dlm-download-link" href="https://livewallpapers4free.com/download/…">`.
    static func parseDownloadVariants(_ html: String) -> [Variant] {
        var variants: [Variant] = []
        var cursor = html.startIndex
        while let open = html.range(of: "<a", options: .caseInsensitive, range: cursor..<html.endIndex) {
            // Debe ser exactamente <a seguido de espacio o '>'.
            guard open.upperBound < html.endIndex else { break }
            let next = html[open.upperBound]
            if !next.isWhitespace && next != ">" { cursor = open.upperBound; continue }
            guard let tagEnd = html[open.upperBound...].firstIndex(of: ">") else { break }
            let tag = String(html[open.lowerBound...tagEnd])
            let afterTag = html.index(after: tagEnd)
            guard let close = html.range(of: "</a>", options: .caseInsensitive, range: afterTag..<html.endIndex) else {
                cursor = afterTag; continue
            }
            let text = HTMLText.plainText(String(html[afterTag..<close.lowerBound]))
            cursor = close.upperBound

            let cls = HTMLText.attribute(tag, "class") ?? ""
            guard cls.contains("dlm-download-link") else { continue }
            let href = HTMLText.decodeEntities(HTMLText.attribute(tag, "href") ?? "")
            guard let url = URL(string: href), url.host == "livewallpapers4free.com", url.path.hasPrefix("/download/") else { continue }
            guard let q = detectQuality("\(text) \(href)") else { continue }
            if !variants.contains(where: { $0.quality == q }) {
                variants.append(Variant(quality: q, url: url.absoluteString))
            }
        }
        return variants
    }

    static func selectVariant(_ variants: [Variant], requested: Quality) -> Variant? {
        if let exact = variants.first(where: { $0.quality == requested }) { return exact }
        if let lower = variants.filter({ $0.quality.rank <= requested.rank }).max(by: { $0.quality.rank < $1.quality.rank }) {
            return lower
        }
        return variants.min(by: { $0.quality.rank < $1.quality.rank })
    }

    static func detectQuality(_ raw: String) -> Quality? {
        let v = raw.lowercased().replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: " ", with: "")
        let markers: [(String, Quality)] = [
            ("-5k2k", .fiveK2K), ("-dqhd", .dqhdUltrawide), ("-qhd", .qhdUltrawide), ("-8k", .eightK),
            ("-5k", .fiveK), ("-4k", .fourK), ("-2k", .twoK), ("-hd", .hd),
        ]
        var best: (String.Index, Quality)?
        for (m, q) in markers {
            if let r = v.range(of: m, options: .backwards) {
                if best == nil || r.lowerBound > best!.0 { best = (r.lowerBound, q) }
            }
        }
        if let best { return best.1 }
        if v.contains("5120x1440") || v.contains("dqhd") { return .dqhdUltrawide }
        if v.contains("5120x2160") || v.contains("5k2k") { return .fiveK2K }
        if v.contains("3440x1440") || v.contains("qhd-ultrawide") { return .qhdUltrawide }
        if v.contains("7680x4320") || v.contains("8k") { return .eightK }
        if v.contains("5984x2560") || v.contains("5k") { return .fiveK }
        if v.contains("3840x2160") || v.contains("4k") { return .fourK }
        if v.contains("2560x1440") || v.contains("2k") { return .twoK }
        if v.contains("1920x1080") || v.contains("1080p") || v.contains("-hd") || v.contains("_hd") { return .hd }
        return nil
    }
}

/// Punto de entrada común para la vista Explorar.
public enum OnlineCatalogs {
    public static func fetch(_ q: OnlineQuery) async throws -> OnlinePage {
        switch q.source {
        case .bing: return try await BingCatalog.fetch(page: q.page)
        case .wallhaven: return try await WallhavenCatalog.fetch(q)
        case .minimalistic: return try await MinimalisticCatalog.fetch(q)
        case .motionBGS: return try await MotionBGSCatalog.fetch(q)
        case .liveWallpapers4Free: return try await LiveWallpapers4FreeCatalog.fetch(q)
        }
    }

    /// Categorías (id, es, en) de cada fuente; vacío si no aplica.
    public static func categories(for source: OnlineSource) -> [(String, String, String)] {
        switch source {
        case .wallhaven: return WallhavenCatalog.categories
        case .motionBGS: return MotionBGSCatalog.categories
        case .liveWallpapers4Free: return LiveWallpapers4FreeCatalog.categories
        default: return []
        }
    }

    public static func resolutions(for source: OnlineSource) -> [(String, String)] {
        switch source {
        case .wallhaven: return WallhavenCatalog.resolutions
        case .motionBGS: return MotionBGSCatalog.resolutions
        case .liveWallpapers4Free: return LiveWallpapers4FreeCatalog.resolutions
        default: return []
        }
    }

    public static func supportsSearch(_ source: OnlineSource) -> Bool { source != .bing }
}
