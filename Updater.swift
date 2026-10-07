// Actualizar con un clic: mira la última Release de GitHub, descarga el zip, sustituye la app y la relanza.
// Es lo único que sale del Mac, y solo si lo pides o tienes activada la comprobación diaria.

import AppKit

let releasesAPI = URL(string: "https://api.github.com/repos/isrart/carita/releases/latest")!

/// «1.10.0» > «1.9.3»: compara número a número.
func isNewer(_ a: String, than b: String) -> Bool {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}

final class Updater: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
    struct Release { let version: String; let zip: URL }

    /// Lo que el actualizador cuenta a la app (bocadillo, menú).
    var onMessage: ((String) -> Void)?
    var onAvailable: ((Release?) -> Void)?
    private(set) var available: Release?
    private(set) var busy = false
    private var interactive = false
    private var apiData = Data()
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Consulta la última Release. `interactive`: lo has pedido tú (dice también «estás al día» y los errores).
    func check(interactive: Bool) {
        guard !busy else { return }
        busy = true
        self.interactive = interactive
        apiData = Data()
        var req = URLRequest(url: releasesAPI, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Carita/\(current)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req).resume()
        if interactive { onMessage?(T("Voy a mirar si hay versión nueva…", "Let me check for a new version…")) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        apiData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task is URLSessionDownloadTask {
            if let error = error { fail(T("No pude descargarla: \(error.localizedDescription)", "I couldn't download it: \(error.localizedDescription)")) }
            return
        }
        busy = false
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200,
              let obj = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String) == "Carita.zip" })?["browser_download_url"] as? String,
              let zipURL = URL(string: zip) else {
            if interactive { onMessage?(T("No pude mirar las actualizaciones (\(error?.localizedDescription ?? "GitHub respondió \(status)")).", "I couldn't check for updates (\(error?.localizedDescription ?? "GitHub answered \(status)")).")) }
            return
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if isNewer(version, than: current) {
            available = Release(version: version, zip: zipURL)
            onAvailable?(available)
            onMessage?(T("¡Hay versión nueva! La \(version). Clic derecho → Actualizar", "There's a new version! \(version). Right-click → Update"))
        } else {
            available = nil
            onAvailable?(nil)
            if interactive { onMessage?(T("Estás al día: tienes la \(current), la última", "You're up to date: \(current) is the latest")) }
        }
    }

    // MARK: instalar

    /// Dónde está la app que se sustituye: la que se está ejecutando (normalmente ~/Applications/Carita.app).
    var appURL: URL { Bundle.main.bundleURL }

    func install() {
        guard let rel = available, !busy else { return }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            onMessage?(T("No puedo escribir en \(appURL.deletingLastPathComponent().path). Muévela a ~/Applications.", "I can't write to \(appURL.deletingLastPathComponent().path). Move me to ~/Applications."))
            return
        }
        busy = true
        onMessage?(T("Descargando la \(rel.version)…", "Downloading \(rel.version)…"))
        // URLSession no marca la descarga en cuarentena: la app nueva abre sin el aviso de Gatekeeper
        session.downloadTask(with: rel.zip).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let rel = available else { return fail(T("Se ha perdido la versión a instalar", "I lost track of the version to install")) }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("carita-update-\(rel.version)")
        try? fm.removeItem(at: work)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("Carita.zip")
            try fm.moveItem(at: location, to: zip)

            // descomprimir con ditto (conserva la firma) y comprobar lo que ha salido
            let (unzipCode, unzipOut) = Scripts.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path], timeout: 60)
            guard unzipCode == 0 else { return fail(T("No pude descomprimirla: \(unzipOut)", "I couldn't unzip it: \(unzipOut)")) }
            let newApp = work.appendingPathComponent("Carita.app")
            let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            // la 1.14 cambió de identidad (com.bajovelo.carita → io.github.isrart.carita): valen las dos
            let ids: Set<String> = ["io.github.isrart.carita", "com.bajovelo.carita"]
            guard let newID = plist?["CFBundleIdentifier"] as? String, ids.contains(newID),
                  plist?["CFBundleShortVersionString"] as? String == rel.version else {
                return fail(T("El zip descargado no es la Carita \(rel.version)", "The downloaded zip isn't Carita \(rel.version)"))
            }
            let (signCode, _) = Scripts.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path], timeout: 30)
            guard signCode == 0 else { return fail(T("La firma de la app descargada no es válida", "The downloaded app's signature isn't valid")) }
            // si esta app va firmada con el certificado propio, la nueva tiene que llevar el mismo
            if let req = ownCertificateRequirement() {
                let (reqCode, _) = Scripts.run("/usr/bin/codesign", ["--verify", "-R=\(req)", newApp.path], timeout: 30)
                guard reqCode == 0 else { return fail(T("La app descargada no está firmada con el certificado de Carita", "The downloaded app isn't signed with Carita's certificate")) }
            }

            // cambiar la vieja por la nueva de una vez (la vieja sigue en memoria hasta el relanzamiento)
            _ = try fm.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
            try? fm.removeItem(at: work)
        } catch {
            return fail(T("No pude instalarla: \(error.localizedDescription)", "I couldn't install it: \(error.localizedDescription)"))
        }
        onMessage?(T("¡Listo! Me reinicio con la \(rel.version)…", "Done! Restarting with \(rel.version)…"))
        Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(relaunch), userInfo: nil, repeats: false)
    }

    /// Abre la app nueva cuando esta haya salido (al arrancar, actualiza ella sola los scripts de ~/.carita).
    @objc func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", appURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// El requisito de firma de esta app si va con certificado (con firma ad hoc no hay nada que comparar).
    func ownCertificateRequirement() -> String? {
        let (code, out) = Scripts.run("/usr/bin/codesign", ["-d", "-r-", Bundle.main.bundlePath], timeout: 10)
        guard code == 0, let line = out.split(separator: "\n").first(where: { $0.contains("designated => ") }),
              line.contains("certificate") else { return nil }
        return String(line.components(separatedBy: "designated => ").last ?? "")
    }

    private func fail(_ text: String) {
        busy = false
        onMessage?(text)
    }
}
