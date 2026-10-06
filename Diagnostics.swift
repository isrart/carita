// Diagnóstico «¿por qué no reacciona?»: semáforos con lo que puede fallar y botones para arreglarlo.

import AppKit
import SwiftUI

let hookPath = (stateDir as NSString).appendingPathComponent("hook.sh")
let helperPath = (stateDir as NSString).appendingPathComponent("carita.py")
let python = "/usr/bin/python3"

/// Los scripts de los hooks que viajan dentro de la app y se copian a ~/.carita.
enum Scripts {
    static func bundled(_ name: String) -> String? { Bundle.main.path(forResource: name, ofType: nil) }

    /// La versión que llevan dentro: `# versión: X` en hook.sh, `VERSION = "X"` en carita.py.
    static func version(at path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(20) {
            if line.hasPrefix("# versión: ") { return String(line.dropFirst("# versión: ".count)) }
            if line.hasPrefix("VERSION = \"") { return line.split(separator: "\"").dropFirst().first.map(String.init) }
        }
        return nil
    }

    /// ¿Son los de ~/.carita idénticos a los de la app?
    static func upToDate() -> Bool {
        [("hook.sh", hookPath), ("carita.py", helperPath)].allSatisfy { name, dest in
            guard let src = bundled(name) else { return true }
            return FileManager.default.contents(atPath: src) == FileManager.default.contents(atPath: dest)
        }
    }

    /// Copia hook.sh y carita.py de la app a ~/.carita (de forma atómica: un hook puede estar ejecutándose).
    @discardableResult
    static func copyToHome() -> Bool {
        var ok = true
        for (name, dest) in [("hook.sh", hookPath), ("carita.py", helperPath)] {
            guard let src = bundled(name), let data = FileManager.default.contents(atPath: src) else { ok = false; continue }
            let tmp = dest + ".nuevo"
            do {
                try data.write(to: URL(fileURLWithPath: tmp))
                chmod(tmp, name == "hook.sh" ? 0o755 : 0o644)
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: dest), withItemAt: URL(fileURLWithPath: tmp))
            } catch {
                ok = rename(tmp, dest) == 0 && ok
            }
        }
        return ok
    }

    /// Ejecuta un programa y devuelve (código de salida, salida). Con límite de tiempo.
    static func run(_ exe: String, _ args: [String], input: String? = nil, timeout: TimeInterval = 5) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        // sin esto, hook.sh apuntaría a Carita como «tu terminal»
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "__CFBundleIdentifier")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let inPipe = Pipe()
        p.standardInput = inPipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        if let input = input { inPipe.fileHandleForWriting.write(input.data(using: .utf8)!) }
        try? inPipe.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return (-2, "tardó demasiado") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Reinstala: copia los scripts y vuelve a poner los hooks en ~/.claude/settings.json.
    static func reinstallHooks() -> (Bool, String) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        guard copyToHome() else { return (false, "No pude copiar los scripts a ~/.carita") }
        guard let hooksPy = bundled("hooks.py") else { return (false, "Falta hooks.py dentro de la app") }
        let (code, out) = run(python, [hooksPy, "install"])
        return code == 0 ? (true, "Hooks reinstalados. Abre una sesión nueva de Claude Code.") : (false, "hooks.py falló: \(out)")
    }
}

/// Un semáforo del diagnóstico.
struct Check: Identifiable {
    enum Level { case ok, warn, bad }
    let id: String
    let title: String
    let detail: String
    let level: Level
}

/// Lo que el diagnóstico necesita saber de la app.
struct DiagnosticsInfo {
    var appVersion: String
    var voiceName: () -> String
    var lastArrival: () -> (state: String, at: Date)?
}

final class DiagnosticsModel: NSObject, ObservableObject {
    @Published var checks: [Check] = []
    @Published var message: (text: String, ok: Bool)?
    @Published var busy = false
    let info: DiagnosticsInfo
    private var testStarted: Date?
    private var refreshTimer: Timer?
    private var hooksStatus: [String: Any] = [:]

    init(info: DiagnosticsInfo) {
        self.info = info
        super.init()
    }

