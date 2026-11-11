import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTP {
    public static let userAgent = "Aura-LiveWallpaper-Client/\(AuraConfig.currentVersion) (macOS)"
    public static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: cfg)
    }()

    /// GET que devuelve el cuerpo y la respuesta, fallando en códigos no 2xx.
    public static func get(
        _ url: URL,
        source: String,
        timeout: TimeInterval = 15,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
        } catch {
            throw OnlineError.network(error.localizedDescription)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw OnlineError.parse(source) }
        guard (200..<300).contains(http.statusCode) else { throw OnlineError.http(http.statusCode, source) }
        return (data, http)
    }

    public static func url(_ base: String, _ query: [(String, String)]) -> URL? {
        var comps = URLComponents(string: base)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return comps?.url
    }

    /// Lee un JSON cacheado en disco si tiene menos de `maxAge` segundos.
    static func cached(_ file: URL, maxAge: TimeInterval) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file), data.count > 100 else { return nil }
        return data
    }
}

/// Utilidades mínimas para leer HTML sin dependencias externas
/// (equivalentes a las funciones del scraper en Rust).
public enum HTMLText {
    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            guard let semi = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semi) <= 10 else {
                out.append("&")
                rest = rest.dropFirst()
                continue
            }
            let entity = rest[rest.index(after: rest.startIndex)..<semi]
            var replacement: String?
            switch entity {
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "quot": replacement = "\""
            case "apos", "#39": replacement = "'"
            case "nbsp": replacement = " "
            case "ndash": replacement = "–"
            case "mdash": replacement = "—"
            case "hellip": replacement = "…"
            case "rsquo", "lsquo": replacement = "'"
            case "rdquo", "ldquo": replacement = "\""
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
                   let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    replacement = String(Character(scalar))
                } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                    replacement = String(Character(scalar))
                }
            }
            if let replacement {
                out += replacement
                rest = rest[rest.index(after: semi)...]
            } else {
                out.append("&")
                rest = rest.dropFirst()
            }
        }
        out += rest
        return out
    }

    /// Valor de un atributo dentro de una etiqueta (`<a class="x" href='y'>`).
    public static func attribute(_ tag: String, _ name: String) -> String? {
        let chars = Array(tag)
        var i = 0
        // Salta "<tag"
        while i < chars.count && !chars[i].isWhitespace && chars[i] != ">" { i += 1 }
        while i < chars.count {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            let keyStart = i
            while i < chars.count && !chars[i].isWhitespace && chars[i] != "=" && chars[i] != ">" { i += 1 }
            if keyStart == i { i += 1; continue }
            let key = String(chars[keyStart..<i])
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            guard i < chars.count, chars[i] == "=" else { continue }
            i += 1
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { return nil }
            let q = chars[i]
            var value: String
            if q == "\"" || q == "'" {
                i += 1
                let vs = i
                while i < chars.count && chars[i] != q { i += 1 }
                value = String(chars[vs..<min(i, chars.count)])
                i += 1
            } else {
                let vs = i
                while i < chars.count && !chars[i].isWhitespace && chars[i] != ">" { i += 1 }
                value = String(chars[vs..<i])
            }
            if key.caseInsensitiveCompare(name) == .orderedSame { return value }
        }
        return nil
    }

    /// Texto plano sin etiquetas y con espacios normalizados.
    public static func plainText(_ html: String) -> String {
        var text = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true }
            else if ch == ">" { inTag = false; text.append(" ") }
            else if !inTag { text.append(ch) }
        }
        return decodeEntities(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func capitalizeWords(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).map { w in
            guard let f = w.first else { return "" }
            return f.uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }
}
