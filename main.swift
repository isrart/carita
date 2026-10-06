// Carita — una cara flotante para Claude Code en el Mac.
// Lee ~/.carita/state, say y costume (los escriben los hooks de Claude Code) y se lo pasa a face.html.

import AppKit
import WebKit
import AVFoundation
import ServiceManagement
import CoreMediaIO
import Carbon.HIToolbox

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

/// Icono de la barra de menús: silueta del bicho con su hoja (plantilla, vale para claro y oscuro).
/// Con `alert`, una exclamación al lado: te necesita aunque esté oculta.
func statusIcon(alert: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: alert ? 22 : 18, height: 18), flipped: false) { _ in
        NSColor.black.setFill()
        NSColor.black.setStroke()
        NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1, width: 15, height: 12.5)).fill()
        // tallo y hoja
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 9, y: 13))
        stem.curve(to: NSPoint(x: 10.5, y: 16.2), controlPoint1: NSPoint(x: 8.6, y: 14.6), controlPoint2: NSPoint(x: 9.4, y: 15.6))
        stem.lineWidth = 1.4
        stem.lineCapStyle = .round
        stem.stroke()
        let leaf = NSBezierPath(ovalIn: NSRect(x: -2.6, y: -1.4, width: 5.2, height: 2.8))
        var t = AffineTransform(translationByX: 12.4, byY: 16.4)
        t.rotate(byDegrees: 25)
        leaf.transform(using: t)
        leaf.fill()
        // ojos huecos
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: 5.2, y: 5.6, width: 2.6, height: 3.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.2, y: 5.6, width: 2.6, height: 3.4)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        if alert {
            NSBezierPath(roundedRect: NSRect(x: 19, y: 7, width: 2.2, height: 9), xRadius: 1.1, yRadius: 1.1).fill()
            NSBezierPath(ovalIn: NSRect(x: 19, y: 2, width: 2.2, height: 2.2)).fill()
        }
        return true
    }
    img.isTemplate = true
    return img
}

/// Un atajo de teclado: código de tecla y modificadores de Carbon.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let toggleDefault = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let muteDefault = Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey | cmdKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(array: Any?) {
        guard let a = array as? [Int], a.count == 2 else { return nil }
        self.init(keyCode: UInt32(a[0]), modifiers: UInt32(a[1]))
    }
    var array: [Int] { [Int(keyCode), Int(modifiers)] }

    var eventModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static let specialKeys: [Int: String] = [
        kVK_Space: "Espacio", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// La tecla tal como sale en tu teclado (distribución actual).
    var keyName: String {
        if let s = Shortcut.specialKeys[Int(keyCode)] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &len, &chars)
        }
        guard status == noErr, len > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }

    /// ¿Lo usa ya macOS (Spotlight, capturas, cambiar de app…)? Los de otras apps no se pueden
    /// consultar: RegisterEventHotKey no da error aunque otra app tenga la misma combinación.
    var clashesWithSystem: Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let list = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        let relevant = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return list.contains { hk in
            guard (hk[kHISymbolicHotKeyEnabled as String] as? Bool) ?? false,
                  let code = hk[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = hk[kHISymbolicHotKeyModifiers as String] as? Int else { return false }
            return UInt32(code) == keyCode && UInt32(mods) & relevant == modifiers & relevant
        }
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }
}

/// Atajos globales con RegisterEventHotKey (Carbon): funcionan con cualquier app delante
/// y no piden permiso de accesibilidad.
final class HotKeys {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let userData = userData {
                Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue().fire(hk.id)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func fire(_ id: UInt32) { actions[id]?() }

    /// Devuelve false si la combinación ya la usa macOS (o no se pudo registrar).
    @discardableResult
    func register(_ id: UInt32, _ shortcut: Shortcut?, action: @escaping () -> Void) -> Bool {
        unregister(id)
        guard let shortcut = shortcut else { return true }
        if shortcut.clashesWithSystem { return false }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x43617269), id: id)   // 'Cari'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else { return false }
        refs[id] = r
        actions[id] = action
        return true
    }

    func unregister(_ id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        actions[id] = nil
    }
}

