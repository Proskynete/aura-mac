import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public var hex: String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

public struct PaletteResult: Equatable, Sendable {
    public let dominant: RGB
    public let isDark: Bool
    /// Luminancia media 0…255.
    public let averageLuminance: Double
}

/// Misma lógica que `theme/palette.rs` del original: el color más "vibrante"
/// (saturación × valor) y la luminancia ponderada Y = 0.299R + 0.587G + 0.114B.
public enum Palette {
    public static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let delta = mx - mn
        let v = mx
        let s = mx == 0 ? 0 : delta / mx
        var h: Double
        if delta == 0 {
            h = 0
        } else if mx == r {
            h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if mx == g {
            h = 60 * ((b - r) / delta + 2)
        } else {
            h = 60 * ((r - g) / delta + 4)
        }
        if h < 0 { h += 360 }
        return (h, s, v)
    }

    /// Analiza píxeles RGBA de 8 bits (idealmente una muestra reducida, p. ej. 100×100).
    public static func analyze(rgba: [UInt8], bytesPerPixel: Int = 4) -> PaletteResult? {
        let count = rgba.count / bytesPerPixel
        guard count > 0 else { return nil }

        var bestVibrancy = -1.0
        var best = RGB(r: 1, g: 0.5, b: 0)
        var totalLum = 0.0

        for i in 0..<count {
            let o = i * bytesPerPixel
            let r8 = Double(rgba[o]), g8 = Double(rgba[o + 1]), b8 = Double(rgba[o + 2])
            let r = r8 / 255, g = g8 / 255, b = b8 / 255
            let (_, s, v) = rgbToHSV(r, g, b)
            if v > 0.15 && v < 0.97 {
                let vibrancy = s * v
                if vibrancy > bestVibrancy {
                    bestVibrancy = vibrancy
                    best = RGB(r: r, g: g, b: b)
                }
            }
            totalLum += 0.299 * r8 + 0.587 * g8 + 0.114 * b8
        }

        let avg = totalLum / Double(count)
        let isDark = avg < 128
        if bestVibrancy < 0.06 {
            // Imagen monocromática: tono pizarra neutro en vez de naranja.
            best = isDark ? RGB(r: 0.45, g: 0.55, b: 0.65) : RGB(r: 0.35, g: 0.45, b: 0.55)
        }
        return PaletteResult(dominant: best, isDark: isDark, averageLuminance: avg)
    }

    /// macOS solo admite 8 colores de acento. Devuelve el valor de
    /// `AppleAccentColor` más cercano en tono (-1 = grafito).
    /// Valores: -1 grafito, 0 rojo, 1 naranja, 2 amarillo, 3 verde, 4 azul, 5 morado, 6 rosa.
    public static func nearestSystemAccent(_ color: RGB) -> Int {
        let (h, s, _) = rgbToHSV(color.r, color.g, color.b)
        if s < 0.18 { return -1 }
        let hues: [(Int, Double)] = [(0, 0), (1, 30), (2, 52), (3, 120), (4, 212), (5, 278), (6, 330), (0, 360)]
        var bestID = 4
        var bestDist = Double.greatestFiniteMagnitude
        for (id, hue) in hues {
            let d = abs(h - hue)
            if d < bestDist { bestDist = d; bestID = id }
        }
        return bestID
    }
}
