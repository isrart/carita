// Estadísticas locales: ~/.carita/historial.jsonl (lo escriben carita.py y la app) y su ventana.
// Nada sale del Mac.

import AppKit
import SwiftUI
import Charts

let historyPath = (stateDir as NSString).appendingPathComponent("historial.jsonl")
let historySummaryPath = (stateDir as NSString).appendingPathComponent("historial-resumen.json")

struct HistoryEvent {
    let t: Date
    let ev: String          // prompt, done, shipped, deploy_fallido, stretch, mask
    let proyecto: String?
    let disfraz: String?
}

enum History {
    static let maxBytes = 2_000_000      // a partir de aquí se resume lo antiguo
    static let keepDays = 60.0           // lo que se queda línea a línea
    static let idleGap: TimeInterval = 300        // huecos de más de 5 min no cuentan como trabajo
    static let maxTurn: TimeInterval = 2 * 3600   // un prompt sin «done» no cuenta más de 2 h

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_ES")
        c.firstWeekday = 2   // la semana empieza el lunes
        return c
    }

    /// Lo que apunta la propia app (descansos pedidos e ignorados).
    static func append(_ ev: String) {
        let line: [String: Any] = ["t": (Date().timeIntervalSince1970 * 10).rounded() / 10, "ev": ev]
        guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
        data.append(10)
        if let h = FileHandle(forWritingAtPath: historyPath) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            FileManager.default.createFile(atPath: historyPath, contents: data)
        }
    }

    static func parse(_ line: Substring) -> HistoryEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let t = obj["t"] as? Double, let ev = obj["ev"] as? String else { return nil }
        return HistoryEvent(t: Date(timeIntervalSince1970: t), ev: ev,
                            proyecto: obj["proyecto"] as? String, disfraz: obj["disfraz"] as? String)
    }

    static func load(since: Date) -> [HistoryEvent] {
        guard let text = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap(parse).filter { $0.t >= since }.sorted { $0.t < $1.t }
    }

    /// Segundos de trabajo por proyecto. Un turno prompt → respuesta cuenta entero (Claude trabajando);
    /// entre otros eventos, solo los huecos de menos de 5 min (tú leyendo o escribiendo).
    static func workSeconds(_ events: [HistoryEvent]) -> [String: TimeInterval] {
        var out: [String: TimeInterval] = [:]
        let byProject = Dictionary(grouping: events.filter { $0.proyecto != nil }) { $0.proyecto! }
        for (p, list) in byProject {
            var total: TimeInterval = 0
            for (a, b) in zip(list, list.dropFirst()) {
                let gap = b.t.timeIntervalSince(a.t)
                if a.ev == "prompt" { total += min(gap, maxTurn) } else if gap < idleGap { total += gap }
            }
            out[p] = total
        }
        return out
    }

    /// Si el historial pasa de unos MB, lo de hace más de 60 días se resume por días en
    /// historial-resumen.json y el archivo se queda solo con lo reciente.
    static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: historyPath))?[.size] as? Int, size > maxBytes,
              let original = fm.contents(atPath: historyPath),
              let text = String(data: original, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-keepDays * 86400)
        let lines = text.split(separator: "\n")
        let old = lines.compactMap(parse).filter { $0.t < cutoff }
        let recent = lines.filter { (parse($0)?.t ?? .distantPast) >= cutoff }

        // resumen por día: {"2026-08-01": {"proyectos": {"blog": {"segundos": 3600, "tareas": 4}}, "deploys": 1, …}}
        var summary = (fm.contents(atPath: historySummaryPath)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: [String: Any]]) ?? [:]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let cal = calendar
        for (day, evs) in Dictionary(grouping: old, by: { cal.startOfDay(for: $0.t) }) {
            let key = f.string(from: day)
            var d = summary[key] ?? [:]
            var projects = d["proyectos"] as? [String: [String: Double]] ?? [:]
            for (p, secs) in workSeconds(evs) { projects[p, default: [:]]["segundos", default: 0] += secs }
            for e in evs where e.ev == "done" { projects[e.proyecto ?? "?", default: [:]]["tareas", default: 0] += 1 }
            d["proyectos"] = projects
            for (ev, name) in [("shipped", "deploys"), ("deploy_fallido", "fallidos"), ("stretch", "descansos"), ("mask", "ignorados")] {
                d[name] = (d[name] as? Int ?? 0) + evs.filter { $0.ev == ev }.count
            }
            summary[key] = d
        }
        guard let sumData = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? sumData.write(to: URL(fileURLWithPath: historySummaryPath), options: .atomic)

        var newData = Data((recent.joined(separator: "\n") + (recent.isEmpty ? "" : "\n")).utf8)
        // si un hook ha escrito mientras tanto, no perder sus líneas
        if let now = fm.contents(atPath: historyPath), now.count > original.count {
            newData.append(now.suffix(from: original.count))
        }
        try? newData.write(to: URL(fileURLWithPath: historyPath), options: .atomic)
    }
}

// MARK: ventana

