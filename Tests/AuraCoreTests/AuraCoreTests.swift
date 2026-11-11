import Foundation
import Testing
@testable import AuraCore

@Suite struct PaletteTests {
    @Test func rgbToHSV() {
        let red = Palette.rgbToHSV(1, 0, 0)
        #expect(abs(red.h - 0) < 0.01)
        #expect(abs(red.s - 1) < 0.01)
        #expect(abs(red.v - 1) < 0.01)
        let blue = Palette.rgbToHSV(0, 0, 1)
        #expect(abs(blue.h - 240) < 0.01)
    }

    @Test func darkAndVibrant() throws {
        // 100 píxeles casi negros y uno naranja intenso.
        var px: [UInt8] = []
        for _ in 0..<100 { px += [10, 10, 12, 255] }
        px += [240, 120, 20, 255]
        let r = try #require(Palette.analyze(rgba: px))
        #expect(r.isDark)
        #expect(abs(r.dominant.r - (240.0 / 255)) < 0.01)
    }

    @Test func monochromeFallsBackToSlate() throws {
        let px = [UInt8](repeating: 200, count: 400)
        let r = try #require(Palette.analyze(rgba: px))
        #expect(!r.isDark)
        #expect(r.dominant == RGB(r: 0.35, g: 0.45, b: 0.55))
    }

    @Test func nearestAccent() {
        #expect(Palette.nearestSystemAccent(RGB(r: 0.1, g: 0.3, b: 0.9)) == 4)
        #expect(Palette.nearestSystemAccent(RGB(r: 0.5, g: 0.5, b: 0.5)) == -1)
    }
}

@Suite struct ConfigTests {
    @Test func decodesPartialAndInvalidValues() throws {
        let json = #"{"volume": 250, "theme_mode": "neon", "rotation": true, "interval": 0}"#
        let cfg = try JSONDecoder().decode(AuraConfig.self, from: Data(json.utf8))
        #expect(cfg.volume == 100)
        #expect(cfg.themeMode == .auto)
        #expect(cfg.rotation)
        #expect(cfg.interval == 1)
    }

    @Test func roundTrip() throws {
        var cfg = AuraConfig()
        cfg.scaling = ["*": .fit, "ABC": .stretch]
        cfg.autoPauseMode = .anyWindow
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AuraConfig.self, from: data)
        #expect(back == cfg)
        #expect(back.scaling(for: "ABC") == .stretch)
        #expect(back.scaling(for: "XYZ") == .fit)
    }

    @Test func autoThemeIsOffByDefault() throws {
        #expect(AuraConfig().autoTheme == false)
        // Una configuración vieja sin el campo también queda apagada.
        let cfg = try JSONDecoder().decode(AuraConfig.self, from: Data("{}".utf8))
        #expect(cfg.autoTheme == false)
    }

    @Test func autoPauseThresholds() {
        #expect(AutoPauseMode.partial.shouldPause(coverage: 0.3))
        #expect(!AutoPauseMode.full.shouldPause(coverage: 0.9))
        #expect(AutoPauseMode.anyWindow.shouldPause(coverage: 0.02))
    }

    @Test func history() {
        var cfg = AuraConfig()
        for i in 0..<60 { cfg.pushHistory("/w/\(i).mp4") }
        cfg.pushHistory("/w/10.mp4")
        #expect(cfg.history.count == 50)
        #expect(cfg.history.last == "/w/10.mp4")
    }
}

@Suite struct CatalogTests {
    @Test func bingTitleFromURLBase() {
        #expect(BingCatalog.titleFromURLBase("/th?id=OHR.FieldsOfGold_EN-US123") == "Fields Of Gold")
    }

