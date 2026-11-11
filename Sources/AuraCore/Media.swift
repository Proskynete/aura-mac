import Foundation

public enum MediaKind: String, Codable, Sendable {
    case video
    case image
}

public enum MediaTypes {
    /// Extensiones que AVFoundation reproduce directamente.
    public static let nativeVideo: Set<String> = ["mp4", "mov", "m4v"]
    /// Extensiones que necesitan conversión previa con ffmpeg.
    public static let convertibleVideo: Set<String> = ["webm", "mkv", "avi"]
    public static let image: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif", "tiff", "bmp"]

    public static var video: Set<String> { nativeVideo.union(convertibleVideo) }
    public static var all: Set<String> { video.union(image) }

    public static func kind(of url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if video.contains(ext) { return .video }
        if image.contains(ext) { return .image }
        return nil
    }

    public static func needsTranscode(_ url: URL) -> Bool {
        convertibleVideo.contains(url.pathExtension.lowercased())
    }

    public static func isSupported(_ url: URL) -> Bool { kind(of: url) != nil }
}

/// Un fondo de la biblioteca local.
public struct WallpaperItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: MediaKind
    public let sizeBytes: Int64
    public let modified: Date
    /// Si está dentro de la carpeta de descargas de Aura.
    public let isDownloaded: Bool

    public init(path: String, name: String, kind: MediaKind, sizeBytes: Int64, modified: Date, isDownloaded: Bool) {
        self.path = path
        self.name = name
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.isDownloaded = isDownloaded
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var isVideo: Bool { kind == .video }

    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public enum LibraryScanner {
    /// Recorre las carpetas configuradas (con subcarpetas) y devuelve los fondos
    /// soportados, sin duplicados aunque una carpeta contenga a otra.
    public static func scan(dirs: [String]) -> [WallpaperItem] {
        let fm = FileManager.default
        let downloads = AuraPaths.downloadsDir.standardizedFileURL.path
        var seen = Set<String>()
        var items: [WallpaperItem] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]

        for dir in dirs {
            let root = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
            guard let walker = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in walker {
                guard let kind = MediaTypes.kind(of: url) else { continue }
                let path = url.standardizedFileURL.path
                // Archivos temporales de descargas en curso.
                if url.lastPathComponent.contains(".tmp.") || url.lastPathComponent.hasSuffix(".part") { continue }
                guard seen.insert(path).inserted else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile ?? false else { continue }
                let size = Int64(values?.fileSize ?? 0)
                if size < 1024 { continue }
                items.append(WallpaperItem(
                    path: path,
                    name: url.deletingPathExtension().lastPathComponent,
                    kind: kind,
                    sizeBytes: size,
                    modified: values?.contentModificationDate ?? .distantPast,
                    isDownloaded: path.hasPrefix(downloads)
                ))
            }
        }
        return items
    }

    public static func sorted(_ items: [WallpaperItem], by sort: LibrarySort) -> [WallpaperItem] {
        switch sort {
        case .newest: return items.sorted { $0.modified > $1.modified }
        case .oldest: return items.sorted { $0.modified < $1.modified }
        case .name: return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: return items.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    /// Fondos elegibles para la rotación automática. Igual que el original:
    /// "solo favoritos" sin favoritos marcados usa toda la biblioteca, pero el
    /// filtro por tipo es estricto.
    public static func rotationPool(
        _ items: [WallpaperItem],
        favorites: Set<String>,
        onlyFavorites: Bool,
        filter: RotationMediaFilter
    ) -> [WallpaperItem] {
        var base = items
        if onlyFavorites {
            let favs = items.filter { favorites.contains($0.path) }
            if !favs.isEmpty { base = favs }
        }
        return base.filter {
            switch filter {
            case .all: return true
            case .live: return $0.isVideo
            case .static: return !$0.isVideo
            }
        }
    }

    /// Elige el siguiente fondo de la rotación.
    public static func nextInRotation(
        pool: [WallpaperItem],
        current: String?,
        order: RotationOrder,
        seqIndex: inout Int
    ) -> WallpaperItem? {
        guard !pool.isEmpty else { return nil }
        switch order {
        case .sequential:
            if let current, let idx = pool.firstIndex(where: { $0.path == current }) {
                seqIndex = (idx + 1) % pool.count
            } else {
                seqIndex = seqIndex % pool.count
            }
            let item = pool[seqIndex]
            seqIndex = (seqIndex + 1) % pool.count
            return item
        case .random:
            if pool.count == 1 { return pool[0] }
            let candidates = pool.filter { $0.path != current }
            return candidates.randomElement() ?? pool[0]
        }
    }
}
