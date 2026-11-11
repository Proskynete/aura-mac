import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import AuraCore

/// Miniaturas en caché (~/Library/Caches/Aura/thumbs) para la biblioteca,
/// el selector rápido y la extracción de color.
actor Thumbnailer {
    static let shared = Thumbnailer()

    private var inFlight: [String: Task<URL?, Never>] = [:]

    nonisolated static func key(for path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let digest = SHA256.hash(data: Data("\(path)|\(mod)|\(size)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    nonisolated static func cachedURL(for path: String) -> URL {
        AuraPaths.thumbsDir.appendingPathComponent("\(key(for: path)).jpg")
    }

    /// Devuelve la miniatura (la genera si no existe).
    func thumbnail(for path: String, width: Int = 640) async -> URL? {
        let out = Self.cachedURL(for: path)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        if let task = inFlight[path] { return await task.value }
        let task = Task<URL?, Never>.detached(priority: .utility) {
            await Self.generate(path: path, out: out, width: width)
        }
        inFlight[path] = task
        let result = await task.value
        inFlight[path] = nil
        return result
    }

    private static func generate(path: String, out: URL, width: Int) async -> URL? {
        let url = URL(fileURLWithPath: path)
        guard let kind = MediaTypes.kind(of: url) else { return nil }
        if kind == .image {
            guard let img = WallpaperEngine.loadImage(url, maxPixelSize: width) else { return nil }
            return write(img, to: out)
        }
        if MediaTypes.needsTranscode(url) {
            // Usa la versión convertida si ya existe; si no, ffmpeg directamente.
            if let playable = Transcoder.playableURL(for: url), let img = await frame(of: playable, width: width) {
                return write(img, to: out)
            }
            return await Transcoder.extractFrame(url, to: out, width: width) ? out : nil
        }
        guard let img = await frame(of: url, width: width) else { return nil }
        return write(img, to: out)
    }

    /// Fotograma de un video al segundo 1 (o al inicio si es más corto).
    static func frame(of url: URL, width: Int, at seconds: Double = 1) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        if width > 0 { gen.maximumSize = CGSize(width: width, height: width) }
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        for t in [seconds, 0] {
            if let result = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                return result.image
            }
        }
        return nil
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, quality: Double = 0.82) -> URL? {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    /// Píxeles RGBA de una imagen reducida a 100×100 para la paleta.
    nonisolated static func samplePixels(_ url: URL) -> [UInt8]? {
        guard let img = WallpaperEngine.loadImage(url, maxPixelSize: 200) else { return nil }
        let w = 100, h = 100
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? pixels : nil
    }
}