    @Test func motionBGSParse() {
        let html = """
        <html><head><meta content="/media/1/x.jpg"></head><body>
        <a href="/celestial-battle" title="Celestial Battle Gojo Vs Mahoraga live wallpaper">
        <img src="/i/c/364x205/media/9967/celestial-battle-gojo-vs-mahoraga.3840x2160.jpg"></a>
        <a href="/rain"><img src="/i/c/364x205/media/10102/rainy-night.jpg"><span class=ttl>Rainy &amp; Night</span></a>
        </body></html>
        """
        let items = MotionBGSCatalog.parse(html: html, preferredResolution: "4k", category: "anime")
        #expect(items.count == 2)
        #expect(items[0].id == "9967")
        #expect(items[0].title == "Celestial Battle Gojo Vs Mahoraga")
        #expect(items[0].fullURL == "https://motionbgs.com/dl/4k/9967/")
        #expect(items[1].title == "Rainy & Night")
        #expect(items[1].fullURL == "https://motionbgs.com/dl/hd/10102/")
        #expect(MotionBGSCatalog.catalogURL(category: "anime", page: 3) == "https://motionbgs.com/tag:anime/3/")
    }

    @Test func lw4fVariants() {
        let html = """
        <a class="kgvid-download-link" href="https://livewallpapers4free.com/wp-content/uploads/preview.mp4">Preview</a>
        <a class="dlm-download-link" href="https://livewallpapers4free.com/download/53887/">ada-wong-rainfall-HD-live.mp4 (download)</a>
        <a class="dlm-download-link" href="https://livewallpapers4free.com/download/53881/">ada-wong-rainfall-4k-live.mp4 (download)</a>
        """
        let v = LiveWallpapers4FreeCatalog.parseDownloadVariants(html)
        #expect(v.count == 2)
        #expect(LiveWallpapers4FreeCatalog.selectVariant(v, requested: .fourK)?.url == "https://livewallpapers4free.com/download/53881/")
        #expect(LiveWallpapers4FreeCatalog.selectVariant(v, requested: .twoK)?.url == "https://livewallpapers4free.com/download/53887/")
    }

    @Test func minimalFilename() {
        let (t, a) = MinimalisticCatalog.parseFilename("alena-aenami-clouds.jpg")
        #expect(t == "Clouds")
        #expect(a == "Alena Aenami")
    }

    @Test func fileNames() {
        #expect(FileNames.clean(prefix: "bing", id: "a/b c", ext: "jpg") == "bing_a_b_c.jpg")
        #expect(FileNames.cleanTitle("  Hello: World?  ") == "Hello- World")
        #expect(HTMLText.decodeEntities("A &amp; B &#39;x&#39; &#x41;") == "A & B 'x' A")
        #expect(HTMLText.attribute("<a class='x y' href=\"/z\">", "href") == "/z")
    }
}

@Suite struct LibraryTests {
    private func item(_ name: String, video: Bool) -> WallpaperItem {
        WallpaperItem(path: "/w/\(name)", name: name, kind: video ? .video : .image, sizeBytes: 2048, modified: Date(), isDownloaded: false)
    }

    @Test func rotationPoolFilters() {
        let items = [item("a.mp4", video: true), item("b.jpg", video: false)]
        #expect(LibraryScanner.rotationPool(items, favorites: [], onlyFavorites: true, filter: .all).count == 2)
        #expect(LibraryScanner.rotationPool(items, favorites: [], onlyFavorites: false, filter: .live).map(\.name) == ["a.mp4"])
    }

    @Test func sequentialRotation() {
        let pool = [item("a", video: true), item("b", video: true), item("c", video: true)]
        var seq = 0
        let next = LibraryScanner.nextInRotation(pool: pool, current: "/w/c", order: .sequential, seqIndex: &seq)
        #expect(next?.name == "a")
        let random = LibraryScanner.nextInRotation(pool: pool, current: "/w/a", order: .random, seqIndex: &seq)
        #expect(random?.name != "a")
    }
}

@Suite struct PathsTests {
    /// El fondo de macOS debe sobrevivir a la limpieza de caché y a la desinstalación.
    @Test func systemFramesLiveOutsideCaches() {
        let frames = AuraPaths.framesDir.path
        #expect(!frames.hasPrefix(AuraPaths.cacheDir.path))
        #expect(frames.hasPrefix(AuraPaths.downloadsDir.path))
        #expect(AuraPaths.isAuraGeneratedFrame(frames + "/abc.jpg"))
        #expect(AuraPaths.isAuraGeneratedFrame(AuraPaths.legacyFramesDir.path + "/abc.jpg"))
        #expect(!AuraPaths.isAuraGeneratedFrame(AuraPaths.downloadsDir.path + "/foto.jpg"))
    }
}
