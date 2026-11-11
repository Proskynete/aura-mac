import AppKit
import CoreGraphics

/// Una pantalla conectada, identificada por su UUID estable
/// (no cambia al reconectarla, a diferencia del número de pantalla).
struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    /// Marco en coordenadas de AppKit (origen abajo a la izquierda).
    let frame: CGRect
    /// Marco en coordenadas globales de Quartz (origen arriba a la izquierda).
    let cgBounds: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat
    let isMain: Bool

    var resolutionLabel: String { "\(pixelWidth)×\(pixelHeight)" }

    static func uuid(for displayID: CGDirectDisplayID) -> String {
        if let cf = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let s = CFUUIDCreateString(nil, cf) {
            return s as String
        }
        return "display-\(displayID)"
    }

    @MainActor
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @MainActor
    static func current() -> [DisplayInfo] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let did = displayID(of: screen) else { return nil }
            let mode = CGDisplayCopyDisplayMode(did)
            return DisplayInfo(
                id: uuid(for: did),
                displayID: did,
                name: screen.localizedName,
                frame: screen.frame,
                cgBounds: CGDisplayBounds(did),
                pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor),
                scale: screen.backingScaleFactor,
                isMain: did == mainID
            )
        }
    }

    @MainActor
    func screen() -> NSScreen? {
        NSScreen.screens.first { DisplayInfo.displayID(of: $0) == displayID }
    }
}
