// Carita — una cara flotante para Claude Code en el Mac.
// Lee ~/.carita/state, say y costume (los escriben los hooks de Claude Code) y se lo pasa a face.html.

import AppKit
import WebKit
import AVFoundation
import ServiceManagement

let stateDir = (NSHomeDirectory() as NSString).appendingPathComponent(".carita")
let statePath = (stateDir as NSString).appendingPathComponent("state")
let sayPath = (stateDir as NSString).appendingPathComponent("say")
let costumePath = (stateDir as NSString).appendingPathComponent("costume")
let termPath = (stateDir as NSString).appendingPathComponent("term")
let workStates: Set<String> = ["hello", "thinking", "reading", "writing", "running", "browsing", "delegating", "deploying"]

// Geometría del dibujo: face.html usa viewBox "-20 -24 240 224" en la app.
let VB_X: CGFloat = -20
let VB_Y: CGFloat = -24
let VB_W: CGFloat = 240

/// Apps donde sueles tener Claude Code (para saber si estás mirando la terminal).
let terminalApps: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "net.kovidgoyal.kitty", "org.alacritty",
    "com.github.wez.wezterm", "dev.zed.Zed",
]

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

/// Panel transparente que nunca roba el foco y puede ir pegado al borde de arriba.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Capa invisible encima de la web: arrastrar mueve la ventana, clic hace cosquillas.
final class DragView: NSView {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x
        let dy = p.y - startMouse.y
        if !moved && hypot(dx, dy) < 3 { return }
        if !moved { onDragStart?() }
        moved = true
        win.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if moved { onDragEnd?() } else { onClick?() }
    }
}

/// El bocadillo: globo blanco con borde y piquito hacia la cabeza (o hacia arriba si va debajo).
final class BubbleView: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    var tailUp = false
    var tailX: CGFloat = 0
    let tail: CGFloat = 9
    let ink = NSColor(srgbRed: 0.17, green: 0.12, blue: 0.10, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.alignment = .center
        label.textColor = ink
        label.maximumNumberOfLines = 0
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("no se usa") }

    var bodyRect: NSRect {
        var r = bounds.insetBy(dx: 2, dy: 2)
        r.size.height -= 3 + tail        // sombra + piquito
        r.origin.y += 3
        if !tailUp { r.origin.y += tail }
        return r
    }

    override func layout() {
        super.layout()
        label.frame = bodyRect.insetBy(dx: 12, dy: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bodyRect
        let tx = min(max(tailX, body.minX + 18), body.maxX - 18)
        let baseY = tailUp ? body.maxY : body.minY
        let tipY = tailUp ? body.maxY + tail : body.minY - tail

        // sombrita
        ink.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: body.offsetBy(dx: 0, dy: -3), xRadius: 15, yRadius: 15).fill()

        let rect = NSBezierPath(roundedRect: body, xRadius: 15, yRadius: 15)
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: tx - 8, y: baseY))
        tri.line(to: NSPoint(x: tx, y: tipY))
        tri.line(to: NSPoint(x: tx + 8, y: baseY))
        tri.close()

        NSColor.white.setFill()
        rect.fill()
        tri.fill()
        ink.setStroke()
        rect.lineWidth = 2.5
        rect.stroke()

        // tapa el borde bajo el piquito y dibuja solo sus dos lados
        let inward: CGFloat = tailUp ? -2 : 2
        let cover = NSBezierPath()
        cover.move(to: NSPoint(x: tx - 6.5, y: baseY + inward))
        cover.line(to: NSPoint(x: tx, y: tipY))
        cover.line(to: NSPoint(x: tx + 6.5, y: baseY + inward))
        cover.close()
        NSColor.white.setFill()
        cover.fill()
        let edges = NSBezierPath()
        edges.move(to: NSPoint(x: tx - 8, y: baseY))
        edges.line(to: NSPoint(x: tx, y: tipY))
        edges.line(to: NSPoint(x: tx + 8, y: baseY))
        edges.lineWidth = 2.5
        edges.lineJoinStyle = .round
        edges.stroke()
    }
}

/// Avisa cuando la voz empieza y acaba, para mover la boca.
final class SpeechWatcher: NSObject, AVSpeechSynthesizerDelegate {
    var onChange: ((Bool) -> Void)?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onChange?(true) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onChange?(synthesizer.isSpeaking) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onChange?(false) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var panel: Panel!
    var web: WKWebView!
    var drag: DragView!
    var bubblePanel: Panel!
    var bubbleView: BubbleView!
    var bubbleText = ""
    var bubbleAnchor = NSRect.zero
    var timer: Timer?
    var lastMTime: Date?
    var lastSayMTime: Date?
    var lastCostumeMTime: Date?
    var lastReplyAt = Date.distantPast
    var currentState = "idle"
    let watcher = SpeechWatcher()
    var pageReady = false
    var lastLook = CGPoint(x: 9, y: 9)
    let speech = AVSpeechSynthesizer()
    let defaults = UserDefaults.standard
    let baseSize = NSSize(width: 240, height: 224)

