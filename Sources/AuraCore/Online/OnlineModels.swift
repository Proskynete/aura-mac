import Foundation

public enum OnlineSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case bing
    case wallhaven
    case minimalistic
    case motionBGS = "motionbgs"
    case liveWallpapers4Free = "livewallpapers4free"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bing: return "Bing UHD"
        case .wallhaven: return "Wallhaven"
        case .minimalistic: return "Minimalistic"
        case .motionBGS: return "MotionBGS"
        case .liveWallpapers4Free: return "LiveWallpapers4Free"
        }
    }

    /// Fuentes de video (fondos animados).
    public var isLive: Bool { self == .motionBGS || self == .liveWallpapers4Free }

    var filePrefix: String {
        switch self {
        case .bing: return "bing"
        case .wallhaven: return "wallhaven"
        case .minimalistic: return "minimal"
        case .motionBGS: return "motionbgs"
        case .liveWallpapers4Free: return "livewallpapers4free"
        }
    }
}

public struct OnlineItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let thumbURL: String
    public let fullURL: String
    public let resolution: String
    public let source: OnlineSource
    public let date: String?

    public init(id: String, title: String, author: String, thumbURL: String, fullURL: String,
                resolution: String, source: OnlineSource, date: String?) {
        self.id = id; self.title = title; self.author = author
        self.thumbURL = thumbURL; self.fullURL = fullURL
        self.resolution = resolution; self.source = source; self.date = date
    }

    public var isVideo: Bool { fileExtension == "mp4" || fileExtension == "webm" }

    public var fileExtension: String {
        if source.isLive || fullURL.contains(".mp4") || fullURL.contains("/dl/") || fullURL.contains("/download/") {
            return "mp4"
        } else if fullURL.contains(".webm") {
            return "webm"
        } else if fullURL.hasSuffix(".png") {
            return "png"
        } else if fullURL.hasSuffix(".webp") {
            return "webp"
        }
        return "jpg"
    }

    /// Nombre de archivo legible, igual que `wallpaper_filename()` del original.
    public var wallpaperFilename: String {
        let ext = fileExtension
        switch source {
        case .motionBGS:
            let clean = FileNames.cleanTitle(title)
            let res = (resolution.contains("1080") || fullURL.contains("/dl/hd/")) ? "1080p" : "4k"
            if clean.isEmpty || clean == "MotionBGS" || clean == "MotionBGS Wallpaper" {
                return FileNames.clean(prefix: source.filePrefix, id: "\(id)_\(res)", ext: ext)
            }
            return "\(clean) - \(id)-\(res).\(ext)"
        case .bing:
            let clean = FileNames.cleanTitle(title)
            if clean == "Bing Wallpaper" {
                return "Bing Wallpaper - \(id.prefix(8)).\(ext)"
            }
            return "\(clean).\(ext)"
        case .wallhaven:
            return FileNames.clean(prefix: source.filePrefix, id: id, ext: ext)
        case .minimalistic:
            let t = FileNames.cleanTitle(title)
            let a = FileNames.cleanTitle(author)
            if !a.isEmpty && a != "Minimalist" { return "\(a) - \(t).\(ext)" }
            return "\(t).\(ext)"
        case .liveWallpapers4Free:
            let clean = FileNames.cleanTitle(title)
            let quality = resolution.split(separator: " ").first.map { $0.lowercased() } ?? "video"
            return "\(clean) - \(id)-\(quality).\(ext)"
        }
    }

    public var localURL: URL { AuraPaths.downloadsDir.appendingPathComponent(wallpaperFilename) }

    public var thumbCacheURL: URL {
        AuraPaths.onlineCacheDir.appendingPathComponent(FileNames.clean(prefix: source.filePrefix, id: id, ext: "jpg"))
    }

    /// Ruta local si ya se descargó (archivos de más de 1 KB).
    public var downloadedURL: URL? {
        let url = localURL
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64, size > 1024 {
            return url
        }
        return nil
    }
}

/// Una página de resultados de un catálogo.
public struct OnlinePage: Sendable {
    public let items: [OnlineItem]
    public let hasMore: Bool

    public init(items: [OnlineItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// Parámetros de búsqueda comunes a todos los catálogos.
public struct OnlineQuery: Equatable, Sendable {
    public var source: OnlineSource
    public var page: Int = 1
    public var search: String = ""
    public var category: String = "all"
    public var resolution: String = "4k"
    /// Solo Wallhaven: toplist, date_added, random, views, favorites, relevance.
    public var sorting: String = "toplist"

    public init(source: OnlineSource) {
        self.source = source
        switch source {
        case .wallhaven: category = "111"
        case .motionBGS: resolution = "4k"
        default: break
        }
    }
}

public enum FileNames {
    /// Limpia un título para usarlo como nombre de archivo (como `clean_title_filename`).
    public static func cleanTitle(_ title: String) -> String {
        var out = ""
        for ch in title {
            switch ch {
            case "/", "\\", ":", "|": out.append("-")
            case "*", "?", "\"", "<", ">": out.append(" ")
            default:
                if ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                    out.append(" ")
                } else {
                    out.append(ch)
                }
            }
        }
        let joined = out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimSet = CharacterSet(charactersIn: ".-_ ")
        let trimmed = joined.trimmingCharacters(in: trimSet)
        if trimmed.isEmpty { return "Bing Wallpaper" }
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)).trimmingCharacters(in: trimSet)
        }
        return trimmed
    }

    public static func clean(prefix: String, id: String, ext: String) -> String {
        let safe = id.map { c -> Character in
            ((c.isASCII && (c.isLetter || c.isNumber)) || c == "-" || c == "_") ? c : "_"
        }
        return "\(prefix)_\(String(safe)).\(ext)"
    }
}

public enum OnlineError: LocalizedError {
    case http(Int, String)
    case empty(String)
    case parse(String)
    case network(String)
    case badContent(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let src): return tr("\(src) respondió con el código HTTP \(code).", "\(src) returned HTTP \(code).")
        case .empty(let src): return tr("No se encontraron fondos en \(src).", "No wallpapers found on \(src).")
        case .parse(let src): return tr("No se pudo leer la respuesta de \(src).", "Could not parse the response from \(src).")
        case .network(let msg): return tr("Error de red: \(msg)", "Network error: \(msg)")
        case .badContent(let msg): return msg
        }
    }
}
