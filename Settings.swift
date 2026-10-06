// Ajustes de Carita: ~/.carita/config.json (la única fuente de verdad) y la ventana para editarlos.

import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement
import Carbon.HIToolbox

let configPath = (stateDir as NSString).appendingPathComponent("config.json")

/// Palabras de la ruta del proyecto → disfraz. Se miran en orden: la primera que encaja gana.
struct CostumeRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var palabras: [String]
    var disfraz: String
    enum CodingKeys: String, CodingKey { case palabras, disfraz }
}

struct Config: Codable, Equatable {
    var nombre = "Isra"
    var tamano: Double = 1
    var disfraz = "auto"
    var leerRespuestas = true
    var avisosVoz = false
    var irABuscarte = true
    var voz = ""                 // identificador de la voz; vacío = la mejor en es-ES
    var velocidad: Double = 0.5
    var tono: Double = 1.15
    var descansoMinutos: Double = 90
    var antifazMinutos: Double = 10
    var pausaMinutos: Double = 5
    var disfraces = Config.reglasDeSerie
    var noMolestarCamara = true
    var noMolestarPantalla = true
    var atajoMostrar = Shortcut.toggleDefault.array   // [] = sin atajo
    var atajoCallar = Shortcut.muteDefault.array
    var oculta = false
    var silenciadaHasta: Double?  // segundos desde 1970

    /// Las mismas que tenía carita.py: los subproyectos antes que lo genérico de Bajovelo.
    static let reglasDeSerie = [
        CostumeRule(palabras: ["trivia", "quiz", "preguntas", "denominacion"], disfraz: "vinotrivia"),
        CostumeRule(palabras: ["reel", "insta", "video", "redes", "social"], disfraz: "vinoreels"),
        CostumeRule(palabras: ["recurso", "resource", "guia", "ficha", "descarga"], disfraz: "vinorecursos"),
        CostumeRule(palabras: ["blog", "articulo"], disfraz: "vinoblog"),
        CostumeRule(palabras: ["bajovelo", "vino", "wine", "sommelier"], disfraz: "vino"),
    ]

    enum CodingKeys: String, CodingKey {
        case nombre, tamano, disfraz, leerRespuestas, avisosVoz, irABuscarte, voz, velocidad, tono
        case descansoMinutos, antifazMinutos, pausaMinutos, disfraces, noMolestarCamara, noMolestarPantalla
        case atajoMostrar, atajoCallar, oculta, silenciadaHasta
    }

    init() {}

    /// Lo que falte o tenga un tipo raro se queda con el valor de serie.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let d = Config()
        nombre = v(.nombre, d.nombre)
        tamano = min(2, max(0.5, v(.tamano, d.tamano)))
        disfraz = v(.disfraz, d.disfraz)
        leerRespuestas = v(.leerRespuestas, d.leerRespuestas)
        avisosVoz = v(.avisosVoz, d.avisosVoz)
        irABuscarte = v(.irABuscarte, d.irABuscarte)
        voz = v(.voz, d.voz)
        velocidad = v(.velocidad, d.velocidad)
        tono = v(.tono, d.tono)
        descansoMinutos = v(.descansoMinutos, d.descansoMinutos)
        antifazMinutos = v(.antifazMinutos, d.antifazMinutos)
        pausaMinutos = v(.pausaMinutos, d.pausaMinutos)
        disfraces = v(.disfraces, d.disfraces)
        noMolestarCamara = v(.noMolestarCamara, d.noMolestarCamara)
        noMolestarPantalla = v(.noMolestarPantalla, d.noMolestarPantalla)
        atajoMostrar = v(.atajoMostrar, d.atajoMostrar)
        atajoCallar = v(.atajoCallar, d.atajoCallar)
        oculta = v(.oculta, d.oculta)
        silenciadaHasta = try? c.decode(Double.self, forKey: .silenciadaHasta)
    }

    static func == (a: Config, b: Config) -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(a)) == (try? enc.encode(b))
    }
}

/// Lee y guarda config.json. Si lo editas a mano, se recarga solo (la app vigila ~/.carita).
final class ConfigStore: ObservableObject {
    @Published var c: Config {
        didSet {
            guard c != oldValue else { return }
            if !loading { save() }
            onChange?(oldValue)
        }
    }
    var onChange: ((Config) -> Void)?
    var onError: ((String) -> Void)?
    private var loading = false
    private var lastData: Data?

