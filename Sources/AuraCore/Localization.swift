import Foundation

/// Idiomas de la interfaz. Igual que el original, español e inglés con
/// detección automática del idioma del sistema.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case auto
    case es
    case en

    /// Idioma efectivo (resuelve `auto` con el idioma preferido del sistema).
    public var resolved: AppLanguage {
        guard self == .auto else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("es") ? .es : .en
    }
}

/// Idioma activo para `tr`. Se actualiza desde la configuración al iniciar y
/// cada vez que el usuario lo cambia en Ajustes.
public enum Localizer {
    private static let lock = NSLock()
    private static var _current: AppLanguage = AppLanguage.auto.resolved

    public static var current: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); _current = newValue.resolved; lock.unlock() }
    }
}

/// Traducción en línea: `tr("Biblioteca", "Library")`.
/// Mantener las dos versiones juntas evita tablas de claves desincronizadas.
public func tr(_ es: String, _ en: String) -> String {
    Localizer.current == .es ? es : en
}
