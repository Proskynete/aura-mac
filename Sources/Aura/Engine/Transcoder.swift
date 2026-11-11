import Foundation
import CryptoKit
import AuraCore

/// AVFoundation no reproduce WebM, MKV ni AVI. Si ffmpeg está instalado
/// (`brew install ffmpeg`), Aura los convierte una sola vez a HEVC usando el
/// codificador por hardware de Apple y guarda el resultado en caché.
enum Transcoder {
    static var ffmpegPath: String? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // Las apps abiertas desde el Dock no heredan el PATH de la terminal.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let p = "\(dir)/ffmpeg"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var isAvailable: Bool { ffmpegPath != nil }

    /// Clave estable según ruta, tamaño y fecha de modificación.
    static func cacheKey(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let digest = SHA256.hash(data: Data("\(url.path)|\(size)|\(mod)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(24))
    }

    static func cachedOutput(for url: URL) -> URL {
        AuraPaths.transcodeDir.appendingPathComponent("\(cacheKey(for: url)).mp4")
    }

    /// Devuelve una URL reproducible: la original o la versión convertida.
    static func playableURL(for url: URL) -> URL? {
        guard MediaTypes.needsTranscode(url) else { return url }
        let out = cachedOutput(for: url)
        return FileManager.default.fileExists(atPath: out.path) ? out : nil
    }

    enum Failure: LocalizedError {
        case missingFFmpeg
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingFFmpeg:
                return tr("Este formato necesita ffmpeg. Instálalo con: brew install ffmpeg",
                          "This format needs ffmpeg. Install it with: brew install ffmpeg")
            case .failed(let msg):
                return tr("No se pudo convertir el video: \(msg)", "Could not convert the video: \(msg)")
            }
        }
    }

    /// Convierte el video. Primero intenta HEVC por hardware (VideoToolbox) y,
    /// si esa variante de ffmpeg no lo soporta, cae a H.264 por software.
    static func transcode(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = ffmpegPath else { throw Failure.missingFFmpeg }
        let out = cachedOutput(for: url)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        let tmp = out.deletingPathExtension().appendingPathExtension("part.mp4")
        try? FileManager.default.removeItem(at: tmp)

        let duration = await probeDuration(ffmpeg: ffmpeg, url: url)
        let attempts: [[String]] = [
            ["-c:v", "hevc_videotoolbox", "-b:v", "16M", "-tag:v", "hvc1", "-allow_sw", "1"],
            ["-c:v", "h264_videotoolbox", "-b:v", "20M"],
            ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20"],
        ]
        var lastError = ""
        for videoArgs in attempts {
            let args = ["-hide_banner", "-nostdin", "-y", "-i", url.path] + videoArgs +
                ["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart",
                 "-progress", "pipe:1", "-loglevel", "error", tmp.path]
            do {
                try await run(ffmpeg, args) { line in
                    // "out_time_us=12345678"
                    guard duration > 0, line.hasPrefix("out_time_us="),
                          let us = Double(line.dropFirst("out_time_us=".count)) else { return }
                    progress(min(1, us / 1_000_000 / duration))
                }
                try FileManager.default.moveItem(at: tmp, to: out)
                progress(1)
                return out
            } catch {
                lastError = error.localizedDescription
                try? FileManager.default.removeItem(at: tmp)
            }
        }
        throw Failure.failed(lastError)
    }

    /// Extrae un fotograma JPEG (para miniaturas de formatos no nativos).
    static func extractFrame(_ url: URL, to out: URL, width: Int = 480) async -> Bool {
        guard let ffmpeg = ffmpegPath else { return false }
        let args = ["-hide_banner", "-nostdin", "-y", "-ss", "1", "-i", url.path, "-frames:v", "1",
                    "-vf", "scale=\(width):-2", "-q:v", "4", "-loglevel", "error", out.path]
        do {
            try await run(ffmpeg, args, onLine: { _ in })
            return FileManager.default.fileExists(atPath: out.path)
        } catch {
            return false
        }
    }

    private static func probeDuration(ffmpeg: String, url: URL) async -> Double {
        // `ffmpeg -i` imprime "Duration: 00:01:23.45" en stderr.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-nostdin", "-i", url.path]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let r = text.range(of: "Duration: ") else { return 0 }
        let parts = text[r.upperBound...].prefix(11).split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return 0 }
        return h * 3600 + m * 60 + s
    }

    private static func run(_ exe: String, _ args: [String], onLine: @escaping @Sendable (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            let buffer = Box(Data())
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else { return }
                var lines: [String] = []
                buffer.mutate { buf in
                    buf.append(chunk)
                    while let nl = buf.firstIndex(of: 0x0A) {
                        lines.append(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self))
                        buf.removeSubrange(buf.startIndex...nl)
                    }
                }
                lines.forEach(onLine)
            }
            // stderr se drena mientras ffmpeg corre: si se leyera recién al final y
            // ffmpeg escribiera más de lo que cabe en el pipe (~64 KB), quedaría bloqueado.
            // Solo se guardan los últimos 8 KB, que es donde está el mensaje de error.
            let errBuffer = Box(Data())
            err.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else { return }
                errBuffer.mutate { buf in
                    buf.append(chunk)
                    if buf.count > 8192 { buf.removeFirst(buf.count - 8192) }
                }
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                let rest = err.fileHandleForReading.readDataToEndOfFile()
                errBuffer.mutate { $0.append(rest) }
                let errText = String(decoding: errBuffer.value, as: UTF8.self)
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let msg = errText.split(separator: "\n").last.map(String.init) ?? "ffmpeg \(proc.terminationStatus)"
                    cont.resume(throwing: Failure.failed(msg))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: Failure.failed(error.localizedDescription)) }
        }
    }
}
