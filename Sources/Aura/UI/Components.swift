import SwiftUI
import AppKit
import AuraCore

/// Miniatura local con carga perezosa desde la caché.
struct ThumbnailImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    @ViewState private var image: NSImage? = nil
    @ViewState private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: failed ? "exclamationmark.triangle" : (MediaTypes.kind(of: URL(fileURLWithPath: path)) == .video ? "film" : "photo"))
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: path) {
            image = nil
            failed = false
            if let url = await Thumbnailer.shared.thumbnail(for: path), let img = NSImage(contentsOf: url) {
                withAnimation(.easeOut(duration: 0.2)) { image = img }
            } else {
                failed = true
            }
        }
    }
}

/// Miniatura de un catálogo online.
struct RemoteThumbnail: View {
    let item: OnlineItem
    @ViewState private var image: NSImage? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Rectangle().fill(.quaternary)
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .task(id: item.id) {
            let img = await RemoteImageCache.shared.image(for: item)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

/// Hexágono con vértices arriba y abajo (estilo panal).
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.25))
        p.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.75))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.75))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.25))
        p.closeSubpath()
        return p
    }
}

/// Insignia pequeña (Video / Imagen / resolución).
struct Badge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .black.opacity(0.55)

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint, in: Capsule())
        .foregroundStyle(.white)
    }
}

/// Aviso flotante que no desplaza el contenido.
struct ToastView: View {
    let toast: Toast
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(toast.message).font(.callout).lineLimit(3)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) { action(); onClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button { onClose() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .frame(maxWidth: 620)
    }

    private var icon: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch toast.kind {
        case .info: return .blue
        case .success: return .green
        case .error: return .orange
        }
    }
}

/// Fila de ajustes: título, descripción y control a la derecha.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

extension View {
    /// Tarjeta con fondo material y borde sutil.
    func card(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

@MainActor
func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

@MainActor
func openInFinder(_ path: String) {
    AuraPaths.ensure(URL(fileURLWithPath: path))
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}
