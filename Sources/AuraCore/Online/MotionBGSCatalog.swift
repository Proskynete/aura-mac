import Foundation

/// Fondos animados de motionbgs.com (lectura del HTML público, igual que el original).
public enum MotionBGSCatalog {
    public static let categories: [(String, String, String)] = [
        ("all", "Todo", "All"),
        ("anime", "Anime", "Anime"),
        ("games", "Juegos", "Games"),
        ("nature", "Naturaleza", "Nature"),
        ("cars", "Autos", "Cars"),
        ("space", "Espacio", "Space"),
        ("fantasy", "Fantasía", "Fantasy"),
        ("cyberpunk", "Cyberpunk", "Cyberpunk"),
        ("movies", "Películas", "Movies"),
        ("abstract", "Abstracto", "Abstract"),
    ]

    public static let resolutions: [(String, String)] = [("4k", "4K UHD"), ("hd", "1080p HD")]

    public static func catalogURL(category: String, page: Int) -> String {
        let cat = category.trimmingCharacters(in: .whitespaces).lowercased()
        if cat.isEmpty || cat == "all" {
            return page <= 1 ? "https://motionbgs.com/" : "https://motionbgs.com/\(page)/"
        }
        return page <= 1 ? "https://motionbgs.com/tag:\(cat)/" : "https://motionbgs.com/tag:\(cat)/\(page)/"
    }

    static func formEncode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"),
                 UInt8(ascii: "."), UInt8(ascii: "~"):
                out.append(Character(Unicode.Scalar(b)))
            case UInt8(ascii: " "):
                out.append("+")
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    public static func fetch(_ q: OnlineQuery) async throws -> OnlinePage {
        let search = q.search.trimmingCharacters(in: .whitespaces)
        let urlString: String
        if !search.isEmpty {
            let enc = formEncode(search)
            urlString = q.page <= 1 ? "https://motionbgs.com/search?q=\(enc)" : "https://motionbgs.com/search?q=\(enc)&page=\(q.page)"
        } else {
            urlString = catalogURL(category: q.category, page: q.page)
        }
        guard let url = URL(string: urlString) else { throw OnlineError.parse("MotionBGS") }
        let (data, _) = try await HTTP.get(url, source: "MotionBGS", timeout: 15, headers: [
            "User-Agent": HTTP.browserUserAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        ])
        let html = String(decoding: data, as: UTF8.self)
        let items = parse(html: html, preferredResolution: q.resolution, category: q.category)
        if items.isEmpty && q.page <= 1 { throw OnlineError.empty("MotionBGS") }
        // El sitio pagina con 36 tarjetas; si llegaron menos, no hay más.
        return OnlinePage(items: items, hasMore: items.count >= 24)
    }

    public static func parse(html fullHTML: String, preferredResolution: String, category: String) -> [OnlineItem] {
        // Trabajamos sobre bytes UTF-8 para que las búsquedas sean O(n).
        let all = Array(fullHTML.utf8)
        var startOffset = 0
        if let b = find(all, Array("<body".utf8), from: 0) { startOffset = b }
        let html = Array(all[startOffset...])

        let catLabel = (category.isEmpty || category == "all") ? "Live" : HTMLText.capitalizeWords(category)
        var seen = Set<String>()
        var items: [OnlineItem] = []
        let mediaMarker = Array("/media/".utf8)
        var pos = 0

        func str(_ a: Int, _ b: Int) -> String { String(decoding: html[a..<b], as: UTF8.self) }

        while let idx = find(html, mediaMarker, from: pos) {
            defer { if pos <= idx { pos = idx + mediaMarker.count } }
            guard let aIdx = rfind(html, Array("<a ".utf8), before: idx) else { continue }
            let afterMedia = idx + mediaMarker.count
            guard let slash = html[afterMedia...].firstIndex(of: UInt8(ascii: "/")) else { continue }
            let mediaID = str(afterMedia, slash)
            let afterSlash = slash + 1
            guard let jpg = find(html, Array(".jpg".utf8), from: afterSlash), jpg - afterSlash < 160 else { continue }
            let imgFilename = str(afterSlash, jpg)
            pos = jpg + 4

            guard !mediaID.isEmpty, mediaID.allSatisfy(\.isNumber), seen.insert(mediaID).inserted else { continue }

            // 1. title="... live wallpaper" en el <a>
            var title = ""
            let anchor = str(aIdx, idx)
            if let t = HTMLText.attribute(anchor, "title") {
                var raw = t.trimmingCharacters(in: .whitespaces)
                if raw.lowercased().hasSuffix(" live wallpaper") { raw = String(raw.dropLast(15)) }
                title = HTMLText.decodeEntities(raw.trimmingCharacters(in: .whitespaces))
            }
            // 2. <span class=ttl>…</span>
            if title.isEmpty {
                let window = str(idx, min(html.count, idx + 600))
                for marker in ["class=ttl>", "class=\"ttl\">"] {
                    if let r = window.range(of: marker), let end = window[r.upperBound...].firstIndex(of: "<") {
                        title = HTMLText.decodeEntities(String(window[r.upperBound..<end]).trimmingCharacters(in: .whitespaces))
                        break
                    }
                }
            }
            // 3. Desde el nombre de la imagen
            if title.isEmpty {
                let slug = imgFilename.split(separator: ".").first.map(String.init) ?? imgFilename
                let words = slug.split(separator: "-").filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
                title = HTMLText.capitalizeWords(words.joined(separator: " "))
            }
            if title.isEmpty { title = "MotionBGS \(mediaID)" }

            let is4K = imgFilename.lowercased().contains("4k") || imgFilename.contains("3840x2160")
            let res: String
            let full: String
            if preferredResolution.lowercased() == "hd" || !is4K {
                res = "1080p HD"; full = "https://motionbgs.com/dl/hd/\(mediaID)/"
            } else {
                res = "4K UHD"; full = "https://motionbgs.com/dl/4k/\(mediaID)/"
            }

            items.append(OnlineItem(
                id: mediaID,
                title: title,
                author: "MotionBGS (\(catLabel))",
                thumbURL: "https://motionbgs.com/i/c/364x205/media/\(mediaID)/\(imgFilename).jpg",
                fullURL: full,
                resolution: res,
                source: .motionBGS,
                date: nil
            ))
        }
        return items
    }

    static func find(_ hay: [UInt8], _ needle: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        let first = needle[0]
        var i = from
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == first {
                var j = 1
                while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }

    static func rfind(_ hay: [UInt8], _ needle: [UInt8], before: Int) -> Int? {
        var i = min(before, hay.count) - needle.count
        while i >= 0 {
            var j = 0
            while j < needle.count && hay[i + j] == needle[j] { j += 1 }
            if j == needle.count { return i }
            i -= 1
        }
        return nil
    }
}
