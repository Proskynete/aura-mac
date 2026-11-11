import Foundation

/// Colecciones de Wallhaven (solo contenido SFW, `purity=100`).
public enum WallhavenCatalog {
    struct Response: Decodable {
        let data: [Item]?
        let meta: Meta?
    }
    struct Meta: Decodable {
        let current_page: Int?
        let last_page: Int?
    }
    struct Item: Decodable {
        let id: String
        let resolution: String?
        let path: String?
        let thumbs: Thumbs?
        let category: String?
    }
    struct Thumbs: Decodable {
        let large: String?
        let small: String?
    }

    /// Categorías como máscara general/anime/people.
    public static let categories: [(String, String, String)] = [
        ("111", "Todo", "All"),
        ("100", "General", "General"),
        ("010", "Anime", "Anime"),
        ("001", "Personas", "People"),
    ]

    public static let sortings: [(String, String, String)] = [
        ("toplist", "Más populares", "Top list"),
        ("date_added", "Recientes", "Latest"),
        ("views", "Más vistos", "Most viewed"),
        ("favorites", "Favoritos", "Favorites"),
        ("random", "Aleatorio", "Random"),
    ]

    public static let resolutions: [(String, String)] = [
        ("any", "HD+"), ("4k", "4K"), ("2k", "2K"), ("ultrawide", "Ultrawide"),
    ]

    static func queryItems(_ q: OnlineQuery) -> [(String, String)] {
        var params: [(String, String)] = [
            ("categories", q.category.count == 3 ? q.category : "111"),
            ("purity", "100"),
            ("sorting", q.sorting),
            ("page", String(max(1, q.page))),
        ]
        switch q.resolution {
        case "4k": params.append(("atleast", "3840x2160"))
        case "2k": params.append(("resolutions", "2560x1440"))
        case "ultrawide":
            params.append(("ratios", "21x9,32x9"))
            params.append(("atleast", "2560x1080"))
        default: params.append(("resolutions", "1920x1080,2560x1440,3840x2160"))
        }
        if q.sorting == "toplist" { params.append(("topRange", "1M")) }
        let s = q.search.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { params.append(("q", s)) }
        return params
    }

    public static func fetch(_ q: OnlineQuery) async throws -> OnlinePage {
        guard let url = HTTP.url("https://wallhaven.cc/api/v1/search", queryItems(q)) else {
            throw OnlineError.parse("Wallhaven")
        }
        let (data, _) = try await HTTP.get(url, source: "Wallhaven", timeout: 12)
        return try parse(data, page: q.page)
    }

    static func parse(_ data: Data, page: Int) throws -> OnlinePage {
        guard let resp = try? JSONDecoder().decode(Response.self, from: data) else {
            throw OnlineError.parse("Wallhaven")
        }
        let items: [OnlineItem] = (resp.data ?? []).compactMap { e in
            guard let full = e.path, !full.isEmpty else { return nil }
            let thumb = e.thumbs?.large ?? e.thumbs?.small ?? full
            return OnlineItem(
                id: e.id,
                title: "Artwork #\(e.id)",
                author: "Wallhaven (\(e.category ?? "Artwork"))",
                thumbURL: thumb,
                fullURL: full,
                resolution: e.resolution ?? "High Resolution",
                source: .wallhaven,
                date: nil
            )
        }
        if items.isEmpty && page <= 1 { throw OnlineError.empty("Wallhaven") }
        let last = resp.meta?.last_page ?? page + 1
        return OnlinePage(items: items, hasMore: page < last)
    }
}

/// Colección minimalista curada (DenverCoder1/minimalistic-wallpaper-collection).
public enum MinimalisticCatalog {
    struct Entry: Decodable {
        let name: String
        let download_url: String
        let size: Int64?
    }

    static let catalogURL = "https://raw.githubusercontent.com/DenverCoder1/minimalistic-wallpaper-collection/main/api/generated/images.json"
    public static let perPage = 36

    public static func fetch(_ q: OnlineQuery) async throws -> OnlinePage {
        let cache = AuraPaths.onlineCacheDir.appendingPathComponent("minimalistic_catalog.json")
        var all: [OnlineItem]
        if let cached = HTTP.cached(cache, maxAge: 86_400), let parsed = try? parse(cached), !parsed.isEmpty {
            all = parsed
        } else {
            do {
                guard let url = URL(string: catalogURL) else { throw OnlineError.parse("Minimalistic") }
                let (data, _) = try await HTTP.get(url, source: "Minimalistic", timeout: 15)
                try? AuraPaths.atomicWrite(data, to: cache)
                all = try parse(data)
            } catch {
                // Sin red: usa el catálogo viejo si existe.
                if let stale = try? Data(contentsOf: cache), let parsed = try? parse(stale) {
                    all = parsed
                } else {
                    throw error
                }
            }
        }
        let s = q.search.trimmingCharacters(in: .whitespaces).lowercased()
        if !s.isEmpty {
            all = all.filter { $0.title.lowercased().contains(s) || $0.author.lowercased().contains(s) }
        }
        let start = max(0, q.page - 1) * perPage
        guard start < all.count else { return OnlinePage(items: [], hasMore: false) }
        let end = min(start + perPage, all.count)
        return OnlinePage(items: Array(all[start..<end]), hasMore: end < all.count)
    }

    static func parse(_ data: Data) throws -> [OnlineItem] {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            throw OnlineError.parse("Minimalistic")
        }
        return entries.map { e in
            let (title, author) = parseFilename(e.name)
            let res: String
            if let sz = e.size {
                res = sz > 2_000_000 ? "4K UHD" : (sz > 800_000 ? "2K QHD" : "1080p HD")
            } else {
                res = "HD"
            }
            let encoded = e.download_url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?"))) ?? e.download_url
            return OnlineItem(
                id: "minimal_\(e.name.replacingOccurrences(of: ".", with: "_"))",
                title: title,
                author: author,
                thumbURL: "https://wsrv.nl/?url=\(encoded)&w=400&h=225&fit=cover&output=jpg&q=80",
                fullURL: e.download_url,
                resolution: res,
                source: .minimalistic,
                date: nil
            )
        }
    }

    /// "alena-aenami-clouds.jpg" → ("Clouds", "Alena Aenami")
    static func parseFilename(_ filename: String) -> (title: String, author: String) {
        let stem = (filename as NSString).deletingPathExtension
        let lower = stem.lowercased()
        let authorRaw: String
        let titleRaw: String
        if lower.hasPrefix("alena-aenami-") {
            authorRaw = "Alena Aenami"
            titleRaw = String(stem.dropFirst("alena-aenami-".count))
        } else if lower.hasPrefix("unknown-") {
            authorRaw = ""
            titleRaw = String(stem.dropFirst("unknown-".count))
        } else if let dash = stem.firstIndex(of: "-") {
            authorRaw = String(stem[..<dash])
            titleRaw = String(stem[stem.index(after: dash)...])
        } else {
            authorRaw = ""
            titleRaw = stem
        }
        let author: String
        if authorRaw.isEmpty { author = "Minimalist" }
        else if authorRaw == "Alena Aenami" { author = authorRaw }
        else { author = HTMLText.capitalizeWords(authorRaw.replacingOccurrences(of: "_", with: " ")) }
        let title = HTMLText.capitalizeWords(titleRaw.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
        return (title, author)
    }
}
