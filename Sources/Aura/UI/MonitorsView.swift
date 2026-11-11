import AppKit
import SwiftUI
import AuraCore

struct MonitorsView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var selected: String? = nil

    private var current: DisplayInfo? {
        model.displays.first { $0.id == selected } ?? model.displays.first(where: \.isMain) ?? model.displays.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("Pantallas", "Displays")).font(.title2.weight(.semibold))
                Text(tr("Disposición real de tus pantallas. Elige una para cambiar su fondo y cómo se ajusta.",
                        "Your actual display arrangement. Pick one to change its wallpaper and how it's scaled."))
                    .foregroundStyle(.secondary)

                canvas
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .card()

                if let d = current { details(d) }

                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Ajuste general", "Default scaling")).font(.headline)
                    Text(tr("Se usa en las pantallas sin un ajuste propio.", "Used on displays without their own setting."))
                        .font(.caption).foregroundStyle(.secondary)
                    ScalingPicker(selection: Binding(
                        get: { model.config.scaling["*"] ?? .fill },
                        set: { model.setScaling($0, for: "*") }
                    ))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(20)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let layout = CanvasLayout(displays: model.displays, size: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(model.displays) { d in
                    DisplayTile(display: d, selected: d.id == current?.id)
                        .frame(width: d.cgBounds.width * layout.scale, height: d.cgBounds.height * layout.scale)
                        .offset(layout.offset(for: d))
                        .onTapGesture { selected = d.id }
                }
            }
        }
    }

    private func details(_ d: DisplayInfo) -> some View {
        let path = model.engine.assignment(for: d.id)?.path
        return HStack(alignment: .top, spacing: 18) {
            Group {
                if let path {
                    ThumbnailImage(path: path)
                } else {
                    Rectangle().fill(.quaternary).overlay(Image(systemName: "display").font(.largeTitle).foregroundStyle(.tertiary))
                }
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(d.name).font(.headline)
                    if d.isMain { Badge(text: tr("Principal", "Main"), tint: .accentColor.opacity(0.8)) }
                }
                Text("\(d.resolutionLabel) · @\(Int(d.scale))x · \(Int(d.frame.width))×\(Int(d.frame.height)) pt")
                    .font(.caption).foregroundStyle(.secondary)
                Text(path.map { ($0 as NSString).lastPathComponent } ?? tr("Sin fondo", "No wallpaper"))
                    .font(.callout).lineLimit(1).truncationMode(.middle)

                ScalingPicker(selection: Binding(
                    get: { model.config.scaling[d.id] ?? model.config.scaling["*"] ?? .fill },
                    set: { model.setScaling($0, for: d.id) }
                ))

                HStack {
                    Button(tr("Elegir en la biblioteca", "Pick from library")) {
                        model.selectedDisplay = d.id
                        model.config.output = d.id
                        NotificationCenter.default.post(name: .auraNavigate, object: SidebarItem.library)
                    }
                    if model.config.wallpapers[d.id] != nil, let general = model.config.current {
                        Button(tr("Usar el fondo general", "Use the general wallpaper")) {
                            model.apply(path: general, target: "*")
                        }
                    }
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }
}

struct ScalingPicker: View {
    @Binding var selection: ScalingMode

    var body: some View {
        Picker("", selection: $selection) {
            Text(tr("Ajustar", "Fit")).tag(ScalingMode.fit)
            Text(tr("Rellenar", "Fill")).tag(ScalingMode.fill)
            Text(tr("Estirar", "Stretch")).tag(ScalingMode.stretch)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 300)
    }
}

/// Escala y posición de cada pantalla dentro del lienzo.
private struct CanvasLayout {
    let union: CGRect
    let scale: CGFloat
    let origin: CGPoint

    init(displays: [DisplayInfo], size: CGSize) {
        var u = CGRect.null
        for d in displays { u = u.union(d.cgBounds) }
        union = u
        let pad: CGFloat = 28
        if u.isNull || u.width <= 0 || u.height <= 0 {
            scale = 1
            origin = .zero
        } else {
            let sx: CGFloat = (size.width - pad * 2) / u.width
            let sy: CGFloat = (size.height - pad * 2) / u.height
            let s: CGFloat = max(0.01, min(sx, sy))
            scale = s
            origin = CGPoint(x: (size.width - u.width * s) / 2, y: (size.height - u.height * s) / 2)
        }
    }

    func offset(for d: DisplayInfo) -> CGSize {
        CGSize(width: origin.x + (d.cgBounds.minX - union.minX) * scale,
               height: origin.y + (d.cgBounds.minY - union.minY) * scale)
    }
}

private struct DisplayTile: View {
    @EnvironmentObject var model: AppModel
    let display: DisplayInfo
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let ring: AnyShapeStyle = selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.25))
        return ZStack {
            background
            label
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ring, lineWidth: selected ? 3 : 1))
        .overlay(alignment: .top) {
            if display.isMain {
                Capsule().fill(Color.white.opacity(0.8)).frame(width: 40, height: 3).padding(.top, 4)
            }
        }
    }

    @ViewBuilder private var background: some View {
        if let path = model.engine.assignment(for: display.id)?.path {
            ThumbnailImage(path: path)
        } else {
            Rectangle().fill(Color.black.opacity(0.75))
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Text(display.name).font(.caption.weight(.semibold)).lineLimit(1)
            Text(display.resolutionLabel).font(.caption2)
            if model.coveredDisplays.contains(display.id) {
                Label(tr("en espera", "idle"), systemImage: "pause.fill").font(.caption2)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.white)
    }
}