/// No molestar automático: detecta videollamadas y pantalla compartida.
/// - Cámara: CoreMediaIO (`DeviceIsRunningSomewhere`), con avisos al cambiar. Vale para cualquier app.
/// - Pantalla compartida: no hay API pública. Heurísticas: Zoom compartiendo (proceso CptHost),
///   alguien viendo tu Mac por Compartir pantalla (screensharingd) o la pantalla duplicada
///   (AirPlay o proyector). Meet/Teams en el navegador sin cámara no se pueden detectar.
/// - Modo concentración: INFocusStatusCenter siempre dice «no» en una app firmada ad hoc
///   (pide el permiso Communication Notifications), así que no se usa.
final class Interruptions: NSObject {
    var onChange: (() -> Void)?
    private(set) var camera = false
    private(set) var sharing: String?      // qué se ha detectado, o nil
    private var watched = Set<CMIOObjectID>()
    private var pollTimer: Timer?

    func start() {
        var addr = Interruptions.address(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.performSelector(onMainThread: #selector(Interruptions.devicesChanged), with: nil, waitUntilDone: false)
        }
        devicesChanged()
        pollTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(check), userInfo: nil, repeats: true)
        pollTimer?.tolerance = 1
    }

    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    func cameraIDs() -> [CMIOObjectID] {
        var addr = Interruptions.address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &size, &ids) == 0 else { return [] }
        return ids
    }

    /// Cámara nueva enchufada (o la primera vez): escuchar cuándo se enciende.
    @objc func devicesChanged() {
        for id in cameraIDs() where !watched.contains(id) {
            watched.insert(id)
            var addr = Interruptions.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main) { [weak self] _, _ in
                self?.performSelector(onMainThread: #selector(Interruptions.check), with: nil, waitUntilDone: false)
            }
        }
        check()
    }

    func cameraRunning() -> Bool {
        cameraIDs().contains { id in
            var addr = Interruptions.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            var on: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &size, &on) == 0 && on != 0
        }
    }

    func screenShared() -> String? {
        let names = runningProcessNames()
        if names.contains("CptHost") { return "Zoom compartiendo pantalla" }
        if names.contains("screensharingd") { return "Compartir pantalla del Mac" }
        if CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 { return "pantalla duplicada" }
        return nil
    }

    func runningProcessNames() -> Set<String> {
        var pids = [pid_t](repeating: 0, count: 4096)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var names = Set<String>()
        var buf = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(max(0, Int(n))) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 { names.insert(String(cString: buf)) }
        }
        return names
    }

    @objc func check() {
        let cam = cameraRunning()
        let share = screenShared()
        if cam != camera || share != sharing {
            camera = cam
            sharing = share
            onChange?()
        }
    }
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
    var onMouseMoved: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // con la app en segundo plano, el ratón encima del bicho solo llega por aquí
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseExited(with event: NSEvent) { onMouseMoved?() }

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
    var dirSource: DispatchSourceFileSystemObject?
    var fileSources: [String: (source: DispatchSourceFileSystemObject, inode: UInt64)] = [:]
    var fallbackTimer: Timer?
    var mouseMonitors: [Any] = []
    var lastMTime: Date?
    var lastSayMTime: Date?
    var lastCostumeMTime: Date?
    var lastReplyAt = Date.distantPast
    var currentState = "idle"
    let watcher = SpeechWatcher()
    var pageReady = false
    var lastLook = CGPoint(x: 9, y: 9)
    let speech = AVSpeechSynthesizer()
    var statusItem: NSStatusItem!
    var unmuteTimer: Timer?
    var noticeTimer: Timer?
    var noticeText = ""
    var pendingNotice: String?
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

    let store = ConfigStore()
    let settingsWindow = SettingsWindow()
    var cfg: Config { store.c }

    var scale: CGFloat { CGFloat(cfg.tamano) }
    var talks: Bool { cfg.avisosVoz }
    /// Leer en voz alta el resumen de cada respuesta.
    var readAloud: Bool { cfg.leerRespuestas }
    /// Ir a buscarte cuando te necesita y estás en otra app.
    var seeksYou: Bool { cfg.irABuscarte }
    var costumeChoice: String { cfg.disfraz }
    /// Escondida a mano (se recuerda entre reinicios).
    var hiddenByUser: Bool { cfg.oculta }
    /// Silenciada: sin voz, sin bocadillos y sin ir a buscarte, hasta esta hora.
    var mutedUntil: Date? {
        guard let t = cfg.silenciadaHasta else { return nil }
        let d = Date(timeIntervalSince1970: t)
        return d > Date() ? d : nil
    }
    var muted: Bool { mutedUntil != nil }
    /// Ni se ve ni habla ni viaja.
    var away: Bool { hiddenByUser || dndReason != nil }
    var dndCamera: Bool { cfg.noMolestarCamara }
    var dndScreen: Bool { cfg.noMolestarPantalla }
    let interruptions = Interruptions()
    let hotKeys = HotKeys()
    /// Atajos guardados; nil = desactivado.
    var toggleShortcut: Shortcut? { Shortcut(array: cfg.atajoMostrar) }
    var muteShortcut: Shortcut? { Shortcut(array: cfg.atajoCallar) }
    /// Por qué está en «no molestar» ahora mismo (nil si no lo está).
    var dndReason: String? {
        if dndCamera && interruptions.camera { return "cámara encendida" }
        if dndScreen, let s = interruptions.sharing { return s }
        return nil
    }
    var wasAway = false
    var quiet: Bool { muted || away }

    /// La voz elegida en Ajustes o, si no, la mejor en español de España que tengas instalada.
    var voice: AVSpeechSynthesisVoice? {
        if !cfg.voz.isEmpty, let v = AVSpeechSynthesisVoice(identifier: cfg.voz) { return v }
        return bestVoice
    }
    lazy var bestVoice: AVSpeechSynthesisVoice? = {
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
        drag.onMouseMoved = { [weak self] in self?.mouseMoved() }
        container.addSubview(drag)
        panel.contentView = container

        speech.delegate = watcher
        watcher.onChange = { [weak self] on in self?.js("carita.talking(\(on))") }

        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel = makePanel(NSRect(x: 0, y: 0, width: 10, height: 10))
        bubblePanel.ignoresMouseEvents = true
        bubblePanel.contentView = bubbleView
        bubblePanel.alphaValue = 0

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon(alert: false)
        statusItem.button?.toolTip = "Carita"
        store.onChange = { [weak self] old in self?.configChanged(from: old) }
        store.onError = { [weak self] msg in self?.notice(msg) }
        interruptions.onChange = { [weak self] in self?.interruptionsChanged() }
        interruptions.start()
        wasAway = away
        registerHotKeys()
        refreshMenu()
        scheduleUnmute()

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
        if !away { panel.orderFrontRegardless() }

        // el bocadillo y la mirada siguen al bicho cuando se mueve (arrastrar, viajar, cambiar de tamaño)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didResizeNotification, object: panel)
        startWatching()
    }

    // MARK: vigilar archivos y ratón (sin sondeo continuo)

    /// Los hooks escriben con `mv`, así que lo que cambia es la carpeta: se vigila ~/.carita.
    func startWatching() {
        let fd = open(stateDir, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in
                self?.performSelector(onMainThread: #selector(AppDelegate.checkFiles), with: nil, waitUntilDone: false)
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            dirSource = src
        }

        watchFile(configPath)

        // el ratón: fuera de la app (monitor global, no pide permisos) y dentro (monitor local)
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.mouseMoved() }) {
            mouseMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.mouseMoved(); return e }) {
            mouseMonitors.append(l)
        }

        // respaldo lento por si se pierde algún evento
        fallbackTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(fallbackTick),
                                             userInfo: nil, repeats: true)
        fallbackTimer?.tolerance = 0.5
    }

    /// Los editores a veces guardan escribiendo encima (sin `mv`): eso no cambia la carpeta,
    /// así que los archivos que se editan a mano se vigilan también uno a uno.
    func watchFile(_ path: String) {
        fileSources[path]?.source.cancel()
        fileSources[path] = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }   // aún no existe: lo vuelve a intentar checkFiles
        var st = stat()
        fstat(fd, &st)
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            self?.performSelector(onMainThread: #selector(AppDelegate.checkFiles), with: nil, waitUntilDone: false)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSources[path] = (src, UInt64(st.st_ino))
    }

    /// Tras un `mv` el descriptor apunta al archivo viejo: se vuelve a abrir.
    func rewatchFiles() {
        for path in [configPath] {
            var st = stat()
            let exists = stat(path, &st) == 0
            if exists && fileSources[path]?.inode != UInt64(st.st_ino) { watchFile(path) }
        }
    }

    @objc func fallbackTick() {
        checkFiles()
        mouseMoved()
    }

    @objc func panelMoved() {
        if !bubbleText.isEmpty && panel.frame != bubbleAnchor { layoutBubble() }
        mouseMoved()
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
        if away { js("carita.hidden(true)") }
        sendFaceConfig()
        if let msg = pendingNotice { pendingNotice = nil; notice(msg) }
        checkFiles()
        mouseMoved()
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
        debugLog(code)
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    /// Para pruebas: `open --env CARITA_LOG=/ruta/log build/Carita.app` apunta cada llamada a la cara.
    let debugLogPath = ProcessInfo.processInfo.environment["CARITA_LOG"]
    func debugLog(_ line: String) {
        guard let path = debugLogPath else { return }
        let text = String(format: "%.3f %@\n", Date().timeIntervalSince1970, line)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(text.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? text.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    func speak(_ text: String, interrupt: Bool, force: Bool = false) {
        guard force || !quiet else { return }
        debugLog("voz: " + text)
        let utterance = AVSpeechUtterance(string: text.replacingOccurrences(of: "*", with: ""))
        utterance.voice = voice
        utterance.rate = Float(cfg.velocidad)
        utterance.pitchMultiplier = Float(cfg.tono)
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

    /// Un aviso de la propia app (p. ej., «me callo»): sale aunque esté silenciada.
    func notice(_ text: String) {
        guard !away else { return }
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
        guard force || !quiet else { return }
        if force { noticeText = text }
        debugLog("bocadillo: " + text)
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
        statusItem.button?.image = statusIcon(alert: s == "asking")
        if s == "asking" {
            goFindUser()
        } else if homeOrigin != nil {
            goHome()
        }
    }

    func goFindUser() {
        guard seeksYou, !quiet, homeOrigin == nil, !userIsLookingAtTerminal() else { return }
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

    // MARK: archivos de estado

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

    @objc func checkFiles() {
        guard pageReady else { return }
        rewatchFiles()
        store.reloadIfChanged()

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
    }

    /// Los ojos siguen al ratón y solo el bicho recibe clics.
    func mouseMoved() {
        guard pageReady, !away else { return }
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
            if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over; debugLog("clicable \(over)") }
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

    /// El mismo menú para la barra de menús y para el clic derecho sobre el bicho.
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let why = dndReason {
            let info = NSMenuItem(title: "No molestar: \(why)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        let show = NSMenuItem(title: hiddenByUser ? "Mostrar Carita" : "Ocultar Carita", action: #selector(toggleHidden), keyEquivalent: "")
        show.target = self
        setKey(show, toggleShortcut)
        menu.addItem(show)
        if let until = mutedUntil {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            addToggle(menu, "Silenciada hasta las \(f.string(from: until))", true, #selector(toggleMute))
        } else {
            addToggle(menu, "Silenciar 1 hora", false, #selector(toggleMute))
        }
        setKey(menu.items.last!, muteShortcut)
        menu.addItem(.separator())

        addSubmenu(menu, "Tamaño",
                   [("Pequeño", 0.75), ("Normal", 1.0), ("Grande", 1.4)].map { ($0.0, $0.1 as Any, abs(Double(scale) - $0.1) < 0.01) },
                   #selector(setSize(_:)))
        addSubmenu(menu, "Disfraz", costumes.map { ($0.0, $0.1 as Any, costumeChoice == $0.1) }, #selector(setCostume(_:)))
        menu.addItem(.separator())
        addToggle(menu, "Leer mis respuestas en voz alta", readAloud, #selector(toggleRead))
        addToggle(menu, "Avisos con voz (¡Hecho!, te necesito…)", talks, #selector(toggleTalk))
        addToggle(menu, "Ir a buscarme cuando me necesita", seeksYou, #selector(toggleSeek))
        let dnd = NSMenuItem(title: "No molestar automático", action: nil, keyEquivalent: "")
        let dndMenu = NSMenu()
        dndMenu.autoenablesItems = false
        addToggle(dndMenu, "Al encender la cámara (videollamadas)", dndCamera, #selector(toggleDndCamera))
        addToggle(dndMenu, "Al compartir pantalla (Zoom, Compartir pantalla, pantalla duplicada)", dndScreen, #selector(toggleDndScreen))
        dndMenu.addItem(.separator())
        let now = NSMenuItem(title: "Ahora: " + [interruptions.camera ? "cámara encendida" : "cámara apagada",
                                                  interruptions.sharing ?? "sin compartir pantalla"].joined(separator: ", "),
                             action: nil, keyEquivalent: "")
        now.isEnabled = false
        dndMenu.addItem(now)
        dnd.submenu = dndMenu
        menu.addItem(dnd)
        addToggle(menu, "Abrir al iniciar sesión", SMAppService.mainApp.status == .enabled, #selector(toggleLogin))
        menu.addItem(.separator())
        addSubmenu(menu, "Probar expresión", testStates.map { ($0.0, $0.1 as Any, false) }, #selector(test(_:)))
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Salir de Carita", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Enseña el atajo junto a la opción (solo de muestra: lo que funciona es el atajo global).
    func setKey(_ item: NSMenuItem, _ shortcut: Shortcut?) {
        guard let sc = shortcut else { return }
        item.keyEquivalent = sc.keyName.lowercased()
        item.keyEquivalentModifierMask = sc.eventModifiers
    }

    func refreshMenu() {
        drag.menu = buildMenu()
        statusItem.menu = buildMenu()
    }

    /// Registra los atajos; si alguno choca con otra app, lo dice. Devuelve los que fallaron.
    @discardableResult
    func registerHotKeys(announce: Bool = true) -> [String] {
        var clash: [String] = []
        if !hotKeys.register(1, toggleShortcut, action: { [weak self] in self?.toggleHidden() }) {
            clash.append(toggleShortcut!.display)
        }
        if !hotKeys.register(2, muteShortcut, action: { [weak self] in self?.toggleMute() }) {
            clash.append(muteShortcut!.display)
        }
        if !clash.isEmpty {
            debugLog("atajo ocupado: " + clash.joined(separator: " "))
            if announce {
                let msg = "El atajo \(clash.joined(separator: " y ")) ya lo usa el Mac. Cámbialo en Ajustes."
                if pageReady { notice(msg) } else { pendingNotice = msg }
            }
        }
        return clash
    }

    func interruptionsChanged() {
        debugLog("no molestar: \(dndReason ?? "no")")
        if away != wasAway { applyVisibility() }
        refreshMenu()
    }

    @objc func toggleDndCamera() { store.c.noMolestarCamara.toggle() }
    @objc func toggleDndScreen() { store.c.noMolestarPantalla.toggle() }
    @objc func toggleHidden() { store.c.oculta.toggle() }

    /// Enseña o esconde el bicho (y su bocadillo) según `away`.
    func applyVisibility() {
        wasAway = away
        js("carita.hidden(\(away))")
        if away {
            speech.stopSpeaking(at: .immediate)
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

    @objc func toggleMute() {
        if muted {
            store.c.silenciadaHasta = nil
            notice("¡Ya puedo hablar otra vez!")
        } else {
            speech.stopSpeaking(at: .immediate)
            notice("Vale, me callo una horita")
            store.c.silenciadaHasta = Date().addingTimeInterval(3600).timeIntervalSince1970
        }
    }

    /// Al acabar el silencio, el menú vuelve a «Silenciar 1 hora» solo.
    func scheduleUnmute() {
        unmuteTimer?.invalidate()
        unmuteTimer = nil
        guard let until = mutedUntil else { return }
        unmuteTimer = Timer(fireAt: until.addingTimeInterval(0.5), interval: 0, target: self,
                            selector: #selector(unmuteFired), userInfo: nil, repeats: false)
        RunLoop.main.add(unmuteTimer!, forMode: .common)
    }

    @objc func unmuteFired() {
        scheduleUnmute()
        refreshMenu()
    }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        store.c.tamano = value
    }

    func applyScale(animate: Bool) {
        var f = panel.frame
        let newSize = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        f.origin.x += (f.width - newSize.width) / 2   // mantiene los pies en el mismo sitio
        f.size = newSize
        panel.setFrame(f, display: true, animate: animate)
        if !bubbleText.isEmpty { showBubble(bubbleText) }
    }

    @objc func setCostume(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        store.c.disfraz = value
    }

    @objc func toggleTalk() { store.c.avisosVoz.toggle() }
    @objc func toggleRead() { store.c.leerRespuestas.toggle() }
    @objc func toggleSeek() { store.c.irABuscarte.toggle() }

    @objc func openSettings() {
        settingsWindow.show(store: store, actions: SettingsActions(
            testVoice: { [weak self] in self?.speak("¡Hola, \(self?.cfg.nombre ?? "")! Así sueno ahora. ¿Te gusta?", interrupt: true, force: true) },
            dndStatus: { [weak self] in
                guard let self = self else { return "" }
                return [self.interruptions.camera ? "cámara encendida" : "cámara apagada",
                        self.interruptions.sharing ?? "sin compartir pantalla"].joined(separator: ", ")
            },
            pauseHotKeys: { [weak self] paused in
                guard let self = self else { return }
                if paused { self.hotKeys.unregister(1); self.hotKeys.unregister(2) } else { self.registerHotKeys(announce: false) }
            }))
    }

    /// Lo que la cara necesita saber de la config (nombre y tiempos del descanso, en ms).
    func sendFaceConfig() {
        let face: [String: Any] = [
            "nombre": cfg.nombre,
            "breakAfter": cfg.descansoMinutos * 60_000,
            "maskAfter": cfg.antifazMinutos * 60_000,
            "breakGap": cfg.pausaMinutos * 60_000,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: face),
              let json = String(data: data, encoding: .utf8) else { return }
        js("carita.config(\(json))")
    }

    /// Cualquier cambio de config (menú, Ajustes o config.json a mano) se aplica al momento.
    func configChanged(from old: Config) {
        let c = cfg
        if c.tamano != old.tamano { applyScale(animate: false) }
        if c.disfraz != old.disfraz { applyCostume() }
        if c.oculta != old.oculta || c.noMolestarCamara != old.noMolestarCamara || c.noMolestarPantalla != old.noMolestarPantalla {
            if away != wasAway { applyVisibility() }
        }
        if c.silenciadaHasta != old.silenciadaHasta {
            if muted { goHome() }
            scheduleUnmute()
        }
        if c.atajoMostrar != old.atajoMostrar || c.atajoCallar != old.atajoCallar { registerHotKeys() }
        if c.irABuscarte != old.irABuscarte && !c.irABuscarte { goHome() }
        if c.avisosVoz != old.avisosVoz && c.avisosVoz { speak("¡Vale! Te aviso con voz", interrupt: true) }
        if c.leerRespuestas != old.leerRespuestas {
            if c.leerRespuestas {
                js("carita.reply('Te leo un resumen de cada respuesta')")
                speak("Vale. A partir de ahora te leo un resumen de cada respuesta.", interrupt: true)
            } else {
                speech.stopSpeaking(at: .immediate)
                js("carita.say('Vale, me callo')")
            }
        }
        if c.nombre != old.nombre || c.descansoMinutos != old.descansoMinutos
            || c.antifazMinutos != old.antifazMinutos || c.pausaMinutos != old.pausaMinutos { sendFaceConfig() }
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
