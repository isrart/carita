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

/// Palabras de la ruta del proyecto → forma del bicho (redondita, alubia, gotita, mandarina, pelusita).
struct ShapeRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var palabras: [String]
    var forma: String
    enum CodingKeys: String, CodingKey { case palabras, forma }
}

/// Un cumpleaños: ese día llevan gorro de fiesta y el primer bicho le canta.
struct Cumple: Codable, Hashable, Identifiable {
    var id = UUID()
    var nombre: String
    var dia: Int
    var mes: Int
    enum CodingKeys: String, CodingKey { case nombre, dia, mes }
}

struct Config: Codable, Equatable {
    var nombre = Config.nombreDelMac
    var idioma = "auto"          // «auto» (el del Mac), «es» o «en»
    var packBajovelo = false     // disfraces de Bajovelo (boina, vino, cava): un pack opcional
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
    var forma = "auto"
    var formas = Config.formasDeSerie
    var noMolestarCamara = true
    var noMolestarPantalla = true
    var atajoMostrar = Shortcut.toggleDefault.array   // [] = sin atajo
    var atajoCallar = Shortcut.muteDefault.array
    var atajoHablar = Shortcut.talkDefault.array
    var enviarAlHablar = false   // al soltar el atajo de hablar, pulsar Intro también
    var cumples: [Cumple] = []
    var cumpleCantado = ""      // «2027-03-12 Lucía»: para cantar solo una vez al día
    var buscarActualizaciones = true   // una vez al día, en silencio
    var ultimaComprobacion: Double?
    var oculta = false
    var silenciadaHasta: Double?  // segundos desde 1970

    /// El nombre de pila del usuario del Mac («Israel García» → «Israel»).
    static var nombreDelMac: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    /// Pack Bajovelo: las mismas que RULES de carita.py; los subproyectos antes que lo genérico.
    static let reglasDeSerie = [
        CostumeRule(palabras: ["trivia", "quiz", "preguntas", "denominacion"], disfraz: "vinotrivia"),
        CostumeRule(palabras: ["reel", "insta", "video", "redes", "social"], disfraz: "vinoreels"),
        CostumeRule(palabras: ["recurso", "resource", "guia", "ficha", "descarga"], disfraz: "vinorecursos"),
        CostumeRule(palabras: ["blog", "articulo"], disfraz: "vinoblog"),
        CostumeRule(palabras: ["bajovelo", "vino", "wine", "sommelier"], disfraz: "vino"),
    ]

    /// Las mismas que SHAPE_RULES de carita.py.
    static let formasDeSerie = [
        ShapeRule(palabras: ["claude", "agent", "mcp", "skill", "prompt"], forma: "pelusita"),
        ShapeRule(palabras: ["blog", "reel", "insta", "video", "redes", "social", "articulo"], forma: "mandarina"),
        ShapeRule(palabras: ["app", "api", "swift", "ios", "web", "carita", "code", "dev", "backend", "frontend"], forma: "alubia"),
        ShapeRule(palabras: ["notas", "notes", "apuntes", "scratch", "prueba", "test", "tmp", "sandbox"], forma: "gotita"),
    ]

    enum CodingKeys: String, CodingKey {
        case forma, formas, packBajovelo, idioma
        case nombre, tamano, disfraz, leerRespuestas, avisosVoz, irABuscarte, voz, velocidad, tono
        case descansoMinutos, antifazMinutos, pausaMinutos, disfraces, noMolestarCamara, noMolestarPantalla
        case enviarAlHablar
        case atajoMostrar, atajoCallar, atajoHablar, cumples, cumpleCantado, oculta, silenciadaHasta, buscarActualizaciones, ultimaComprobacion
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
        packBajovelo = v(.packBajovelo, d.packBajovelo)
        idioma = v(.idioma, d.idioma)
        forma = v(.forma, d.forma)
        formas = v(.formas, d.formas)
        noMolestarCamara = v(.noMolestarCamara, d.noMolestarCamara)
        noMolestarPantalla = v(.noMolestarPantalla, d.noMolestarPantalla)
        atajoMostrar = v(.atajoMostrar, d.atajoMostrar)
        atajoCallar = v(.atajoCallar, d.atajoCallar)
        atajoHablar = v(.atajoHablar, d.atajoHablar)
        enviarAlHablar = v(.enviarAlHablar, d.enviarAlHablar)
        oculta = v(.oculta, d.oculta)
        buscarActualizaciones = v(.buscarActualizaciones, d.buscarActualizaciones)
        cumples = v(.cumples, d.cumples)
        cumpleCantado = v(.cumpleCantado, d.cumpleCantado)
        ultimaComprobacion = try? c.decode(Double.self, forKey: .ultimaComprobacion)
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
            if var cfg = try? JSONDecoder().decode(Config.self, from: data) {
                // quien ya usaba Carita antes de los packs (Isra) se queda con lo de Bajovelo
                let keys = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).map { Set($0.keys) } ?? []
                let migrate = !keys.contains("packBajovelo") && keys.contains("disfraces")
                if migrate { cfg.packBajovelo = true }
                c = cfg
                if migrate { save() }   // carita.py también lo lee del archivo
            }
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(store: store, actions: actions))
            w.center()
            window = w
        }
        window?.title = T("Ajustes de Carita", "Carita Settings")   // por si has cambiado de idioma
        NSApp.activate(ignoringOtherApps: true)   // la app es LSUIElement: si no, la ventana sale detrás
        window?.makeKeyAndOrderFront(nil)
    }
}