    init() {
        c = Config()
        if let data = FileManager.default.contents(atPath: configPath) {
            lastData = data
            if let cfg = try? JSONDecoder().decode(Config.self, from: data) { c = cfg }
        } else {
            c = ConfigStore.migrateFromDefaults()
            save()
        }
    }

    /// Los ajustes de antes (1.4.x) vivían en UserDefaults: se pasan aquí una vez y se borran de allí.
    static func migrateFromDefaults() -> Config {
        let d = UserDefaults.standard
        var c = Config()
        if d.double(forKey: "scale") > 0 { c.tamano = d.double(forKey: "scale") }
        if d.object(forKey: "talks") != nil { c.avisosVoz = d.bool(forKey: "talks") }
        if d.object(forKey: "readAloud") != nil { c.leerRespuestas = d.bool(forKey: "readAloud") }
        if d.object(forKey: "seeksYou") != nil { c.irABuscarte = d.bool(forKey: "seeksYou") }
        if let s = d.string(forKey: "costume") { c.disfraz = s }
        c.oculta = d.bool(forKey: "hidden")
        if let m = d.object(forKey: "mutedUntil") as? Date, m > Date() { c.silenciadaHasta = m.timeIntervalSince1970 }
        if d.object(forKey: "dndCamera") != nil { c.noMolestarCamara = d.bool(forKey: "dndCamera") }
        if d.object(forKey: "dndScreen") != nil { c.noMolestarPantalla = d.bool(forKey: "dndScreen") }
        if let a = d.array(forKey: "hotkeyToggle") as? [Int] { c.atajoMostrar = a }
        if let a = d.array(forKey: "hotkeyMute") as? [Int] { c.atajoCallar = a }
        for k in ["scale", "talks", "readAloud", "seeksYou", "costume", "hidden", "mutedUntil",
                  "dndCamera", "dndScreen", "hotkeyToggle", "hotkeyMute"] { d.removeObject(forKey: k) }
        return c
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(c) else { return }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if (try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)) != nil { lastData = data }
    }

    /// Si config.json ha cambiado por fuera, lo vuelve a leer.
    func reloadIfChanged() {
        guard let data = FileManager.default.contents(atPath: configPath), data != lastData else { return }
        lastData = data
        do {
            let cfg = try JSONDecoder().decode(Config.self, from: data)
            loading = true
            c = cfg
            loading = false
        } catch {
            onError?("Hay un error en config.json; sigo con lo de antes")
        }
    }
}

// MARK: ventana

/// Lo que la ventana necesita de la app.
struct SettingsActions {
    var testVoice: () -> Void
    var dndStatus: () -> String
    var pauseHotKeys: (Bool) -> Void
    var editPhrases: () -> Void
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(store: ConfigStore, actions: SettingsActions) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Ajustes de Carita"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(store: store, actions: actions))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)   // la app es LSUIElement: si no, la ventana sale detrás
        window?.makeKeyAndOrderFront(nil)
    }
}

let costumeNames: [(String, String)] = [
    ("Sin disfraz", "none"), ("Bajovelo (boina y copa)", "vino"), ("Blog (pluma y cuaderno)", "vinoblog"),
    ("Recursos (guía de vino)", "vinorecursos"), ("Trivia (cartel ?)", "vinotrivia"), ("Reels (móvil grabando)", "vinoreels"),
]

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions

    var body: some View {
        TabView {
            GeneralTab(store: store, actions: actions).tabItem { Label("General", systemImage: "gearshape") }
            VoiceTab(store: store, actions: actions).tabItem { Label("Voz", systemImage: "speaker.wave.2") }
            BreakTab(store: store).tabItem { Label("Descanso", systemImage: "cup.and.saucer") }
            CostumeTab(store: store).tabItem { Label("Disfraces", systemImage: "theatermasks") }
            DndTab(store: store, actions: actions).tabItem { Label("No molestar", systemImage: "moon") }
            ShortcutTab(store: store, actions: actions).tabItem { Label("Atajos", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 500)
    }
}

/// Pie de sección en gris, que puede ocupar varias líneas.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Deslizador con su valor a la derecha.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(maxWidth: 260)
                Text(format(value)).monospacedDigit().foregroundColor(.secondary).frame(width: 48, alignment: .trailing)
            }
        }
    }
}

struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                TextField("Tu nombre", text: $store.c.nombre)
            } footer: {
                Hint("Así te llama cuando te necesita o se despide.")
            }
            Section {
                ValueSlider(title: "Tamaño", value: $store.c.tamano, range: 0.6...1.6, step: 0.05) { "\(Int(($0 * 100).rounded())) %" }
                Toggle("Ir a buscarme cuando me necesita", isOn: $store.c.irABuscarte)
            }
            Section {
                LabeledContent("Lo que dice") {
                    Button("Editar frases…") { actions.editPhrases() }
                }
            } footer: {
                Hint("Abre ~/.carita/frases.json (lo crea con las frases de serie si no existe). Cada estado que pongas sustituye a sus frases; con \"+done\" añades en vez de sustituir. Al guardar, la siguiente frase ya es la nueva.")
            }
            Section {
                Toggle("Abrir al iniciar sesión", isOn: Binding(get: { login }, set: { on in
                    let service = SMAppService.mainApp
                    do { if on { try service.register() } else { try service.unregister() } } catch { NSSound.beep() }
                    login = service.status == .enabled
                }))
            }
        }
        .formStyle(.grouped)
    }
}

struct VoiceTab: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions

    static func voices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "es-ES" }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }
    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "prémium"
        case .enhanced: return "mejorada"
        default: return "básica"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Leer mis respuestas en voz alta", isOn: $store.c.leerRespuestas)
                Toggle("Avisos con voz (¡Hecho!, te necesito…)", isOn: $store.c.avisosVoz)
            }
            Section {
                Picker("Voz", selection: $store.c.voz) {
                    Text("Automática (la mejor que tengas)").tag("")
                    Divider()
                    ForEach(VoiceTab.voices(), id: \.identifier) { v in
                        Text("\(v.name) · \(VoiceTab.qualityName(v))").tag(v.identifier)
                    }
                }
                ValueSlider(title: "Velocidad", value: $store.c.velocidad, range: 0.3...0.7) { String(format: "%.2f", $0) }
                ValueSlider(title: "Tono", value: $store.c.tono, range: 0.7...1.6) { String(format: "%.2f", $0) }
                HStack {
                    Button("Valores de serie") {
                        store.c.velocidad = Config().velocidad
                        store.c.tono = Config().tono
                    }
                    Spacer()
                    Button { actions.testVoice() } label: { Label("Probar", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
            } footer: {
                Hint("¿Suena robótica? Descarga una voz «mejorada» o «prémium»: Ajustes del Sistema → Accesibilidad → Contenido leído → Voz del sistema → Gestionar voces → Español (España).")
            }
        }
        .formStyle(.grouped)
    }
}

struct BreakTab: View {
    @ObservedObject var store: ConfigStore

    func minutes(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            Stepper(value: value, in: range, step: step) {
                Text("\(Int(value.wrappedValue)) min").monospacedDigit()
            }
        }
    }

    var body: some View {
        Form {
            Section {
                minutes("Pedirte que te estires tras", $store.c.descansoMinutos, 15...240, step: 5)
                minutes("Ponerse el antifaz si lo ignoras", $store.c.antifazMinutos, 1...60, step: 1)
                minutes("Pausa que cuenta como descanso", $store.c.pausaMinutos, 1...30, step: 1)
            } footer: {
                Hint("Cuenta el tiempo de trabajo seguido con Claude Code. Si paras el rato de la pausa, el contador vuelve a cero.")
            }
        }
        .formStyle(.grouped)
    }
}

