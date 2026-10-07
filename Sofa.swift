// El sofá: cuando hay varios bichos sin nada que hacer, se sientan juntos en vez de quedarse
// sueltos por la pantalla «como un frutero lleno de naranjas».
// Son dos paneles: el respaldo va detrás de los bichos y el cojín delantero y los brazos, delante,
// para que parezca que están sentados dentro.

import AppKit

/// Medidas del sofá en unidades del dibujo del bicho (1 unidad = 1 punto a escala 1).
/// La «y» es la del viewBox de face.html (crece hacia abajo; el suelo está en 200).
enum SofaGeometry {
    static let seat: CGFloat = 146          // ancho de cada plaza
    static let arm: CGFloat = 34            // ancho de cada brazo
    static let backTop: CGFloat = 84        // arriba del respaldo
    static let seatTop: CGFloat = 158       // arriba del cojín delantero
    static let armTop: CGFloat = 126
    static let floor: CGFloat = 198         // abajo del sofá (sin patas)
    static let legs: CGFloat = 10

    static func width(seats n: Int) -> CGFloat { CGFloat(n) * seat + 2 * arm }
}

final class SofaView: NSView {
    enum Part { case back, front }
    let part: Part
    var seats = 2
    var scale: CGFloat = 1
    let ink = NSColor(srgbRed: 0.17, green: 0.12, blue: 0.10, alpha: 1)
    let fabric = NSColor(srgbRed: 0.24, green: 0.55, blue: 0.53, alpha: 1)
    let fabricLight = NSColor(srgbRed: 0.35, green: 0.68, blue: 0.64, alpha: 1)
    let fabricDark = NSColor(srgbRed: 0.18, green: 0.43, blue: 0.42, alpha: 1)
    let wood = NSColor(srgbRed: 0.55, green: 0.37, blue: 0.24, alpha: 1)

    init(part: Part) {
        self.part = part
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("no se usa") }

    /// La «y» del dibujo que cae en el borde de arriba de esta vista.
    var topUnits: CGFloat { part == .back ? SofaGeometry.backTop - 4 : SofaGeometry.armTop - 4 }

    func box(_ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ yBottom: CGFloat) -> NSRect {
        let h = (yBottom - yTop) * scale
        let y = bounds.height - (yTop - topUnits) * scale - h
        return NSRect(x: x * scale, y: y, width: w * scale, height: h)
    }

    func shape(_ r: NSRect, radius: CGFloat, fill: NSColor, line: CGFloat = 2.5) {
        let p = NSBezierPath(roundedRect: r, xRadius: radius * scale, yRadius: radius * scale)
        fill.setFill()
        p.fill()
        ink.setStroke()
        p.lineWidth = line * scale
        p.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        let G = SofaGeometry.self
        let total = G.width(seats: seats)
        let inner = CGFloat(seats) * G.seat
        switch part {
        case .back:
            // respaldo y un cojín por plaza
            shape(box(6, G.backTop, total - 12, G.seatTop + 14), radius: 26, fill: fabric)
            for i in 0..<seats {
                let x = G.arm + CGFloat(i) * G.seat
                shape(box(x + 6, G.backTop + 10, G.seat - 12, G.seatTop + 4), radius: 20, fill: fabricLight, line: 2)
            }
        case .front:
            // patas, cojín delantero con sus costuras y los brazos
            for x in [G.arm + 4, total - G.arm - 16] {
                shape(box(x, G.floor - 2, 12, G.floor + G.legs), radius: 3, fill: wood, line: 2)
            }
            shape(box(G.arm - 6, G.seatTop, inner + 12, G.floor), radius: 14, fill: fabricLight)
            ink.withAlphaComponent(0.45).setStroke()
            for i in 1..<max(1, seats) {
                let x = (G.arm + CGFloat(i) * G.seat) * scale
                let seam = NSBezierPath()
                let r = box(0, G.seatTop + 8, 1, G.floor - 6)
                seam.move(to: NSPoint(x: x, y: r.minY))
                seam.line(to: NSPoint(x: x, y: r.maxY))
                seam.lineWidth = 2 * scale
                seam.lineCapStyle = .round
                seam.stroke()
            }
            // sombra suave del cojín sobre la tela de abajo
            fabricDark.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: box(G.arm, G.floor - 10, inner, G.floor - 2), xRadius: 4, yRadius: 4).fill()
            for x in [CGFloat(0), total - G.arm] {
                shape(box(x, G.armTop, G.arm, G.floor), radius: 16, fill: fabric)
            }
        }
    }
}