var shapeNames: [(String, String)] { [
    (T("Redondita", "Round"), "redondita"), (T("Alubia alta", "Tall bean"), "alubia"), (T("Gotita", "Little drop"), "gotita"),
    (T("Mandarina con flor", "Tangerine with a flower"), "mandarina"), (T("Pelusita", "Fluffball"), "pelusita"),
] }

var costumeNames: [(String, String)] { [
    (T("Sin disfraz", "No costume"), "none"), (T("Bajovelo (boina y copa)", "Bajovelo (beret and glass)"), "vino"), (T("Blog (pluma y cuaderno)", "Blog (quill and notebook)"), "vinoblog"),
    (T("Recursos (guía de vino)", "Resources (wine guide)"), "vinorecursos"), (T("Trivia (cartel ?)", "Trivia (? sign)"), "vinotrivia"), (T("Reels (móvil grabando)", "Reels (phone recording)"), "vinoreels"),
] }

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions
    @State private var tab = 0

    // con TabView, en ventanas estrechas macOS esconde las pestañas tras un «»»: barra propia, siempre visible
    static var tabs: [(String, String)] { [("General", "gearshape"), (T("Voz", "Voice"), "speaker.wave.2"),
                                           (T("Descanso", "Breaks"), "cup.and.saucer"), (T("Aspecto", "Look"), "theatermasks"),
                                           (T("Cumpleaños", "Birthdays"), "gift"), (T("No molestar", "Do not disturb"), "moon"),
                                           (T("Atajos", "Shortcuts"), "keyboard")] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(SettingsView.tabs.enumerated()), id: \.offset) { i, t in
                    Button { tab = i } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.1).font(.system(size: 17))
                            Text(t.0).font(.caption)
                        }
                        .frame(width: 80, height: 46)
                        .foregroundColor(tab == i ? .accentColor : .secondary)
                        .background(RoundedRectangle(cornerRadius: 8).fill(tab == i ? Color.accentColor.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            Divider()
            Group {
                switch tab {
                case 1: VoiceTab(store: store, actions: actions)
                case 2: BreakTab(store: store)
                case 3: CostumeTab(store: store)
                case 4: BirthdayTab(store: store)
                case 5: DndTab(store: store, actions: actions)
                case 6: ShortcutTab(store: store, actions: actions)
                default: GeneralTab(store: store, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 560)
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
                TextField(T("Tu nombre", "Your name"), text: $store.c.nombre)
            } footer: {
                Hint(T("Así te llama cuando te necesita o se despide.", "What it calls you when it needs you or says goodbye."))
            }
            Section {
                Picker(T("Idioma", "Language"), selection: $store.c.idioma) {
                    Text(T("El del Mac", "Same as the Mac")).tag("auto")
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }
            }
            Section {
                ValueSlider(title: T("Tamaño", "Size"), value: $store.c.tamano, range: 0.6...1.6, step: 0.05) { "\(Int(($0 * 100).rounded())) %" }
                Toggle(T("Ir a buscarme cuando me necesita", "Come find me when it needs me"), isOn: $store.c.irABuscarte)
            }
            Section {
                LabeledContent(T("Lo que dice", "What it says")) {
                    Button(T("Editar frases…", "Edit lines…")) { actions.editPhrases() }
                }
            } footer: {
                Hint(T("Abre ~/.carita/frases.json (lo crea con las frases de serie si no existe). Cada estado que pongas sustituye a sus frases; con \"+done\" añades en vez de sustituir. Al guardar, la siguiente frase ya es la nueva.", "Opens ~/.carita/frases.json (creates it with the built-in lines if missing). Each state you add replaces its lines; with \"+done\" you add instead of replacing. As soon as you save, the next line is the new one."))
            }
            Section {
                Toggle(T("Buscar actualizaciones una vez al día", "Check for updates once a day"), isOn: $store.c.buscarActualizaciones)
            } footer: {
                Hint(T("Pregunta a GitHub por la última versión (es lo único que sale del Mac). Si hay una nueva, te lo dice en el bocadillo.", "Asks GitHub for the latest version (the only thing that leaves your Mac). If there's a new one, it tells you in the speech bubble."))
            }
            Section {
                Toggle(T("Abrir al iniciar sesión", "Open at login"), isOn: Binding(get: { login }, set: { on in
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

    /// ¿Es una voz del idioma de la app? (en español, solo de España; en inglés, cualquier inglés)
    static func matchesLanguage(_ v: AVSpeechSynthesisVoice) -> Bool {
        appLanguage == "en" ? v.language.hasPrefix("en") : v.language == "es-ES"
    }

    static func voices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(matchesLanguage)
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }
    /// «Mónica (Enhanced)» → «Mónica»: la calidad ya la ponemos nosotros, en español.
    static func displayName(_ v: AVSpeechSynthesisVoice) -> String {
        v.name.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
    }
    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return T("prémium", "premium")
        case .enhanced: return T("mejorada", "enhanced")
        default: return T("básica", "basic")
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(T("Leer mis respuestas en voz alta", "Read my answers out loud"), isOn: $store.c.leerRespuestas)
                Toggle(T("Avisos con voz (¡Hecho!, te necesito…)", "Spoken alerts (Done!, I need you…)"), isOn: $store.c.avisosVoz)
            }
            Section {
                Toggle(T("Enviar directamente al soltar (pulsa Intro por ti)", "Send right away when released (presses Return for you)"), isOn: $store.c.enviarAlHablar)
            } header: {
                Text(T("Cuando le hablas", "When you talk to it"))
            } footer: {
                Hint(T("Desactivado, deja el texto escrito en la terminal para que lo revises y lo envíes tú.", "When off, it leaves the text typed in the terminal so you can check it and send it yourself."))
            }
            Section {
                Picker(T("Voz", "Voice"), selection: $store.c.voz) {
                    Text(T("Automática (la mejor que tengas)", "Automatic (the best one you have)")).tag("")
                    Divider()
                    ForEach(VoiceTab.voices(), id: \.identifier) { v in
                        Text("\(VoiceTab.displayName(v)) · \(VoiceTab.qualityName(v))").tag(v.identifier)
                    }
                }
                ValueSlider(title: T("Velocidad", "Speed"), value: $store.c.velocidad, range: 0.3...0.7) { String(format: "%.2f", $0) }
                ValueSlider(title: T("Tono", "Pitch"), value: $store.c.tono, range: 0.7...1.6) { String(format: "%.2f", $0) }
                HStack {
                    Button(T("Valores de serie", "Defaults")) {
                        store.c.velocidad = Config().velocidad
                        store.c.tono = Config().tono
                    }
                    Spacer()
                    Button { actions.testVoice() } label: { Label(T("Probar", "Try it"), systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
            } footer: {
                Hint(T("¿Suena robótica? Descarga una voz «mejorada» o «prémium»: Ajustes del Sistema → Accesibilidad → Contenido leído → Voz del sistema → Gestionar voces → Español (España).", "Sounds robotic? Download an “Enhanced” or “Premium” voice: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices."))
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
                minutes(T("Pedirte que te estires tras", "Ask you to stretch after"), $store.c.descansoMinutos, 15...240, step: 5)
                minutes(T("Ponerse el antifaz si lo ignoras", "Put on the sleep mask if ignored"), $store.c.antifazMinutos, 1...60, step: 1)
                minutes(T("Pausa que cuenta como descanso", "A pause that counts as a break"), $store.c.pausaMinutos, 1...30, step: 1)
            } footer: {
                Hint(T("Cuenta el tiempo de trabajo seguido con Claude Code. Si paras el rato de la pausa, el contador vuelve a cero.", "Counts continuous work time with Claude Code. If you stop for the length of the pause, it starts again from zero."))
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
                Toggle(T("Pack Bajovelo (boina, vino y cava al desplegar)", "Bajovelo pack (beret, wine and cava on deploys)"), isOn: Binding(
                    get: { store.c.packBajovelo },
                    set: { on in
                        store.c.packBajovelo = on
                        if on && store.c.disfraces.isEmpty { store.c.disfraces = Config.reglasDeSerie }
                    }))
            } footer: {
                Hint(T("Disfraces según el subproyecto: boina granate y, en la mano, una copa, un cuaderno, una guía, un cartel o un móvil. Los deploys se celebran descorchando cava.", "Costumes by subproject: a maroon beret and, in hand, a wine glass, a notebook, a guide, a sign or a phone. Deploys are celebrated by popping cava."))
            }
            if store.c.packBajovelo {
                Section {
                    Picker(T("Disfraz", "Costume"), selection: $store.c.disfraz) {
                        Text(T("Automático (según el proyecto)", "Automatic (by project)")).tag("auto")
                        Divider()
                        ForEach(costumeNames, id: \.1) { Text($0.0).tag($0.1) }
                    }
                }
            }
            Section {
                Picker(T("Forma", "Shape"), selection: $store.c.forma) {
                    Text(T("Automática (según el proyecto)", "Automatic (by project)")).tag("auto")
                    Divider()
                    ForEach(shapeNames, id: \.1) { Text($0.0).tag($0.1) }
                }
                ForEach(Array(store.c.formas.enumerated()), id: \.element.id) { i, _ in
                    ShapeRow(store: store, index: i)
                }
                HStack {
                    Button { store.c.formas.append(ShapeRule(palabras: [], forma: "redondita")) } label: {
                        Label(T("Añadir regla", "Add rule"), systemImage: "plus")
                    }
                    Spacer()
                    Button(T("Valores de serie", "Defaults")) { store.c.formas = Config.formasDeSerie }
                }
            } header: {
                Text(T("Forma del bicho", "Shape of the critter"))
            } footer: {
                Hint(T("Todas son Carita, en naranja. Igual que los disfraces: gana la primera regla con alguna palabra de la carpeta; en el archivo .carita también puedes poner una forma (p. ej., «blog alubia»).", "They're all Carita, in orange. Like costumes: the first rule with a word in the folder wins; you can also put a shape in the .carita file (e.g. “blog alubia”)."))
            }
            if store.c.packBajovelo {
                Section {
                    ForEach(Array(store.c.disfraces.enumerated()), id: \.element.id) { i, rule in
                        CostumeRow(store: store, index: i)
                    }
                    HStack {
                        Button { store.c.disfraces.append(CostumeRule(palabras: [], disfraz: "vino")) } label: {
                            Label(T("Añadir regla", "Add rule"), systemImage: "plus")
                        }
                        Spacer()
                        Button(T("Valores de serie", "Defaults")) { store.c.disfraces = Config.reglasDeSerie }
                    }
                } header: {
                    Text(T("Palabras en la ruta del proyecto", "Words in the project path"))
                } footer: {
                    Hint(T("En automático gana la primera regla con alguna palabra que aparezca en la carpeta. Un archivo .carita en la raíz del proyecto manda sobre todo.", "In automatic mode, the first rule with a word found in the folder wins. A .carita file at the project root overrides everything."))
                }
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
                }), prompt: Text(T("palabras, separadas por comas", "words, separated by commas")))
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

struct ShapeRow: View {
    @ObservedObject var store: ConfigStore
    let index: Int

    var body: some View {
        let rules = store.c.formas
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { index < rules.count ? rules[index].palabras.joined(separator: ", ") : "" },
                set: { text in
                    guard index < store.c.formas.count else { return }
                    store.c.formas[index].palabras = text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                }), prompt: Text(T("palabras, separadas por comas", "words, separated by commas")))
                .labelsHidden()
            Image(systemName: "arrow.right").foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { index < rules.count ? rules[index].forma : "redondita" },
                set: { if index < store.c.formas.count { store.c.formas[index].forma = $0 } })) {
                ForEach(shapeNames, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .frame(width: 180)
            ControlGroup {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(index >= rules.count - 1)
                Button { store.c.formas.remove(at: index) } label: { Image(systemName: "trash") }
            }
            .frame(width: 96)
        }
    }

    func move(_ d: Int) {
        let j = index + d
        guard j >= 0, j < store.c.formas.count else { return }
        store.c.formas.swapAt(index, j)
    }
}

struct BirthdayTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                ForEach($store.c.cumples) { $c in
                    HStack {
                        TextField("", text: $c.nombre, prompt: Text(T("Nombre", "Name"))).labelsHidden()
                        Picker("", selection: $c.dia) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                            .labelsHidden().frame(width: 64)
                        Picker("", selection: $c.mes) {
                            ForEach(1...12, id: \.self) { m in Text(Calendar(identifier: .gregorian).monthSymbols(es: m)).tag(m) }
                        }
                        .labelsHidden().frame(width: 120)
                        Button { store.c.cumples.removeAll { $0.id == c.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { store.c.cumples.append(Cumple(nombre: "", dia: 1, mes: 1)) } label: { Label(T("Añadir cumpleaños", "Add birthday"), systemImage: "plus") }
            } header: {
                Text(T("Cumpleaños", "Birthdays"))
            } footer: {
                Hint(T("Ese día llevan gorro de fiesta y el primer bicho le canta «Cumpleaños feliz» con su nombre (una vez).", "On that day they wear party hats and the first critter sings “Happy birthday” with their name (once)."))
            }
        }
        .formStyle(.grouped)
    }
}

struct DndTab: View {
    @ObservedObject var store: ConfigStore
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle(T("Esconderse al encender la cámara", "Hide when the camera turns on"), isOn: $store.c.noMolestarCamara)
                Toggle(T("Esconderse al compartir pantalla", "Hide when sharing the screen"), isOn: $store.c.noMolestarPantalla)
            } footer: {
                Hint(T("La cámara vale para cualquier videollamada. Compartir pantalla: Zoom, Compartir pantalla del Mac y pantalla duplicada (AirPlay o proyector); Meet o Teams en el navegador sin cámara no se pueden detectar, ni el modo concentración.", "The camera works for any video call. Screen sharing: Zoom, macOS Screen Sharing and mirrored displays (AirPlay or a projector); Meet or Teams in the browser without the camera can't be detected, nor can Focus modes."))
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent(T("Ahora mismo", "Right now"), value: actions.dndStatus())
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
                ShortcutRecorder(title: T("Mostrar u ocultar", "Show or hide"), value: $store.c.atajoMostrar, other: store.c.atajoCallar,
                                 fallback: Shortcut.toggleDefault, actions: actions)
                ShortcutRecorder(title: T("Callarla (y silenciar 1 hora)", "Silence it (and mute for 1 hour)"), value: $store.c.atajoCallar, other: store.c.atajoMostrar,
                                 fallback: Shortcut.muteDefault, actions: actions)
                ShortcutRecorder(title: T("Hablarle (mantenlo pulsado)", "Talk to it (hold it down)"), value: $store.c.atajoHablar, other: store.c.atajoCallar,
                                 fallback: Shortcut.talkDefault, actions: actions)
            } footer: {
                Hint(T("Para hablarle, mantén pulsado su atajo mientras hablas: lo que digas se escribe en la terminal de la sesión que estuvo activa la última, sin pulsar Intro. Funcionan con cualquier app delante. Haz clic en el atajo y pulsa la combinación nueva (con ⌘, ⌥ o ⌃); Esc cancela.", "To talk to it, hold its shortcut while you speak: what you say is typed into the terminal of the most recently active session. They work with any app in front and need no permissions. Click a shortcut and press the new combination (with ⌘, ⌥ or ⌃); Esc cancels."))
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
        if value == other { return T("Es el mismo que el otro atajo.", "It's the same as the other shortcut.") }
        if sc.clashesWithSystem { return T("Ese atajo ya lo usa el Mac; elige otro.", "macOS already uses that shortcut; pick another one.") }
        return nil
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button { recording ? stop() : start() } label: {
                    Text(recording ? T("Pulsa el atajo…", "Press the shortcut…") : (current?.display ?? T("Sin atajo", "No shortcut")))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                Menu {
                    Button("De serie (\(fallback.display))") { stop(); value = fallback.array }
                    Button(T("Sin atajo", "No shortcut")) { stop(); value = [] }
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

extension Calendar {
    /// «enero», «febrero»… en español.
    func monthSymbols(es m: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: appLanguage == "en" ? "en_US" : "es_ES")
        return f.standaloneMonthSymbols[m - 1]
    }
}