    func start() {
        refreshHooks()
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshHooks() {
        guard let hooksPy = Scripts.bundled("hooks.py") else { hooksStatus = [:]; return }
        let (code, out) = Scripts.run(python, [hooksPy, "status"])
        hooksStatus = code == 0 ? ((try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]) : [:]
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "hace \(s) s" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 86400 { return "hace \(s / 3600) h" }
        return "hace \(s / 86400) días"
    }

    @objc func refresh() {
        var list: [Check] = []
        let fm = FileManager.default

        // 1. último aviso de Claude Code
        if let attrs = try? fm.attributesOfItem(atPath: statePath), let m = attrs[.modificationDate] as? Date {
            let state = ((try? String(contentsOfFile: statePath, encoding: .utf8)) ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
            let age = Date().timeIntervalSince(m)
            list.append(Check(id: "state", title: "Último aviso de Claude Code",
                              detail: "«\(state)» \(DiagnosticsModel.ago(m))",
                              level: age < 3600 ? .ok : .warn))
        } else {
            list.append(Check(id: "state", title: "Último aviso de Claude Code",
                              detail: "Nunca ha llegado ninguno. ¿Están los hooks instalados?", level: .bad))
        }

        // 2. hooks en settings.json
        if let expected = hooksStatus["esperados"] as? Int, let present = hooksStatus["instalados"] as? Int {
            let missing = (hooksStatus["faltan"] as? [String]) ?? []
            let readable = (hooksStatus["settings_legible"] as? Bool) ?? true
            let level: Check.Level = !readable ? .bad : missing.isEmpty ? .ok : (present == 0 ? .bad : .warn)
            let detail = !readable ? "~/.claude/settings.json no es JSON válido"
                : missing.isEmpty ? "\(present) de \(expected) en ~/.claude/settings.json"
                : "\(present) de \(expected); faltan: " + missing.prefix(4).joined(separator: ", ") + (missing.count > 4 ? "…" : "")
            list.append(Check(id: "hooks", title: "Hooks instalados", detail: detail, level: level))
        } else {
            list.append(Check(id: "hooks", title: "Hooks instalados", detail: "No pude comprobarlo (hace falta python3)", level: .bad))
        }

        // 3. hook.sh
        if !fm.fileExists(atPath: hookPath) {
            list.append(Check(id: "hook", title: "hook.sh", detail: "No está en ~/.carita", level: .bad))
        } else if !fm.isExecutableFile(atPath: hookPath) {
            list.append(Check(id: "hook", title: "hook.sh", detail: "Existe pero no es ejecutable", level: .bad))
        } else {
            list.append(Check(id: "hook", title: "hook.sh", detail: "En ~/.carita y ejecutable", level: .ok))
        }

        // 4. python3
        let py = fm.isExecutableFile(atPath: python)
        list.append(Check(id: "python", title: "python3", detail: py ? python : "No está; instala las Command Line Tools (xcode-select --install)",
                          level: py ? .ok : .bad))

        // 5. versión de los scripts
        let v = Scripts.version(at: helperPath) ?? "?"
        let same = Scripts.upToDate()
        list.append(Check(id: "version", title: "Versión de los scripts",
                          detail: same ? "\(v), igual que la app" : "~/.carita tiene la \(v) y la app es la \(info.appVersion)",
                          level: same ? .ok : .warn))

        // 6. terminal y voz
        let term = ((try? String(contentsOfFile: termPath, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let termName = term.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: term)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? term
        list.append(Check(id: "term", title: "Terminal detectada", detail: termName ?? "Aún ninguna (se detecta al empezar una sesión)",
                          level: termName == nil ? .warn : .ok))
        list.append(Check(id: "voice", title: "Voz", detail: info.voiceName(), level: .ok))

        checks = list

        // prueba en curso: ¿ha llegado el estado?
        if let t = testStarted {
            if let a = info.lastArrival(), a.at >= t {
                testStarted = nil
                busy = false
                message = ("¡Llega! Carita ha recibido «\(a.state)» en \(Int(a.at.timeIntervalSince(t) * 1000)) ms.", true)
            } else if Date().timeIntervalSince(t) > 4 {
                testStarted = nil
                busy = false
                message = ("No ha llegado nada en 4 s. Prueba «Reinstalar hooks».", false)
            }
        }
    }

    func reinstall() {
        let (ok, text) = Scripts.reinstallHooks()
        message = (text, ok)
        refreshHooks()
        refresh()
    }

    /// Ejecuta hook.sh como lo haría Claude Code y mira si la app se entera.
    func test() {
        guard FileManager.default.isExecutableFile(atPath: hookPath) else {
            message = ("No hay hook.sh que probar. Prueba «Reinstalar hooks».", false)
            return
        }
        busy = true
        message = nil
        testStarted = Date()
        _ = Scripts.run(hookPath, ["hello"], input: "{}")
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(testTick), userInfo: nil, repeats: true)
    }

    @objc func testTick() {
        refresh()
        if testStarted == nil { start() }
    }

    func report() -> String {
        let icon: (Check.Level) -> String = { $0 == .ok ? "✅" : $0 == .warn ? "🟠" : "🔴" }
        var lines = ["Diagnóstico de Carita \(info.appVersion) — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        lines += checks.map { "\(icon($0.level)) \($0.title): \($0.detail)" }
        if let m = message { lines.append("Último resultado: \(m.text)") }
        return lines.joined(separator: "\n")
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
        message = ("Informe copiado. Pégamelo donde quieras.", true)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel

    func color(_ l: Check.Level) -> Color { l == .ok ? .green : l == .warn ? .orange : .red }

    var body: some View {
        Form {
            Section {
                ForEach(model.checks) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(color(c.level)).frame(width: 10, height: 10)
                        Text(c.title)
                        Spacer()
                        Text(c.detail).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
            Section {
                HStack {
                    Button { model.reinstall() } label: { Label("Reinstalar hooks", systemImage: "wrench.and.screwdriver") }
                    Button { model.test() } label: { Label("Probar", systemImage: "bolt") }.disabled(model.busy)
                    Spacer()
                    Button { model.copyReport() } label: { Label("Copiar informe", systemImage: "doc.on.doc") }
                }
                if let m = model.message {
                    Label(m.text, systemImage: m.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(m.ok ? .green : .orange)
                }
            } footer: {
                Hint("«Probar» ejecuta hook.sh como lo haría Claude Code y comprueba que Carita se entera. Tras reinstalar, las sesiones de Claude Code que ya estaban abiertas no lo notan: abre una nueva.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 470)
    }
}

final class DiagnosticsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: DiagnosticsModel?

    func show(info: DiagnosticsInfo) {
        if window == nil {
            let m = DiagnosticsModel(info: info)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Diagnóstico de Carita"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentViewController = NSHostingController(rootView: DiagnosticsView(model: m))
            w.center()
            window = w
            model = m
        }
        model?.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model?.stop() }
}
