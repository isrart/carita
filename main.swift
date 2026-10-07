// Carita — una cara flotante para Claude Code en el Mac.
// Lee ~/.carita/state, say y costume (los escriben los hooks de Claude Code) y se lo pasa a face.html.

import AppKit
import WebKit
import AVFoundation
import ServiceManagement
import CoreMediaIO
import Carbon.HIToolbox

/// Para pruebas, `CARITA_DIR=/otra/carpeta` aísla la app de las sesiones reales de Claude Code.
let stateDir = ProcessInfo.processInfo.environment["CARITA_DIR"]
    ?? (NSHomeDirectory() as NSString).appendingPathComponent(".carita")
let statePath = (stateDir as NSString).appendingPathComponent("state")
let sayPath = (stateDir as NSString).appendingPathComponent("say")
let costumePath = (stateDir as NSString).appendingPathComponent("costume")
let termPath = (stateDir as NSString).appendingPathComponent("term")
let phrasesPath = (stateDir as NSString).appendingPathComponent("frases.json")
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
    static let talkDefault = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey | cmdKey))

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
    private var releases: [UInt32: () -> Void] = [:]

    init() {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let userData = userData, let event = event {
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue().fire(hk.id, released: released)
            }
            return noErr
        }, 2, &specs, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func fire(_ id: UInt32, released: Bool) { (released ? releases[id] : actions[id])?() }

    /// Devuelve false si la combinación ya la usa macOS (o no se pudo registrar).
    @discardableResult
    func register(_ id: UInt32, _ shortcut: Shortcut?, action: @escaping () -> Void, release: (() -> Void)? = nil) -> Bool {
        unregister(id)
        guard let shortcut = shortcut else { return true }
        if shortcut.clashesWithSystem { return false }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x43617269), id: id)   // 'Cari'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else { return false }
        refs[id] = r
        actions[id] = action
        releases[id] = release
        return true
    }

    func unregister(_ id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        actions[id] = nil
        releases[id] = nil
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

/// Tamaño del dibujo a escala 1 (igual que el viewBox de face.html).
let baseSize = NSSize(width: 240, height: 224)
let sessionsDir = (stateDir as NSString).appendingPathComponent("sesiones")
let maxCreatures = 4

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Un bicho por sesión de Claude Code; siempre hay al menos uno (el primero guarda su sitio).
    var creatures: [Creature] = []
    var primary: Creature { creatures[0] }
    /// El que está hablando ahora (la voz es una para todos).
    weak var speaker: Creature?
    var dirSource: DispatchSourceFileSystemObject?
    var sessionsSource: DispatchSourceFileSystemObject?
    var fileSources: [String: (source: DispatchSourceFileSystemObject, inode: UInt64)] = [:]
    var fallbackTimer: Timer?
    var mouseMonitors: [Any] = []
    var lastMTime: Date?
    var lastSayMTime: Date?
    var lastCostumeMTime: Date?
    var lastReplyAt = Date.distantPast
    let watcher = SpeechWatcher()
    let speech = AVSpeechSynthesizer()
    var statusItem: NSStatusItem!
    var unmuteTimer: Timer?
    var pendingNotice: String?
    var lastPhrasesData: Data?
    var startedUp = false

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
    let diagnosticsWindow = DiagnosticsWindow()
    let statsWindow = StatsWindow()
    let updater = Updater()
    var updateTimer: Timer?
    let listener = Listener()
    let typist = Typist()
    /// El bicho que te está escuchando (mientras mantienes el atajo de hablar).
    weak var listening: Creature?
    var lastArrival: (state: String, at: Date)?
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
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
    var talkShortcut: Shortcut? { Shortcut(array: cfg.atajoHablar) }
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
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        updateScriptsIfNeeded()
        History.rotateIfNeeded()

        // no repetir lo último de la vez anterior al arrancar
        lastMTime = modDate(statePath)
        lastSayMTime = modDate(sayPath)

        let first = Creature(app: self, origin: nil)
        creatures = [first]
        // recuerda dónde lo dejaste, siempre que siga dentro de alguna pantalla
        let fallback = first.panel.frame
        if first.panel.setFrameUsingName("CaritaWindow2") {
            var f = first.panel.frame
            f.size = first.panelSize
            let visible = NSScreen.screens.contains { $0.frame.intersects(f) }
            first.panel.setFrame(visible ? f : fallback, display: false)
        }
        first.panel.setFrameAutosaveName("CaritaWindow2")
        if !away { first.panel.orderFrontRegardless() }

        speech.delegate = watcher
        watcher.onChange = { [weak self] on in self?.speaker?.js("carita.talking(\(on))") }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon(alert: false)
        statusItem.button?.toolTip = "Carita"
        store.onChange = { [weak self] old in self?.configChanged(from: old) }
        store.onError = { [weak self] msg in self?.notice(msg) }
        interruptions.onChange = { [weak self] in self?.interruptionsChanged() }
        interruptions.start()
        wasAway = away
        registerHotKeys()
        updater.onMessage = { [weak self] text in self?.notice(text) }
        listener.onText = { [weak self] text in self?.heard(text) }
        listener.onDone = { [weak self] text in self?.heardAll(text) }
        listener.onProblem = { [weak self] text in self?.listenProblem(text) }
        typist.onMessage = { [weak self] text in self?.typedMessage(text) }
        updater.onAvailable = { [weak self] _ in self?.refreshMenu() }
        updateTimer = Timer.scheduledTimer(timeInterval: 3600, target: self, selector: #selector(dailyUpdateCheck),
                                           userInfo: nil, repeats: true)
        updateTimer?.tolerance = 600
        refreshMenu()
        scheduleUnmute()
        resumeSessions()
        startWatching()

        // al dormir o bloquear, que el bicho no se quede con los clics (si el sistema pierde el «soltar»
        // de un clic al despertar, todos los clics podrían acabar en su ventana)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(self, selector: #selector(systemWillSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(self, selector: #selector(systemDidWake), name: name, object: nil)
        }
    }

    /// Cuando la cara de un bicho termina de cargar. La del primero arranca lo que depende de ella.
    func creatureReady(_ c: Creature) {
        guard c === creatures.first, !startedUp else { return }
        startedUp = true
        if let msg = pendingNotice { pendingNotice = nil; notice(msg) }
        dailyUpdateCheck()
        if ProcessInfo.processInfo.environment["CARITA_SNAPSHOT"] != nil {
            openSettings()
            openDiagnostics()
            openStats()
            Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(takeSnapshots), userInfo: nil, repeats: false)
        }
        checkFiles()
    }

    @objc func systemWillSleep() {
        debugLog("el Mac se duerme o se bloquea: los bichos dejan pasar los clics")
        for c in creatures {
            c.stopTravel()
            c.panel.ignoresMouseEvents = true
        }
    }

    @objc func systemDidWake() {
        debugLog("el Mac despierta")
        for c in creatures { c.panel.ignoresMouseEvents = true }
        // un segundo para que el sistema se asiente antes de volver a mirar dónde está el ratón
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(fallbackTick), userInfo: nil, repeats: false)
    }

    // MARK: vigilar archivos y ratón (sin sondeo continuo)

    func watchDir(_ path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            self?.performSelector(onMainThread: #selector(AppDelegate.checkFiles), with: nil, waitUntilDone: false)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }

    /// Los hooks escriben con `mv`, así que lo que cambia son las carpetas: ~/.carita y ~/.carita/sesiones.
    func startWatching() {
        dirSource = watchDir(stateDir)
        sessionsSource = watchDir(sessionsDir)
        watchFile(configPath)
        watchFile(phrasesPath)

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
        for path in [configPath, phrasesPath] {
            var st = stat()
            let exists = stat(path, &st) == 0
            if exists && fileSources[path]?.inode != UInt64(st.st_ino) { watchFile(path) }
        }
    }

    @objc func fallbackTick() {
        checkFiles()
        mouseMoved()
        sweepSessions()
    }

    func mouseMoved() {
        for c in creatures where !c.leaving { c.mouseMoved() }
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

    func sessionFile(_ sid: String, _ ext: String) -> String {
        (sessionsDir as NSString).appendingPathComponent("\(sid).\(ext)")
    }

    @objc func checkFiles() {
        guard startedUp else { return }
        rewatchFiles()
        store.reloadIfChanged()
        if phrasesData() != lastPhrasesData { sendFaceConfig() }

        // estado sin sesión (la prueba del diagnóstico, hooks antiguos): para el primer bicho
        if let m = modDate(statePath), m != lastMTime {
            lastMTime = m
            let s = readWord(statePath)
            if !s.isEmpty { arrived(s, for: primary) }
        }

        let costumeM = modDate(costumePath) ?? .distantPast
        if costumeM != lastCostumeMTime {
            lastCostumeMTime = costumeM
            for c in creatures where c.sessionID == nil { c.applyCostume() }
        }
        if let m = modDate(sayPath), m != lastSayMTime {
            lastSayMTime = m
            readReply(sayPath, m, by: primary)
        }

        // cada sesión, a su bicho
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir)) ?? []
        for file in names where file.hasSuffix(".state") {
            let sid = String(file.dropLast(".state".count))
            let path = sessionFile(sid, "state")
            guard let m = modDate(path) else { continue }
            var c = creatures.first { $0.sessionID == sid && !$0.leaving }
            if c == nil {
                // una sesión nueva (o que vuelve): solo si el aviso es reciente
                guard Date().timeIntervalSince(m) < 600, readWord(path) != "bye" else { continue }
                c = adopt(sid)
            }
            guard let creature = c else { continue }
            refreshInfo(creature)
            if m != creature.lastStateMTime {
                creature.lastStateMTime = m
                let s = readWord(path)
                if !s.isEmpty { arrived(s, for: creature) }
            }
            let sayFile = sessionFile(sid, "say")
            if let sm = modDate(sayFile), sm != creature.lastSayMTime {
                creature.lastSayMTime = sm
                readReply(sayFile, sm, by: creature)
            }
        }
    }

    /// Un estado que llega para un bicho.
    func arrived(_ s: String, for c: Creature) {
        lastArrival = (s, Date())
        // si le preguntas otra cosa mientras habla, se calla
        if workStates.contains(s) && speech.isSpeaking && speaker === c { speech.stopSpeaking(at: .word) }
        c.set(s)
        if s == "bye", c.sessionID != nil {
            Timer.scheduledTimer(timeInterval: 6, target: self, selector: #selector(retireFired(_:)), userInfo: c, repeats: false)
        }
        statusItem.button?.image = statusIcon(alert: creatures.contains { $0.currentState == "asking" && !$0.leaving })
    }

    /// El resumen de una respuesta, para leerlo en voz alta.
    func readReply(_ path: String, _ m: Date, by c: Creature) {
        guard readAloud, Date().timeIntervalSince(m) < 20,
              let data = FileManager.default.contents(atPath: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = obj["voice"] as? String, !text.isEmpty else { return }
        let bubbleText = (obj["bubble"] as? String) ?? text
        lastReplyAt = Date()
        c.js("carita.reply(\(jsString(bubbleText)))")
        speak(text, interrupt: true, by: c)
    }

    /// Relee la ficha de la sesión (proyecto, disfraz, pestaña) si ha cambiado.
    func refreshInfo(_ c: Creature) {
        guard let sid = c.sessionID else { return }
        let path = sessionFile(sid, "info")
        let m = modDate(path)
        guard m != c.lastInfoMTime else { return }
        c.lastInfoMTime = m
        let old = c.info
        c.info = SessionInfo(path: path) ?? SessionInfo()
        if c.info.disfraz != old.disfraz { c.applyCostume() }
        if c.info.proyecto != old.proyecto { updateLabels() }
    }

    // MARK: un bicho por sesión

    /// Al arrancar, los bichos de las sesiones que seguían activas hace poco (sin repetir su último estado).
    func resumeSessions() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir)) ?? []
        let recent = names.filter { $0.hasSuffix(".state") }.compactMap { file -> (String, Date)? in
            let sid = String(file.dropLast(".state".count))
            guard let m = modDate(sessionFile(sid, "state")), Date().timeIntervalSince(m) < 1800,
                  readWord(sessionFile(sid, "state")) != "bye" else { return nil }
            return (sid, m)
        }.sorted { $0.1 > $1.1 }
        for (sid, m) in recent.prefix(maxCreatures) {
            let c = adopt(sid)
            c.lastStateMTime = m
            c.lastSayMTime = modDate(sessionFile(sid, "say"))
        }
    }

    /// El bicho para una sesión nueva: el libre si lo hay; si no, uno nuevo al lado de los demás.
    func adopt(_ sid: String) -> Creature {
        let c: Creature
        if let free = creatures.first(where: { $0.sessionID == nil && !$0.leaving }) {
            c = free
        } else if creatures.filter({ !$0.leaving }).count >= maxCreatures,
                  let oldest = creatures.filter({ !$0.leaving && $0.currentState != "asking" }).min(by: { $0.lastEvent < $1.lastEvent }) {
            c = oldest   // ya hay demasiados: el que lleva más rato sin hacer nada cambia de sesión
        } else {
            c = Creature(app: self, origin: spawnOrigin())
            creatures.append(c)
            if !away { c.panel.orderFrontRegardless() }
        }
        c.sessionID = sid
        c.lastInfoMTime = nil
        c.lastStateMTime = nil
        c.lastSayMTime = nil
        c.lastEvent = Date()
        refreshInfo(c)
        c.applyCostume()
        updateLabels()
        debugLog("sesión \(sid) → bicho \(c.name)")
        return c
    }

    /// A la izquierda del que esté más a la izquierda; si no cabe, a la derecha del último.
    func spawnOrigin() -> NSPoint {
        let alive = creatures.filter { !$0.leaving }
        guard let leftmost = alive.min(by: { $0.panel.frame.minX < $1.panel.frame.minX }),
              let rightmost = alive.max(by: { $0.panel.frame.maxX < $1.panel.frame.maxX }) else { return .zero }
        let f = leftmost.panel.frame
        let screen = leftmost.panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? f
        let step = f.width * 0.72   // los paneles tienen margen transparente: así quedan juntitos
        if f.minX - step >= screen.minX { return NSPoint(x: f.minX - step, y: f.minY) }
        let r = rightmost.panel.frame
        if r.minX + step + r.width <= screen.maxX { return NSPoint(x: r.minX + step, y: r.minY) }
        return NSPoint(x: f.minX, y: min(f.minY + f.height * 0.8, screen.maxY - f.height))
    }

    @objc func retireFired(_ timer: Timer) {
        guard let c = timer.userInfo as? Creature, c.currentState == "bye" || c.currentState == "sleepy" else { return }
        retire(c)
    }

    /// Su sesión ha terminado: si hay más bichos se va; si es el último, se queda sin sesión.
    func retire(_ c: Creature) {
        if let sid = c.sessionID {
            for ext in ["state", "say", "info"] { try? FileManager.default.removeItem(atPath: sessionFile(sid, ext)) }
            debugLog("sesión \(sid) terminada (bicho \(c.name))")
        }
        if speaker === c { speech.stopSpeaking(at: .word) }
        let others = creatures.filter { $0 !== c && !$0.leaving }
        if others.isEmpty {
            c.sessionID = nil
            c.info = SessionInfo()
            c.applyCostume()
        } else {
            let wasFirst = c === creatures.first
            c.dismiss()
            creatures.removeAll { $0 === c }
            if wasFirst { primary.panel.setFrameAutosaveName("CaritaWindow2") }
        }
        updateLabels()
    }

    /// Sesiones que se cerraron sin despedirse (terminal cerrada): fuera tras 45 min sin noticias.
    func sweepSessions() {
        for c in creatures where c.sessionID != nil && !c.leaving && c.currentState != "asking" {
            if Date().timeIntervalSince(c.lastEvent) > 45 * 60 { retire(c) }
        }
    }

    /// El nombre del proyecto debajo de cada bicho, solo si hay más de uno.
    func updateLabels() {
        let alive = creatures.filter { !$0.leaving }
        for c in alive { c.showLabel(alive.count > 1) }
    }

    // MARK: voz

    func speak(_ text: String, interrupt: Bool, force: Bool = false, by c: Creature? = nil) {
        guard force || !quiet else { return }
        debugLog("voz (\((c ?? primary).name)): " + text)
        let utterance = AVSpeechUtterance(string: text.replacingOccurrences(of: "*", with: ""))
        utterance.voice = voice
        utterance.rate = Float(cfg.velocidad)
        utterance.pitchMultiplier = Float(cfg.tono)
        if interrupt && speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        if let old = speaker, old !== (c ?? primary) { old.js("carita.talking(false)") }
        speaker = c ?? primary
        speech.speak(utterance)
    }

    /// Avisos cortos ("¡Hecho!", "te necesito"); no pisan la lectura de una respuesta.
    func shortSay(_ text: String, by c: Creature) {
        if talks, Date().timeIntervalSince(lastReplyAt) > 4, !text.isEmpty { speak(text, interrupt: true, by: c) }
    }

    // MARK: hablarle

    /// A quién le hablas: al bicho de la sesión que tuvo actividad la última.
    func listenTarget() -> Creature? {
        let alive = creatures.filter { !$0.leaving }
        return alive.filter { $0.sessionID != nil }.max { $0.lastEvent < $1.lastEvent } ?? alive.first
    }

    func talkPressed() {
        guard !away, listening == nil, let c = listenTarget() else { return }
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        listening = c
        c.js("carita.listen(true)")
        c.showBubble("Te escucho…", force: true)
        listener.start()
    }

    func talkReleased() {
        guard listening != nil else { return }
        listener.stop()
    }

    func heard(_ text: String) {
        guard let c = listening, !text.isEmpty else { return }
        c.showBubble(text, force: true)
    }

    func heardAll(_ text: String) {
        guard let c = listening else { return }
        listening = nil
        c.js("carita.listen(false)")
        guard !text.isEmpty else {
            c.notice("No te he oído nada")
            return
        }
        debugLog("\(c.name): oído «\(text)»")
        c.showBubble(text, force: true)
        typedTo = c
        typist.type(text, term: termBundle(for: c), tty: c.info.tty)
    }

    func listenProblem(_ text: String) {
        let c = listening ?? listenTarget()
        listening = nil
        c?.js("carita.listen(false)")
        c?.notice(text)
    }

    weak var typedTo: Creature?
    func typedMessage(_ text: String) {
        (typedTo ?? primary).notice(text)
    }

    /// Avisos de la app: los dice el primer bicho.
    func notice(_ text: String) {
        guard let first = creatures.first else { return }
        if first.pageReady { first.notice(text) } else { pendingNotice = text }
    }

    func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "''" }
        return String(json.dropFirst().dropLast())
    }

    /// Para pruebas: `open --env CARITA_SNAPSHOT=/carpeta build/Carita.app` abre las ventanas
    /// (ajustes, diagnóstico, estadísticas) y las guarda como PNG en esa carpeta.
    @objc func takeSnapshots() {
        guard let dir = ProcessInfo.processInfo.environment["CARITA_SNAPSHOT"] else { return }
        // solo las ventanas normales (ni los bichos ni el icono de la barra de menús)
        for w in NSApp.windows where w.isVisible && w.styleMask.contains(.titled) {
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = w.title.replacingOccurrences(of: " ", with: "-")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            w.close()
        }
        debugLog("capturas guardadas en \(dir)")
    }

    // MARK: la terminal

    func termBundle(for c: Creature? = nil) -> String? {
        if let t = c?.info.term, !t.isEmpty { return t }
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
    func focusTerminal(for c: Creature) -> Bool {
        guard let id = termBundle(for: c),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
        return true
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

        if let rel = updater.available {
            let up = NSMenuItem(title: "Actualizar a la \(rel.version)…", action: #selector(installUpdate), keyEquivalent: "")
            up.target = self
            menu.addItem(up)
            menu.addItem(.separator())
        }
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
        if let talk = talkShortcut {
            let hint = NSMenuItem(title: "Para hablarle, mantén \(talk.display)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
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
        let check = NSMenuItem(title: "Buscar actualizaciones…", action: #selector(checkUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let stats = NSMenuItem(title: "Estadísticas…", action: #selector(openStats), keyEquivalent: "")
        stats.target = self
        menu.addItem(stats)
        let diagnostics = NSMenuItem(title: "Diagnóstico…", action: #selector(openDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
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
        for c in creatures { c.drag.menu = buildMenu() }
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
        if !hotKeys.register(3, talkShortcut, action: { [weak self] in self?.talkPressed() },
                             release: { [weak self] in self?.talkReleased() }) {
            clash.append(talkShortcut!.display)
        }
        if !clash.isEmpty {
            debugLog("atajo ocupado: " + clash.joined(separator: " "))
            if announce {
                let msg = "El atajo \(clash.joined(separator: " y ")) ya lo usa el Mac. Cámbialo en Ajustes."
                notice(msg)
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

    /// Enseña o esconde los bichos (y sus bocadillos) según `away`.
    func applyVisibility() {
        wasAway = away
        if away { speech.stopSpeaking(at: .immediate) }
        for c in creatures where !c.leaving { c.applyVisibility(away) }
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

    func goHomeAll() {
        for c in creatures { c.goHome() }
    }

    @objc func setCostume(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        store.c.disfraz = value
    }

    @objc func toggleTalk() { store.c.avisosVoz.toggle() }
    @objc func toggleRead() { store.c.leerRespuestas.toggle() }
    @objc func toggleSeek() { store.c.irABuscarte.toggle() }

    /// Si los scripts de ~/.carita no son los de esta versión de la app, los cambia solos.
    /// Solo si ya estaban instalados: instalar hooks es cosa de install.sh o del diagnóstico.
    func updateScriptsIfNeeded() {
        guard FileManager.default.fileExists(atPath: hookPath), !Scripts.upToDate() else { return }
        let old = Scripts.version(at: helperPath) ?? "?"
        let ok = Scripts.copyToHome()
        debugLog("scripts de ~/.carita: \(old) → \(appVersion) \(ok ? "actualizados" : "ERROR")")
    }

    @objc func openStats() { statsWindow.show() }

    @objc func checkUpdates() {
        store.c.ultimaComprobacion = Date().timeIntervalSince1970
        updater.check(interactive: true)
    }

    /// Una vez al día como mucho, y solo si está activado en Ajustes.
    @objc func dailyUpdateCheck() {
        guard cfg.buscarActualizaciones else { return }
        let last = cfg.ultimaComprobacion.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        store.c.ultimaComprobacion = Date().timeIntervalSince1970
        updater.check(interactive: false)
    }

    @objc func installUpdate() { updater.install() }

    @objc func openDiagnostics() {
        diagnosticsWindow.show(info: DiagnosticsInfo(
            appVersion: appVersion,
            voiceName: { [weak self] in
                guard let v = self?.voice else { return "Ninguna en español de España" }
                return "\(VoiceTab.displayName(v)) (\(VoiceTab.qualityName(v)))"
            },
            lastArrival: { [weak self] in self?.lastArrival }))
    }

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
                if paused { for id: UInt32 in 1...3 { self.hotKeys.unregister(id) } } else { self.registerHotKeys(announce: false) }
            },
            editPhrases: { [weak self] in self?.editPhrases() }))
    }

    func phrasesData() -> Data? { FileManager.default.contents(atPath: phrasesPath) }

    /// Las frases de ~/.carita/frases.json. Si no existe, ninguna (se usan las de serie);
    /// si está mal, las de serie y un aviso con la línea del error.
    func loadPhrases() -> [String: Any] {
        let data = phrasesData()
        lastPhrasesData = data
        guard let data = data, !data.isEmpty else { return [:] }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                notice("frases.json tiene que ser un objeto: {\"done\": [\"…\"]}. Sigo con las de serie.")
                return [:]
            }
            return obj
        } catch {
            notice("Hay un error en frases.json\(jsonErrorLine(error, data).map { ", línea \($0)" } ?? ""). Sigo con las de serie.")
            return [:]
        }
    }

    /// La línea del error de JSON: del mensaje («line 3») o contando saltos hasta el carácter que falla.
    func jsonErrorLine(_ error: Error, _ data: Data) -> Int? {
        let ns = error as NSError
        let text = [ns.userInfo[NSDebugDescriptionErrorKey] as? String, ns.localizedDescription].compactMap { $0 }.joined(separator: " ")
        func number(after word: String) -> Int? {
            guard let r = text.range(of: word + " ") else { return nil }
            return Int(text[r.upperBound...].prefix { $0.isNumber })
        }
        if let line = number(after: "line") { return line }
        if let idx = (ns.userInfo["NSJSONSerializationErrorIndex"] as? Int) ?? number(after: "character") {
            return data.prefix(idx).filter { $0 == 10 }.count + 1
        }
        return nil
    }

    /// Crea frases.json con las de serie (si no existe) y lo abre en tu editor.
    func editPhrases() {
        let url = URL(fileURLWithPath: phrasesPath)
        if FileManager.default.fileExists(atPath: phrasesPath) {
            NSWorkspace.shared.open(url)
            return
        }
        primary.web.evaluateJavaScript("JSON.stringify(carita.frasesDeSerie())") { result, _ in
            var obj: [String: Any] = ["_ayuda": "Cada clave sustituye a las frases de serie de ese estado; \"+done\" añade en vez de sustituir. {n} es tu nombre y {t} el tiempo trabajado. Borra las que no quieras cambiar."]
            if let json = result as? String, let data = json.data(using: .utf8),
               let serie = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj.merge(serie) { a, _ in a }
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? data.write(to: url, options: .atomic)
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Lo que la cara necesita saber de la config (nombre, tiempos del descanso en ms y frases).
    /// Sin bicho: a todos (las frases se leen una sola vez, para no repetir avisos de error).
    func sendFaceConfig(to one: Creature? = nil) {
        let face: [String: Any] = [
            "nombre": cfg.nombre,
            "breakAfter": cfg.descansoMinutos * 60_000,
            "maskAfter": cfg.antifazMinutos * 60_000,
            "breakGap": cfg.pausaMinutos * 60_000,
            "frases": loadPhrases(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: face),
              let json = String(data: data, encoding: .utf8) else { return }
        for c in one.map({ [$0] }) ?? creatures { c.js("carita.config(\(json))") }
    }

    /// Cualquier cambio de config (menú, Ajustes o config.json a mano) se aplica al momento.
    func configChanged(from old: Config) {
        let c = cfg
        if c.tamano != old.tamano { for k in creatures { k.applyScale() } }
        if c.disfraz != old.disfraz { for k in creatures { k.applyCostume() } }
        if c.oculta != old.oculta || c.noMolestarCamara != old.noMolestarCamara || c.noMolestarPantalla != old.noMolestarPantalla {
            if away != wasAway { applyVisibility() }
        }
        if c.silenciadaHasta != old.silenciadaHasta {
            if muted { goHomeAll() }
            scheduleUnmute()
        }
        if c.atajoMostrar != old.atajoMostrar || c.atajoCallar != old.atajoCallar || c.atajoHablar != old.atajoHablar { registerHotKeys() }
        if c.irABuscarte != old.irABuscarte && !c.irABuscarte { goHomeAll() }
        if c.avisosVoz != old.avisosVoz && c.avisosVoz { speak("¡Vale! Te aviso con voz", interrupt: true) }
        if c.leerRespuestas != old.leerRespuestas {
            if c.leerRespuestas {
                primary.js("carita.reply('Te leo un resumen de cada respuesta')")
                speak("Vale. A partir de ahora te leo un resumen de cada respuesta.", interrupt: true)
            } else {
                speech.stopSpeaking(at: .immediate)
                primary.js("carita.say('Vale, me callo')")
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
        for c in creatures where !c.leaving { c.js("carita.set('\(state)')") }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