    // viaje hasta ti cuando te necesita
    var homeOrigin: NSPoint?
    var travelTimer: Timer?
    var travelStart = NSPoint.zero
    var travelTarget = NSPoint.zero
    var travelBegan = Date()
    var travelDuration: TimeInterval = 1

    let testStates: [(String, String)] = [
        ("Hola", "hello"), ("Pensando", "thinking"), ("Leyendo", "reading"), ("Escribiendo", "writing"),
        ("Ejecutando", "running"), ("Desplegando", "deploying"), ("¡En producción!", "shipped"),
        ("Investigando", "browsing"), ("Delegando", "delegating"), ("Te necesita", "asking"),
        ("¡Hecho!", "done"), ("Descanso", "stretch"), ("Aburrido", "sleepy"), ("Dormido", "sleeping"),
    ]
    let costumes: [(String, String)] = [
        ("Automático (según el proyecto)", "auto"), ("Sin disfraz", "none"),
        ("Bajovelo (boina y copa)", "vino"), ("Blog (pluma y cuaderno)", "vinoblog"),
        ("Recursos (guía de vino)", "vinorecursos"), ("Trivia (cartel ?)", "vinotrivia"),
        ("Reels (móvil grabando)", "vinoreels"),
    ]

    var scale: CGFloat {
        let v = defaults.double(forKey: "scale")
        return v > 0 ? CGFloat(v) : 1
    }
    var talks: Bool { defaults.bool(forKey: "talks") }
    /// Leer en voz alta el resumen de cada respuesta (activado por defecto).
    var readAloud: Bool { defaults.object(forKey: "readAloud") == nil ? true : defaults.bool(forKey: "readAloud") }
    /// Ir a buscarte cuando te necesita y estás en otra app (activado por defecto).
    var seeksYou: Bool { defaults.object(forKey: "seeksYou") == nil ? true : defaults.bool(forKey: "seeksYou") }
    var costumeChoice: String { defaults.string(forKey: "costume") ?? "auto" }