struct CostumeTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                Picker("Disfraz", selection: $store.c.disfraz) {
                    Text("Automático (según el proyecto)").tag("auto")
                    Divider()
                    ForEach(costumeNames, id: \.1) { Text($0.0).tag($0.1) }
                }
            }
            Section {
                ForEach(Array(store.c.disfraces.enumerated()), id: \.element.id) { i, rule in
                    CostumeRow(store: store, index: i)
                }
                HStack {
                    Button { store.c.disfraces.append(CostumeRule(palabras: [], disfraz: "vino")) } label: {
                        Label("Añadir regla", systemImage: "plus")
                    }
                    Spacer()
                    Button("Valores de serie") { store.c.disfraces = Config.reglasDeSerie }
                }
            } header: {
                Text("Palabras en la ruta del proyecto")
            } footer: {
                Hint("En automático gana la primera regla con alguna palabra que aparezca en la carpeta. Un archivo .carita en la raíz del proyecto manda sobre todo.")
            }
        }
        .formStyle(.grouped)
    }
}

struct CostumeRow: View {
    @ObservedObject var store: ConfigStore
    let index: Int

    var body: some View {
        let rules = store.c.disfraces
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { index < rules.count ? rules[index].palabras.joined(separator: ", ") : "" },
                set: { text in
                    guard index < store.c.disfraces.count else { return }
                    store.c.disfraces[index].palabras = text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                }), prompt: Text("palabras, separadas por comas"))
                .labelsHidden()
            Image(systemName: "arrow.right").foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { index < rules.count ? rules[index].disfraz : "none" },
                set: { if index < store.c.disfraces.count { store.c.disfraces[index].disfraz = $0 } })) {
                ForEach(costumeNames, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .frame(width: 180)
            ControlGroup {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(index >= rules.count - 1)
                Button { store.c.disfraces.remove(at: index) } label: { Image(systemName: "trash") }
            }
            .frame(width: 96)
        }
    }

    func move(_ d: Int) {
        let j = index + d
        guard j >= 0, j < store.c.disfraces.count else { return }
        store.c.disfraces.swapAt(index, j)
    }
}

struct DndTab: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle("Esconderse al encender la cámara", isOn: $store.c.noMolestarCamara)
                Toggle("Esconderse al compartir pantalla", isOn: $store.c.noMolestarPantalla)
            } footer: {
                Hint("La cámara vale para cualquier videollamada. Compartir pantalla: Zoom, Compartir pantalla del Mac y pantalla duplicada (AirPlay o proyector); Meet o Teams en el navegador sin cámara no se pueden detectar, ni el modo concentración.")
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("Ahora mismo", value: actions.dndStatus())
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutTab: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                ShortcutRecorder(title: "Mostrar u ocultar", value: $store.c.atajoMostrar, other: store.c.atajoCallar,
                                 fallback: Shortcut.toggleDefault, actions: actions)
                ShortcutRecorder(title: "Callarla (y silenciar 1 hora)", value: $store.c.atajoCallar, other: store.c.atajoMostrar,
                                 fallback: Shortcut.muteDefault, actions: actions)
            } footer: {
                Hint("Funcionan con cualquier app delante y no piden permisos. Haz clic en el atajo y pulsa la combinación nueva (con ⌘, ⌥ o ⌃); Esc cancela.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Grabador de atajos sencillo: clic, pulsas la combinación y listo.
struct ShortcutRecorder: View {
    let title: String
    @Binding var value: [Int]
    let other: [Int]
    let fallback: Shortcut
    let actions: SettingsActions
    @State private var recording = false
    @State private var monitor: Any?

    var current: Shortcut? { Shortcut(array: value) }

    var warning: String? {
        guard let sc = current else { return nil }
        if value == other { return "Es el mismo que el otro atajo." }
        if sc.clashesWithSystem { return "Ese atajo ya lo usa el Mac; elige otro." }
        return nil
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button { recording ? stop() : start() } label: {
                    Text(recording ? "Pulsa el atajo…" : (current?.display ?? "Sin atajo"))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                Menu {
                    Button("De serie (\(fallback.display))") { stop(); value = fallback.array }
                    Button("Sin atajo") { stop(); value = [] }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let w = warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundColor(.orange)
                }
            }
        }
        .onDisappear { stop() }
    }

    func start() {
        recording = true
        actions.pauseHotKeys(true)   // si no, el atajo actual se dispararía en vez de grabarse
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let mods = Shortcut.carbonModifiers(e.modifierFlags)
            guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return nil }
            value = Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods).array
            stop()
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording { actions.pauseHotKeys(false) }
        recording = false
    }
}
