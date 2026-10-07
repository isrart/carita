// Un bicho: su panel flotante con la cara, su bocadillo, su viaje hasta ti y la sesión de Claude Code
// que representa. La app tiene uno por sesión abierta (y siempre al menos uno).

import AppKit
import WebKit

/// Lo que se sabe de una sesión de Claude Code (de ~/.carita/sesiones/<id>.info).
struct SessionInfo: Equatable {
    var cwd = ""
    var proyecto = ""
    var disfraz = ""
    var tty = ""
    var term = ""

    init() {}
    init?(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        cwd = obj["cwd"] as? String ?? ""
        proyecto = obj["proyecto"] as? String ?? ""
        disfraz = obj["disfraz"] as? String ?? ""
        tty = obj["tty"] as? String ?? ""
        term = obj["term"] as? String ?? ""
    }
}

/// Altura de la etiqueta con el nombre del proyecto, debajo de los pies (solo si hay varios bichos).
let labelHeight: CGFloat = 20

final class Creature: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var app: AppDelegate?
    var panel: Panel!
    var web: WKWebView!
    var drag: DragView!
    var label: NSTextField!
    var bubblePanel: Panel!
    var bubbleView: BubbleView!
    var bubbleText = ""
    var bubbleAnchor = NSRect.zero
    var noticeTimer: Timer?
    var noticeText = ""
    var pageReady = false
    var lastLook = CGPoint(x: 9, y: 9)
    var currentState = "idle"

    // la sesión que representa (nil: el bicho de siempre, sin sesión)
    var sessionID: String?
    var info = SessionInfo()
    var lastEvent = Date()
    var lastStateMTime: Date?
    var lastSayMTime: Date?
    var lastInfoMTime: Date?
    var leaving = false

    // el sofá
    var seated = false
    var goingToSofa = false
    var preSofaOrigin: NSPoint?     // dónde estaba antes de sentarse (allí vuelve al levantarse)
    var sofaHome: NSPoint?          // al levantarse para ir a buscarte, adónde vuelve luego
    var sofaOptOut = false          // lo has sacado tú del sofá: no vuelve hasta que su sesión haga algo
    var dragging = false
    private var onArrive: (() -> Void)?

    // viaje hasta ti cuando te necesita
    var homeOrigin: NSPoint?
    var travelTimer: Timer?
    var travelStart = NSPoint.zero
    var travelTarget = NSPoint.zero
    var travelBegan = Date()
    var travelDuration: TimeInterval = 1

    var name: String { info.proyecto.isEmpty ? "carita" : info.proyecto }

    init(app: AppDelegate, origin: NSPoint?) {
        self.app = app
        super.init()
        let size = panelSize
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let start = origin ?? NSPoint(x: screen.maxX - size.width - 20, y: screen.minY + 10)
        panel = Creature.makePanel(NSRect(origin: start, size: size))

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "carita")
        web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = self
        container.addSubview(web)

        label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = roundedFont(11)
        label.textColor = NSColor(srgbRed: 0.17, green: 0.12, blue: 0.10, alpha: 1)
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        label.layer?.cornerRadius = 8
        label.isHidden = true
        container.addSubview(label)

        drag = DragView(frame: container.bounds)
        drag.autoresizingMask = [.width, .height]
        drag.onClick = { [weak self] in self?.clicked() }
        drag.onDragStart = { [weak self] in self?.dragStarted() }
        drag.onDragEnd = { [weak self] in self?.dragEnded() }
        drag.onMouseMoved = { [weak self] in self?.mouseMoved() }
        container.addSubview(drag)
        panel.contentView = container
        layoutContent()

        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel = Creature.makePanel(NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel.ignoresMouseEvents = true
        bubblePanel.contentView = bubbleView
        bubblePanel.alphaValue = 0

        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didResizeNotification, object: panel)

        if let url = Bundle.main.url(forResource: "face", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    static func makePanel(_ rect: NSRect) -> Panel {
        let p = Panel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }

    var scale: CGFloat { app?.scale ?? 1 }
    /// El dibujo arriba (240×224 a escala, como el viewBox) y la etiqueta debajo.
    var panelSize: NSSize { NSSize(width: baseSize.width * scale, height: baseSize.height * scale + labelHeight) }

    func layoutContent() {
        let w = baseSize.width * scale, h = baseSize.height * scale
        web.frame = NSRect(x: 0, y: labelHeight, width: w, height: h)
        let text = label.stringValue as NSString
        let tw = min(w - 20, ceil(text.size(withAttributes: [.font: label.font!]).width) + 16)
        label.frame = NSRect(x: (w - tw) / 2, y: 2, width: tw, height: labelHeight - 4)
    }

    /// Enseña el nombre del proyecto debajo (cuando hay más de un bicho).
    func showLabel(_ on: Bool) {
        label.stringValue = name
        label.isHidden = !on
        layoutContent()
    }

    // MARK: web

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        guard let app = app else { return }
        if app.away { js("carita.hidden(true)") }
        app.sendFaceConfig(to: self)
        applyCostume()
        if let s = pendingState { pendingState = nil; set(s) }
        app.creatureReady(self)
        mouseMoved()
    }
    var pendingState: String?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let text = body["text"] as? String ?? ""
        switch type {
        case "bubble":
            showBubble(text)
        case "log":
            debugLog("\(name): cara: " + text)
        case "event":
            if ["stretch", "mask"].contains(text) { History.append(text) }   // descansos, para las estadísticas
        case "sound":
            NSSound(named: NSSound.Name(text))?.play()   // "Pop": el tapón del cava
        case "say":
            app?.shortSay(text, by: self)
        default:
            break
        }
    }

    func js(_ code: String) {
        guard pageReady else { return }
        debugLog("\(name): \(code)")
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    /// Un estado que llega de su sesión (o de la app).
    func set(_ s: String) {
        guard pageReady else { pendingState = s; return }
        currentState = s
        lastEvent = Date()
        sofaOptOut = false
        js("carita.set('\(s)')")
        // su sesión hace algo: se levanta del sofá (si te necesita, va directo a buscarte)
        if seated || goingToSofa { leaveSofa(returning: s != "asking") }
        if s == "asking" {
            goFindUser()
        } else if homeOrigin != nil {
            goHome()
        }
    }

    func applyCostume() {
        guard let app = app else { return }
        var c = app.costumeChoice
        if c == "auto" { c = info.disfraz.isEmpty ? app.readWord(costumePath) : info.disfraz }
        js("carita.costume('\(c.isEmpty ? "none" : c)')")
    }

    func clicked() {
        guard let app = app else { return }
        if app.speech.isSpeaking && app.speaker === self {
            app.speech.stopSpeaking(at: .word)
            js("carita.say('Vale, vale, me callo')")
        } else if currentState == "asking", app.focusTerminal(for: self) {
            js("carita.say('¡Vamos para allá!')")
        } else {
            js("carita.poke()")
        }
    }

    // MARK: bocadillo

    /// Coordenadas de pantalla de un punto del dibujo.
    func screenPoint(_ vx: CGFloat, _ vy: CGFloat) -> NSPoint {
        let f = panel.frame
        let s = f.width / VB_W
        return NSPoint(x: f.minX + (vx - VB_X) * s, y: f.maxY - (vy - VB_Y) * s)
    }

    /// Un aviso de la propia app (p. ej., «me callo»): sale aunque esté silenciada.
    func notice(_ text: String) {
        guard app?.away == false else { return }
        showBubble(text, force: true)
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(timeInterval: 3.5, target: self, selector: #selector(hideNotice),
                                           userInfo: nil, repeats: false)
    }
    @objc func hideNotice() { if bubbleText == noticeText { showBubble("") } }

    func showBubble(_ text: String, force: Bool = false) {
        if text.isEmpty {
            bubbleText = ""
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.bubblePanel.animator().alphaValue = 0
            }
            return
        }
        guard force || app?.quiet == false else { return }
        if force { noticeText = text }
        debugLog("\(name): bocadillo: " + text)
        bubbleText = text
        bubbleView.label.font = roundedFont(13 * scale)
        bubbleView.label.stringValue = text
        layoutBubble()
        bubblePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.bubblePanel.animator().alphaValue = 1
        }
    }

    /// Encima de la cabeza; si no cabe (barra de menús), debajo de los pies.
    func layoutBubble() {
        let s = panel.frame.width / VB_W
        let maxTextW = 200 * s
        let fit = bubbleView.label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxTextW, height: 10000))
            ?? NSSize(width: maxTextW, height: 20)
        let w = min(maxTextW, ceil(fit.width)) + 28
        let h = ceil(fit.height) + 18 + bubbleView.tail + 3

        let head = screenPoint(100, 30)     // punta de la hoja
        let feet = screenPoint(100, 190)
        let screen = NSScreen.screens.first { $0.frame.contains(head) }?.visibleFrame
            ?? panel.screen?.visibleFrame ?? panel.frame
        var below = false
        var y = head.y + 2
        if y + h > screen.maxY { below = true; y = feet.y - h - 2 - (label.isHidden ? 0 : labelHeight) }
        let x = min(max(head.x - w / 2, screen.minX + 4), screen.maxX - w - 4)

        bubbleView.tailUp = below
        bubbleView.tailX = head.x - x
        bubblePanel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        bubbleView.needsLayout = true
        bubbleView.needsDisplay = true
        bubbleAnchor = panel.frame
    }

    @objc func panelMoved() {
        if !bubbleText.isEmpty && panel.frame != bubbleAnchor { layoutBubble() }
        mouseMoved()
    }

    // MARK: ratón

    /// Los ojos siguen al ratón y solo el bicho recibe clics.
    func mouseMoved() {
        guard pageReady, app?.away == false else { return }
        let mouse = NSEvent.mouseLocation
        let eyes = screenPoint(100, 112)
        let dx = max(-1, min(1, (mouse.x - eyes.x) / 300))
        let dy = max(-1, min(1, (eyes.y - mouse.y) / 300))
        if abs(dx - lastLook.x) > 0.01 || abs(dy - lastLook.y) > 0.01 {
            lastLook = CGPoint(x: dx, y: dy)
            js(String(format: "carita.look(%.3f,%.3f)", dx, dy))
        }

        // el resto de la ventana deja pasar el clic a lo que haya detrás. No se toca mientras arrastras.
        if NSEvent.pressedMouseButtons == 0 {
            let over = isOverCreature(mouse)
            if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over; debugLog("\(name): clicable \(over)") }
        }
    }

    /// ¿Está el ratón encima del cuerpo (hoja, brazos y pies incluidos)?
    func isOverCreature(_ p: NSPoint) -> Bool {
        let f = panel.frame
        let s = f.width / VB_W
        let vx = (p.x - f.minX) / s + VB_X
        let vy = (f.maxY - p.y) / s + VB_Y
        let ex = (vx - 100) / 80
        let ey = (vy - 112) / 82
        return ex * ex + ey * ey <= 1
    }

    // MARK: verse, esconderse, irse

    func applyVisibility(_ away: Bool) {
        js("carita.hidden(\(away))")
        if away {
            stopTravel()
            homeOrigin = nil
            showBubble("")
            panel.orderOut(nil)
            bubblePanel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            mouseMoved()
        }
    }

    func applyScale() {
        var f = panel.frame
        let newSize = panelSize
        f.origin.x += (f.width - newSize.width) / 2   // mantiene los pies en el mismo sitio
        f.size = newSize
        panel.setFrame(f, display: true)
        layoutContent()
        if !bubbleText.isEmpty { showBubble(bubbleText) }
    }

    /// Se va (su sesión ha terminado): se desvanece y cierra sus ventanas.
    func dismiss() {
        leaving = true
        stopTravel()
        noticeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            self.panel.animator().alphaValue = 0
            self.bubblePanel.animator().alphaValue = 0
        }, completionHandler: { [panel, bubblePanel, web] in
            panel?.orderOut(nil)
            bubblePanel?.orderOut(nil)
            web?.configuration.userContentController.removeScriptMessageHandler(forName: "carita")
        })
    }

    // MARK: ir a buscarte

    func goFindUser() {
        let home = sofaHome
        sofaHome = nil
        let mouse = NSEvent.mouseLocation
        let f = panel.frame
        guard let app = app, app.seeksYou, !app.quiet, homeOrigin == nil, !app.userIsLookingAtTerminal(),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              hypot(mouse.x - f.midX, mouse.y - f.midY) >= 220 else {   // (o ya estás cerca)
            if let h = home { travel(to: h) }   // venía del sofá: a su sitio
            return
        }
        let v = screen.visibleFrame
        var target = NSPoint(x: mouse.x + 30, y: mouse.y - f.height - 30)
        if target.y < v.minY { target.y = mouse.y + 30 }
        target.x = min(max(target.x, v.minX), v.maxX - f.width)
        target.y = min(max(target.y, v.minY), v.maxY - f.height)
        homeOrigin = home ?? f.origin
        travel(to: target)
    }

    func goHome() {
        guard let home = homeOrigin else { return }
        homeOrigin = nil
        travel(to: home)
    }

    func travel(to target: NSPoint, then arrive: (() -> Void)? = nil) {
        stopTravel()
        onArrive = arrive
        travelStart = panel.frame.origin
        travelTarget = target
        travelBegan = Date()
        let dist = hypot(target.x - travelStart.x, target.y - travelStart.y)
        travelDuration = min(1.6, max(0.5, Double(dist) / 1300))
        js("carita.travel(\(target.x < travelStart.x ? -1 : 1))")
        travelTimer = Timer.scheduledTimer(timeInterval: 1.0 / 60, target: self, selector: #selector(travelStep),
                                           userInfo: nil, repeats: true)
    }

    func stopTravel() {
        guard travelTimer != nil else { return }
        travelTimer?.invalidate()
        travelTimer = nil
        onArrive = nil
        js("carita.travel(0)")
    }

    @objc func travelStep() {
        let p = min(1, Date().timeIntervalSince(travelBegan) / travelDuration)
        let e = CGFloat(p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2)
        panel.setFrameOrigin(NSPoint(x: travelStart.x + (travelTarget.x - travelStart.x) * e,
                                     y: travelStart.y + (travelTarget.y - travelStart.y) * e))
        if p >= 1 {
            let arrive = onArrive
            stopTravel()
            arrive?()
        }
    }

    // MARK: el sofá

    /// Va andando a su plaza y se sienta.
    func goSit(at seat: NSPoint) {
        if !seated && !goingToSofa { preSofaOrigin = panel.frame.origin }
        if seated && panel.frame.origin == seat { return }
        goingToSofa = true
        if seated {
            panel.setFrameOrigin(seat)   // el sofá ha cambiado de tamaño: se recoloca sin más
            goingToSofa = false
            return
        }
        travel(to: seat) { [weak self] in
            guard let self = self else { return }
            self.goingToSofa = false
            self.seated = true
            self.js("carita.sit(true)")
            self.app?.arrangeSofa()
        }
    }

    /// Se levanta: vuelve a donde estaba (o se queda listo para ir a buscarte).
    func leaveSofa(returning: Bool) {
        let home = preSofaOrigin
        seated = false
        goingToSofa = false
        preSofaOrigin = nil
        stopTravel()
        js("carita.sit(false)")
        if returning, let h = home { travel(to: h) } else { sofaHome = home }
        app?.arrangeSofa()
    }

    func dragStarted() {
        dragging = true
        stopTravel()
        if seated || goingToSofa {
            // lo sacas tú del sofá: se queda donde lo sueltes
            seated = false
            goingToSofa = false
            preSofaOrigin = nil
            sofaOptOut = true
            js("carita.sit(false)")
            app?.arrangeSofa()
        }
    }

    func dragEnded() {
        dragging = false
        homeOrigin = nil   // si lo sueltas en otro sitio, se queda ahí
    }
}