/// Los dos paneles del sofá y dónde va cada plaza.
final class Sofa {
    let back = Creature.makePanel(.zero)
    let front = Creature.makePanel(.zero)
    let backView = SofaView(part: .back)
    let frontView = SofaView(part: .front)
    private(set) var seats = 0
    private(set) var visible = false
    /// Esquina de abajo a la izquierda del sofá (en pantalla), donde está el «suelo» del dibujo.
    private(set) var origin = NSPoint.zero
    var scale: CGFloat = 1

    init() {
        for (p, v) in [(back, backView), (front, frontView)] {
            p.ignoresMouseEvents = true
            p.contentView = v
            p.alphaValue = 0
        }
    }

    var width: CGFloat { SofaGeometry.width(seats: seats) * scale }

    /// Coloca el sofá con su suelo en `floor` (y de pantalla) y centrado en `centerX`, dentro de la pantalla.
    func layout(seats n: Int, centerX: CGFloat, floor: CGFloat, screen: NSRect, scale s: CGFloat) {
        seats = n
        scale = s
        let G = SofaGeometry.self
        var x = centerX - width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - width - 4)
        let fl = max(floor, screen.minY + G.legs * s)
        origin = NSPoint(x: x, y: fl)
        // cada panel cubre su franja del dibujo (más un poco de margen para las patas)
        let backTopU = G.backTop - 4, frontTopU = G.armTop - 4
        let bottomU = G.floor + G.legs + 2
        back.setFrame(NSRect(x: x, y: fl - (bottomU - 200) * s, width: width, height: (bottomU - backTopU) * s), display: false)
        front.setFrame(NSRect(x: x, y: fl - (bottomU - 200) * s, width: width, height: (bottomU - frontTopU) * s), display: false)
        for v in [backView, frontView] {
            v.seats = n
            v.scale = s
            v.needsDisplay = true
        }
    }

    /// Dónde va el panel de un bicho sentado en la plaza `i` (contando desde la izquierda).
    /// `labelHeight`: la etiqueta de debajo del bicho; el dibujo empieza encima.
    func seatOrigin(_ i: Int, panelWidth: CGFloat) -> NSPoint {
        let G = SofaGeometry.self
        let center = origin.x + (G.arm + (CGFloat(i) + 0.5) * G.seat) * scale
        // el centro del bicho está en x = 100 del viewBox, que es 120 puntos desde el borde del panel
        return NSPoint(x: center - (100 - VB_X) * scale, y: origin.y - labelHeight)
    }

    /// Enseña el sofá: el respaldo justo debajo de los bichos y el cojín justo encima.
    func show(below creatures: [Creature]) {
        let lowest = creatures.map { $0.panel.windowNumber }
        if let first = lowest.first { back.order(.below, relativeTo: first) } else { back.orderFrontRegardless() }
        for c in creatures { c.panel.order(.above, relativeTo: back.windowNumber) }
        front.orderFrontRegardless()
        for c in creatures where !c.bubbleText.isEmpty { c.bubblePanel.orderFrontRegardless() }
        guard !visible else { return }
        visible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            back.animator().alphaValue = 1
            front.animator().alphaValue = 1
        }
    }

    func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            back.animator().alphaValue = 0
            front.animator().alphaValue = 0
        }, completionHandler: { [back, front] in
            back.orderOut(nil)
            front.orderOut(nil)
        })
    }
}