final class StatsModel: ObservableObject {
    enum Period: String, CaseIterable, Identifiable {
        case semana = "Esta semana", mes = "Este mes"
        var id: String { rawValue }
    }
    struct ProjectHours: Identifiable { let id: String; let hours: Double; let bajovelo: Bool }
    struct DayCount: Identifiable { let id = UUID(); let day: Date; let kind: String; let count: Int }

    @Published var period: Period = .semana { didSet { reload() } }
    @Published var projects: [ProjectHours] = []
    @Published var tasks: [DayCount] = []
    @Published var deploys: [DayCount] = []
    @Published var shipped = 0
    @Published var failed = 0
    @Published var breaksAsked = 0
    @Published var breaksIgnored = 0
    @Published var empty = true
    @Published var days: [Date] = []

    func reload() {
        let cal = History.calendar
        let now = Date()
        let start = cal.dateInterval(of: period == .semana ? .weekOfYear : .month, for: now)?.start ?? cal.startOfDay(for: now)
        let events = History.load(since: start)
        empty = events.isEmpty

        var allDays: [Date] = []
        var d = start
        let end = cal.dateInterval(of: period == .semana ? .weekOfYear : .month, for: now)?.end ?? now
        while d < end { allDays.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        days = allDays

        let costumes = Dictionary(events.compactMap { e in e.proyecto.map { ($0, e.disfraz ?? "") } }) { _, b in b }
        projects = History.workSeconds(events)
            .filter { $0.value >= 60 }
            .map { ProjectHours(id: $0.key, hours: $0.value / 3600, bajovelo: (costumes[$0.key] ?? "").hasPrefix("vino")) }
            .sorted { $0.hours > $1.hours }

        func perDay(_ ev: String, _ kind: String) -> [DayCount] {
            let counts = Dictionary(grouping: events.filter { $0.ev == ev }) { cal.startOfDay(for: $0.t) }.mapValues(\.count)
            return allDays.map { DayCount(day: $0, kind: kind, count: counts[$0] ?? 0) }
        }
        tasks = perDay("done", "Tareas")
        deploys = perDay("shipped", "En producción") + perDay("deploy_fallido", "Fallidos")
        shipped = events.filter { $0.ev == "shipped" }.count
        failed = events.filter { $0.ev == "deploy_fallido" }.count
        breaksAsked = events.filter { $0.ev == "stretch" }.count
        breaksIgnored = events.filter { $0.ev == "mask" }.count
    }
}

let clay = Color(red: 0.886, green: 0.478, blue: 0.322)

struct StatsView: View {
    @ObservedObject var model: StatsModel

    func hoursText(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return m < 60 ? "\(m) min" : String(format: "%d h %02d", m / 60, m % 60)
    }

    var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: model.period == .semana ? 1 : 7)) { _ in
            AxisGridLine()
            AxisValueLabel(format: model.period == .semana ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated),
                           centered: model.period == .semana)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Periodo", selection: $model.period) {
                    ForEach(StatsModel.Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                if model.empty { Hint("Aún no hay datos de este periodo: se apuntan a partir de ahora, cada vez que trabajas con Claude Code.") }
            }

            Section("Horas por proyecto") {
                if model.projects.isEmpty {
                    Text("Nada todavía").foregroundColor(.secondary)
                } else {
                    Chart(model.projects) { p in
                        BarMark(x: .value("Horas", p.hours), y: .value("Proyecto", p.id))
                            .foregroundStyle(p.bajovelo ? clay : Color.secondary.opacity(0.6))
                            .annotation(position: .trailing) { Text(hoursText(p.hours)).font(.caption).foregroundColor(.secondary) }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(max(1, model.projects.count)) * 28 + 8)
                    Hint("En color, los proyectos de Bajovelo. Cuenta cada pregunta hasta su respuesta y los ratos sin pausas de más de 5 minutos.")
                }
            }

            Section("Tareas terminadas") {
                Chart(model.tasks) { d in
                    BarMark(x: .value("Día", d.day, unit: .day), y: .value("Tareas", d.count)).foregroundStyle(clay)
                }
                .chartXAxis { xAxis }
                .frame(height: 130)
            }

            Section("Deploys") {
                LabeledContent("En producción", value: "\(model.shipped)")
                LabeledContent("Fallidos", value: "\(model.failed)")
                if model.shipped + model.failed > 0 {
                    Chart(model.deploys) { d in
                        BarMark(x: .value("Día", d.day, unit: .day), y: .value("Deploys", d.count))
                            .foregroundStyle(by: .value("Resultado", d.kind))
                    }
                    .chartForegroundStyleScale(["En producción": Color.green, "Fallidos": Color.red])
                    .chartXAxis { xAxis }
                    .frame(height: 110)
                }
            }

            Section("Descansos") {
                LabeledContent("Te pidió que te estiraras", value: "\(model.breaksAsked)")
                LabeledContent("Lo ignoraste (antifaz)", value: "\(model.breaksIgnored)")
            }
        }
        .formStyle(.grouped)
        .environment(\.locale, Locale(identifier: "es_ES"))
        .frame(width: 560, height: 620)
    }
}

final class StatsWindow {
    private var window: NSWindow?
    private let model = StatsModel()

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Estadísticas de Carita"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: StatsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
