import Foundation

/// Fotos diarias UHD de Microsoft Bing, con archivo histórico paginado.
public enum BingCatalog {
    struct Response: Decodable { let images: [Image]? }
    struct ArchiveRoot: Decodable { let data: [Image]? }
    struct Image: Decodable {
        let urlbase: String?
        let copyright: String?
        let title: String?
        let startdate: String?
        let hsh: String?
    }

    static let archiveURL = "https://raw.githubusercontent.com/zkeq/Bing-Wallpaper-Action/main/data/en-US_all.json"
    public static let perPage = 24

    /// Página 1: las 16 fotos más recientes. Siguientes páginas: archivo histórico.
    public static func fetch(page: Int) async throws -> OnlinePage {
        if page <= 1 {
            return OnlinePage(items: try await fetchDaily(), hasMore: true)
        }
        return try await fetchArchive(page: page - 1)
    }

    static func fetchDaily() async throws -> [OnlineItem] {
        var items: [OnlineItem] = []
        for idx in [0, 8] {
            guard let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=\(idx)&n=8&mkt=en-US") else { continue }
            guard let result = try? await HTTP.get(url, source: "Bing", timeout: 10,
                                                    headers: ["User-Agent": HTTP.browserUserAgent]) else { continue }
            let images = (try? JSONDecoder().decode(Response.self, from: result.0))?.images ?? []
            for img in images {
                if let item = convert(img), !items.contains(where: { $0.id == item.id }) {
                    items.append(item)
                }
            }
        }
        if items.isEmpty {
            throw OnlineError.badContent(tr("No se pudieron cargar los fondos de Bing. Revisa tu conexión a internet.",
                                            "Could not load wallpapers from Bing. Check your internet connection."))
        }
        return items
    }

    static func fetchArchive(page: Int) async throws -> OnlinePage {
        let cache = AuraPaths.onlineCacheDir.appendingPathComponent("bing_archive.json")
        let data: Data
        if let cached = HTTP.cached(cache, maxAge: 86_400) {
            data = cached
        } else {
            guard let url = URL(string: archiveURL) else { throw OnlineError.parse("Bing") }
            data = try await HTTP.get(url, source: "Bing", timeout: 20).0
            try? AuraPaths.atomicWrite(data, to: cache)
        }
        let all = (try? JSONDecoder().decode(ArchiveRoot.self, from: data))?.data ?? []
        return paginateArchive(all, page: page)
    }

    static func paginateArchive(_ all: [Image], page: Int) -> OnlinePage {
        let start = max(0, page - 1) * perPage
        guard start < all.count else { return OnlinePage(items: [], hasMore: false) }
        let end = min(start + perPage, all.count)
        return OnlinePage(items: all[start..<end].compactMap(convert), hasMore: end < all.count)
    }

    static func convert(_ img: Image) -> OnlineItem? {
        guard let urlbase = img.urlbase, !urlbase.isEmpty else { return nil }
        let id = img.hsh ?? urlbase.replacingOccurrences(of: "/th?id=", with: "")
        let title: String = {
            if let t = img.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
            return titleFromURLBase(urlbase)
        }()
        let date: String? = {
            guard let sd = img.startdate, sd.count == 8 else { return nil }
            let a = Array(sd)
            return "\(String(a[0..<4]))-\(String(a[4..<6]))-\(String(a[6..<8]))"
        }()
        return OnlineItem(
            id: id,
            title: title,
            author: img.copyright ?? "Microsoft Bing",
            thumbURL: "https://www.bing.com\(urlbase)_1920x1080.jpg&pid=hp&w=480&h=270&rs=1&c=4",
            fullURL: "https://www.bing.com\(urlbase)_UHD.jpg",
            resolution: "3840x2160 (4K UHD)",
            source: .bing,
            date: date
        )
    }

    /// "/th?id=OHR.FieldsOfGold_EN-US123" → "Fields Of Gold"
    static func titleFromURLBase(_ urlbase: String) -> String {
        if let range = urlbase.range(of: "OHR.") {
            let part = urlbase[range.upperBound...]
            let core = part.split(separator: "_").first.map(String.init) ?? String(part)
            var s = ""
            var prevLower = false
            for c in core {
                if prevLower && c.isUppercase { s.append(" ") }
                prevLower = c.isLowercase
                s.append(c)
            }
            if !s.isEmpty { return s }
        }
        let parts = urlbase.split(separator: ".")
        return parts.count > 1 ? parts[1].replacingOccurrences(of: "_", with: " ") : "Bing Wallpaper"
    }
}
