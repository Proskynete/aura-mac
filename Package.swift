// swift-tools-version:5.9
//
// Aura para macOS — port nativo en Swift de Aura (https://github.com/antwny/aura).
// Licencia GPL-3.0-or-later, igual que el proyecto original.

import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aura", targets: ["Aura"]),
        .executable(name: "aura-cli", targets: ["aura-cli"]),
    ],
    targets: [
        // Lógica pura (configuración, catálogos online, paleta, IPC).
        // Solo depende de Foundation para poder probarse sin interfaz.
        .target(
            name: "AuraCore",
            path: "Sources/AuraCore"
        ),
        // La app: motor de fondos, barra de menú, selector rápido e interfaz SwiftUI.
        .executableTarget(
            name: "Aura",
            dependencies: ["AuraCore"],
            path: "Sources/Aura",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Comando de terminal `aura` (next, prev, toggle-pause, apply, status…).
        .executableTarget(
            name: "aura-cli",
            dependencies: ["AuraCore"],
            path: "Sources/aura-cli"
        ),
        .testTarget(
            name: "AuraCoreTests",
            dependencies: ["AuraCore"],
            path: "Tests/AuraCoreTests"
        ),
    ]
)