    /// La mejor voz en español de España que tengas instalada.
    lazy var voice: AVSpeechSynthesisVoice? = {
        let novelty = ["eloquence", "speech.synthesis.voice"]
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { v in
            v.language == "es-ES" && !novelty.contains { v.identifier.lowercased().contains($0) }
        }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            let preferred = v.name.contains("Mónica") || v.name.contains("Monica") ? 1 : 0
            return v.quality.rawValue * 10 + preferred
        }
        return candidates.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "es-ES")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: screen.maxX - size.width - 20, y: screen.minY + 10,
                          width: size.width, height: size.height)

        panel = makePanel(rect)

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizesSubviews = true

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "carita")
        web = WKWebView(frame: container.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = self
        container.addSubview(web)

        drag = DragView(frame: container.bounds)
        drag.autoresizingMask = [.width, .height]
        drag.onClick = { [weak self] in self?.clicked() }
        drag.onDragStart = { [weak self] in self?.stopTravel() }
        drag.onDragEnd = { [weak self] in self?.homeOrigin = nil }   // si lo sueltas en otro sitio, se queda ahí
        container.addSubview(drag)
        panel.contentView = container

        speech.delegate = watcher
        watcher.onChange = { [weak self] on in self?.js("carita.talking(\(on))") }

        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel = makePanel(NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel.ignoresMouseEvents = true
        bubblePanel.contentView = bubbleView
        bubblePanel.alphaValue = 0

        refreshMenu()

        // recuerda dónde lo dejaste, siempre que siga dentro de alguna pantalla
        if panel.setFrameUsingName("CaritaWindow2") {
            var f = panel.frame
            f.size = size
            let visible = NSScreen.screens.contains { $0.frame.intersects(f) }
            panel.setFrame(visible ? f : rect, display: false)
        }
        panel.setFrameAutosaveName("CaritaWindow2")

        if let url = Bundle.main.url(forResource: "face", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        panel.orderFrontRegardless()

        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(tick),
                                     userInfo: nil, repeats: true)
    }

    func makePanel(_ rect: NSRect) -> Panel {
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

    // MARK: web

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        // no repetir el último estado de la sesión anterior al arrancar
        lastMTime = modDate(statePath)
        lastSayMTime = modDate(sayPath)
        lastCostumeMTime = nil   // el disfraz sí se aplica al arrancar
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let text = body["text"] as? String ?? ""
        switch type {
        case "bubble":
            showBubble(text)
        case "sound":
            NSSound(named: NSSound.Name(text))?.play()   // "Pop": el tapón del cava
        case "say":
            // avisos cortos ("¡Hecho!", "te necesito"); no pisan la lectura de una respuesta
            if talks, Date().timeIntervalSince(lastReplyAt) > 4, !text.isEmpty { speak(text, interrupt: true) }
        default:
            break
        }
    }

    func js(_ code: String) {
        guard pageReady else { return }
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    func speak(_ text: String, interrupt: Bool) {
        let utterance = AVSpeechUtterance(string: text.replacingOccurrences(of: "*", with: ""))
        utterance.voice = voice
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.15
        if interrupt && speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        speech.speak(utterance)
    }

    func clicked() {
        if speech.isSpeaking {
            speech.stopSpeaking(at: .word)
            js("carita.say('Vale, vale, me callo')")
        } else if currentState == "asking", focusTerminal() {
            js("carita.say('¡Vamos para allá!')")
        } else {
            js("carita.poke()")
        }
    }

    /// Texto seguro para meterlo en una llamada de JavaScript.
    func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "''" }
        return String(json.dropFirst().dropLast())
    }

    // MARK: bocadillo

    /// Coordenadas de pantalla de un punto del dibujo.
    func screenPoint(_ vx: CGFloat, _ vy: CGFloat) -> NSPoint {
        let f = panel.frame
        let s = f.width / VB_W
        return NSPoint(x: f.minX + (vx - VB_X) * s, y: f.maxY - (vy - VB_Y) * s)
    }

    func showBubble(_ text: String) {
        if text.isEmpty {
            bubbleText = ""
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.bubblePanel.animator().alphaValue = 0
            }
            return
        }
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
        if y + h > screen.maxY { below = true; y = feet.y - h - 2 }
        let x = min(max(head.x - w / 2, screen.minX + 4), screen.maxX - w - 4)

        bubbleView.tailUp = below
        bubbleView.tailX = head.x - x
        bubblePanel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        bubbleView.needsLayout = true
        bubbleView.needsDisplay = true
        bubbleAnchor = panel.frame
    }

    // MARK: ir a buscarte

    func termBundle() -> String? {
        let id = (try? String(contentsOfFile: termPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (id?.isEmpty ?? true) ? nil : id
    }

    func userIsLookingAtTerminal() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        if let t = termBundle() { return front == t }
        return terminalApps.contains(front)
    }

    @discardableResult
    func focusTerminal() -> Bool {
        guard let id = termBundle(),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
        return true
    }

    func stateChanged(to s: String) {
        currentState = s
        if s == "asking" {
            goFindUser()
        } else if homeOrigin != nil {
            goHome()
        }
    }

    func goFindUser() {
        guard seeksYou, homeOrigin == nil, !userIsLookingAtTerminal() else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        let f = panel.frame
        if hypot(mouse.x - f.midX, mouse.y - f.midY) < 220 { return }   // ya estás cerca
        let v = screen.visibleFrame
        var target = NSPoint(x: mouse.x + 30, y: mouse.y - f.height - 30)
        if target.y < v.minY { target.y = mouse.y + 30 }
        target.x = min(max(target.x, v.minX), v.maxX - f.width)
        target.y = min(max(target.y, v.minY), v.maxY - f.height)
        homeOrigin = f.origin
        travel(to: target)
    }

    func goHome() {
        guard let home = homeOrigin else { return }
        homeOrigin = nil
        travel(to: home)
    }

    func travel(to target: NSPoint) {
        stopTravel()
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
        js("carita.travel(0)")
    }

    @objc func travelStep() {
        let p = min(1, Date().timeIntervalSince(travelBegan) / travelDuration)
        let e = CGFloat(p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2)
        panel.setFrameOrigin(NSPoint(x: travelStart.x + (travelTarget.x - travelStart.x) * e,
                                     y: travelStart.y + (travelTarget.y - travelStart.y) * e))
        if p >= 1 { stopTravel() }
    }

    // MARK: polling

    func modDate(_ path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    func readWord(_ path: String) -> String {
        let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return String(raw.filter { $0.isASCII && $0.isLetter }.prefix(20))
    }

    func applyCostume() {
        let c = costumeChoice == "auto" ? readWord(costumePath) : costumeChoice
        js("carita.costume('\(c.isEmpty ? "none" : c)')")
    }

    @objc func tick() {
        guard pageReady else { return }

        if let m = modDate(statePath), m != lastMTime {
            lastMTime = m
            let s = readWord(statePath)
            if !s.isEmpty {
                // si le preguntas otra cosa mientras habla, se calla
                if workStates.contains(s) && speech.isSpeaking { speech.stopSpeaking(at: .word) }
                js("carita.set('\(s)')")
                stateChanged(to: s)
            }
        }

        let costumeM = modDate(costumePath) ?? .distantPast
        if costumeM != lastCostumeMTime {
            lastCostumeMTime = costumeM
            applyCostume()
        }

        // resumen de la última respuesta, para leerlo en voz alta
        if let m = modDate(sayPath), m != lastSayMTime {
            lastSayMTime = m
            if readAloud, Date().timeIntervalSince(m) < 20,
               let data = FileManager.default.contents(atPath: sayPath),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let text = obj["voice"] as? String, !text.isEmpty {
                let bubbleText = (obj["bubble"] as? String) ?? text
                lastReplyAt = Date()
                js("carita.reply(\(jsString(bubbleText)))")
                speak(text, interrupt: true)
            }
        }

        // el bocadillo sigue a la cabeza
        if !bubbleText.isEmpty && panel.frame != bubbleAnchor { layoutBubble() }

        // los ojos siguen al ratón
        let mouse = NSEvent.mouseLocation
        let eyes = screenPoint(100, 112)
        let dx = max(-1, min(1, (mouse.x - eyes.x) / 300))
        let dy = max(-1, min(1, (eyes.y - mouse.y) / 300))
        if abs(dx - lastLook.x) > 0.01 || abs(dy - lastLook.y) > 0.01 {
            lastLook = CGPoint(x: dx, y: dy)
            js(String(format: "carita.look(%.3f,%.3f)", dx, dy))
        }

        // solo el bicho recibe clics; el resto de la ventana deja pasar el clic
        // a lo que haya detrás. No se toca mientras arrastras.
        if NSEvent.pressedMouseButtons == 0 {
            let over = isOverCreature(mouse)
            if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
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

    // MARK: menu (clic derecho)

    func addToggle(_ menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        menu.addItem(item)
    }

    func addSubmenu(_ menu: NSMenu, _ title: String, _ items: [(String, Any, Bool)], _ action: Selector) {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (t, value, on) in items {
            let item = NSMenuItem(title: t, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = on ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    func refreshMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addSubmenu(menu, "Tamaño",
                   [("Pequeño", 0.75), ("Normal", 1.0), ("Grande", 1.4)].map { ($0.0, $0.1 as Any, abs(Double(scale) - $0.1) < 0.01) },
                   #selector(setSize(_:)))
        addSubmenu(menu, "Disfraz", costumes.map { ($0.0, $0.1 as Any, costumeChoice == $0.1) }, #selector(setCostume(_:)))
        menu.addItem(.separator())
        addToggle(menu, "Leer mis respuestas en voz alta", readAloud, #selector(toggleRead))
        addToggle(menu, "Avisos con voz (¡Hecho!, te necesito…)", talks, #selector(toggleTalk))
        addToggle(menu, "Ir a buscarme cuando me necesita", seeksYou, #selector(toggleSeek))
        addToggle(menu, "Abrir al iniciar sesión", SMAppService.mainApp.status == .enabled, #selector(toggleLogin))
        menu.addItem(.separator())
        addSubmenu(menu, "Probar expresión", testStates.map { ($0.0, $0.1 as Any, false) }, #selector(test(_:)))
        let quit = NSMenuItem(title: "Salir de Carita", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        drag.menu = menu
    }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        defaults.set(value, forKey: "scale")
        var f = panel.frame
        let newSize = NSSize(width: baseSize.width * CGFloat(value), height: baseSize.height * CGFloat(value))
        f.origin.x += (f.width - newSize.width) / 2   // mantiene los pies en el mismo sitio
        f.size = newSize
        panel.setFrame(f, display: true, animate: true)
        if !bubbleText.isEmpty { showBubble(bubbleText) }
        refreshMenu()
    }

    @objc func setCostume(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        defaults.set(value, forKey: "costume")
        applyCostume()
        refreshMenu()
    }

    @objc func toggleTalk() {
        defaults.set(!talks, forKey: "talks")
        if talks { speak("¡Vale! Te aviso con voz", interrupt: true) }
        refreshMenu()
    }

    @objc func toggleRead() {
        defaults.set(!readAloud, forKey: "readAloud")
        if readAloud {
            js("carita.reply('Te leo un resumen de cada respuesta')")
            speak("Vale. A partir de ahora te leo un resumen de cada respuesta.", interrupt: true)
        } else {
            speech.stopSpeaking(at: .immediate)
            js("carita.say('Vale, me callo')")
        }
        refreshMenu()
    }

    @objc func toggleSeek() {
        defaults.set(!seeksYou, forKey: "seeksYou")
        if !seeksYou { goHome() }
        refreshMenu()
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
        refreshMenu()
    }

    @objc func test(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String else { return }
        js("carita.set('\(state)')")
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
