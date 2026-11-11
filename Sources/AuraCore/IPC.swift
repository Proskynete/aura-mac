import Foundation

/// Comunicación entre el comando `aura` y la app en ejecución mediante
/// notificaciones distribuidas de macOS (equivalente al D-Bus del original).
public enum IPC {
    public static let commandName = Notification.Name("io.github.aura.macos.command")
    public static let replyName = Notification.Name("io.github.aura.macos.reply")

    public enum Key {
        public static let command = "cmd"
        public static let argument = "arg"
        public static let replyID = "rid"
        public static let ok = "ok"
        public static let message = "msg"
    }
}

public enum IPCCommand: String, CaseIterable, Sendable {
    case ping
    case show
    case switcher
    case next
    case prev
    case togglePause = "toggle-pause"
    case pause
    case resume
    case stop
    case apply
    case status
    case volume
    case mute
    case themeMode = "theme-mode"
    case rescan
    case quit
}

/// Estado publicado por la app (también se guarda en state.json).
public struct AuraStatus: Codable, Sendable {
    public var running: Bool
    public var paused: Bool
    public var pauseReasons: [String]
    public var current: String?
    public var displays: [DisplayStatus]
    public var volume: Int
    public var muted: Bool
    public var rotation: Bool
    public var rotationInterval: Int
    public var themeMode: String
    public var libraryCount: Int
    public var updated: Date

    public struct DisplayStatus: Codable, Sendable {
        public var id: String
        public var name: String
        public var resolution: String
        public var wallpaper: String?
        public var scaling: String
        public var playing: Bool

        public init(id: String, name: String, resolution: String, wallpaper: String?, scaling: String, playing: Bool) {
            self.id = id; self.name = name; self.resolution = resolution
            self.wallpaper = wallpaper; self.scaling = scaling; self.playing = playing
        }
    }

    public init(running: Bool, paused: Bool, pauseReasons: [String], current: String?, displays: [DisplayStatus],
                volume: Int, muted: Bool, rotation: Bool, rotationInterval: Int, themeMode: String,
                libraryCount: Int, updated: Date) {
        self.running = running; self.paused = paused; self.pauseReasons = pauseReasons
        self.current = current; self.displays = displays; self.volume = volume; self.muted = muted
        self.rotation = rotation; self.rotationInterval = rotationInterval; self.themeMode = themeMode
        self.libraryCount = libraryCount; self.updated = updated
    }

    public func jsonString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    public static func load() -> AuraStatus? {
        guard let data = try? Data(contentsOf: AuraPaths.stateFile) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(AuraStatus.self, from: data)
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) { try? AuraPaths.atomicWrite(data, to: AuraPaths.stateFile) }
    }
}

/// Caja mutable segura para compartir un valor con closures `@Sendable`
/// (respuestas de notificaciones, handlers de procesos).
public final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    public init(_ value: T) { _value = value }

    public var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }

    public func mutate(_ body: (inout T) -> Void) {
        lock.lock(); body(&_value); lock.unlock()
    }
}
