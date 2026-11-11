import Foundation
import AppKit
import AuraCore

/// Descargas de catálogos con progreso y cancelación. Guarda en
/// ~/Pictures/Wallpapers/Aura y rechaza respuestas que sean páginas de error.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    struct Job {
        let item: OnlineItem
        var progress: Double
        var applyWhenDone: Bool
        let task: URLSessionDownloadTask
    }

    @Published private(set) var jobs: [String: Job] = [:]

    /// Se llama con el archivo final (y si hay que aplicarlo).
    var onFinished: ((OnlineItem, URL, Bool) -> Void)?
    var onFailed: ((OnlineItem, String) -> Void)?

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": HTTP.userAgent]
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var itemsByTask: [Int: String] = [:]

    func progress(for item: OnlineItem) -> Double? { jobs[item.id]?.progress }

    func isDownloading(_ item: OnlineItem) -> Bool { jobs[item.id] != nil }

    func start(_ item: OnlineItem, apply: Bool) {
        if let existing = jobs[item.id] {
            jobs[item.id]?.applyWhenDone = existing.applyWhenDone || apply
            return
        }
        if let local = item.downloadedURL {
            onFinished?(item, local, apply)
            return
        }
        guard let url = URL(string: item.fullURL), ["https", "http"].contains(url.scheme ?? "") else {
            onFailed?(item, tr("Dirección de descarga no válida.", "Invalid download URL."))
            return
        }
        var request = URLRequest(url: url)
        if item.source == .motionBGS || item.source == .liveWallpapers4Free {
            request.setValue(HTTP.browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(item.source == .motionBGS ? "https://motionbgs.com/" : "https://livewallpapers4free.com/",
                             forHTTPHeaderField: "Referer")
        }
        let task = session.downloadTask(with: request)
        jobs[item.id] = Job(item: item, progress: 0, applyWhenDone: apply, task: task)
        itemsByTask[task.taskIdentifier] = item.id
        task.resume()
    }

    func cancel(_ item: OnlineItem) {
        guard let job = jobs.removeValue(forKey: item.id) else { return }
        itemsByTask[job.task.taskIdentifier] = nil
        job.task.cancel()
    }

    fileprivate func updateProgress(taskID: Int, value: Double) {
        guard let id = itemsByTask[taskID] else { return }
        jobs[id]?.progress = value
    }

    fileprivate func finish(taskID: Int, tempFile: URL?, response: URLResponse?, error: String?) {
        guard let id = itemsByTask.removeValue(forKey: taskID), let job = jobs.removeValue(forKey: id) else { return }
        if let error {
            onFailed?(job.item, error)
            return
        }
        guard let tempFile else {
            onFailed?(job.item, tr("La descarga no produjo ningún archivo.", "The download produced no file."))
            return
        }
        let dest = Self.uniqueDestination(job.item.localURL)
        do {
            AuraPaths.ensure(dest.deletingLastPathComponent())
            try FileManager.default.moveItem(at: tempFile, to: dest)
            onFinished?(job.item, dest, job.applyWhenDone)
        } catch {
            onFailed?(job.item, error.localizedDescription)
        }
    }

    static func uniqueDestination(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for i in 2..<10_000 {
            let c = dir.appendingPathComponent("\(stem) (\(i)).\(ext)")
            if !fm.fileExists(atPath: c.path) { return c }
        }
        return url
    }

    /// Valida que lo descargado sea un medio y no una página HTML/JSON de error.
    nonisolated static func validate(file: URL, response: URLResponse?) -> String? {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return tr("El servidor respondió con el código \(http.statusCode).", "The server returned HTTP \(http.statusCode).")
        }
        let type = (response?.mimeType ?? "").lowercased()
        if type.hasPrefix("text/") || type.contains("json") || type.contains("html") {
            return tr("El servidor devolvió una página en vez del archivo (\(type)).",
                      "The server returned a page instead of the file (\(type)).")
        }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 64)) ?? Data()
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if size < 1024 { return tr("El archivo descargado está vacío.", "The downloaded file is empty.") }
        if let first = head.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }),
           first == UInt8(ascii: "<") || first == UInt8(ascii: "{") || first == UInt8(ascii: "[") {
            return tr("El servidor devolvió una página de error.", "The server returned an error page.")
        }
        return nil
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let id = downloadTask.taskIdentifier
        Task { @MainActor in self.updateProgress(taskID: id, value: value) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // El archivo temporal se borra al salir de este método: hay que moverlo ya.
        let id = downloadTask.taskIdentifier
        let response = downloadTask.response
        if let problem = Self.validate(file: location, response: response) {
            Task { @MainActor in self.finish(taskID: id, tempFile: nil, response: response, error: problem) }
            return
        }
        let keep = AuraPaths.cacheDir.appendingPathComponent("download-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            Task { @MainActor in self.finish(taskID: id, tempFile: keep, response: response, error: nil) }
        } catch {
            let msg = error.localizedDescription
            Task { @MainActor in self.finish(taskID: id, tempFile: nil, response: response, error: msg) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let id = task.taskIdentifier
        let msg = error.localizedDescription
        Task { @MainActor in self.finish(taskID: id, tempFile: nil, response: task.response, error: msg) }
    }
}

/// Caché en disco de las miniaturas de los catálogos.
actor RemoteImageCache {
    static let shared = RemoteImageCache()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let memory = NSCache<NSString, NSImage>()

    func image(for item: OnlineItem) async -> NSImage? {
        let key = item.thumbCacheURL.path as NSString
        if let m = memory.object(forKey: key) { return m }
        if let disk = NSImage(contentsOf: item.thumbCacheURL) {
            memory.setObject(disk, forKey: key)
            return disk
        }
        if let t = inFlight[item.id] { return await t.value }
        let task = Task<NSImage?, Never>.detached(priority: .utility) {
            guard let url = URL(string: item.thumbURL) else { return nil }
            var headers: [String: String] = [:]
            if item.source == .motionBGS { headers = ["User-Agent": HTTP.browserUserAgent, "Referer": "https://motionbgs.com/"] }
            guard let result = try? await HTTP.get(url, source: item.source.displayName, timeout: 15, headers: headers),
                  let img = NSImage(data: result.0) else { return nil }
            try? result.0.write(to: item.thumbCacheURL, options: .atomic)
            return img
        }
        inFlight[item.id] = task
        let img = await task.value
        inFlight[item.id] = nil
        if let img { memory.setObject(img, forKey: key) }
        return img
    }
}
