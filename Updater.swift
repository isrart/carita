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
        if interactive { onMessage?("Voy a mirar si hay versión nueva…") }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        apiData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task is URLSessionDownloadTask {
            if let error = error { fail("No pude descargarla: \(error.localizedDescription)") }
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
            if interactive { onMessage?("No pude mirar las actualizaciones (\(error?.localizedDescription ?? "GitHub respondió \(status)")).") }
            return
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if isNewer(version, than: current) {
            available = Release(version: version, zip: zipURL)
            onAvailable?(available)
            onMessage?("¡Hay versión nueva! La \(version). Clic derecho → Actualizar")
        } else {
            available = nil
            onAvailable?(nil)
            if interactive { onMessage?("Estás al día: tienes la \(current), la última") }
        }
    }

    // MARK: instalar

    /// Dónde está la app que se sustituye: la que se está ejecutando (normalmente ~/Applications/Carita.app).
    var appURL: URL { Bundle.main.bundleURL }

    func install() {
        guard let rel = available, !busy else { return }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            onMessage?("No puedo escribir en \(appURL.deletingLastPathComponent().path). Muévela a ~/Applications.")
            return
        }
        busy = true
        onMessage?("Descargando la \(rel.version)…")
        // URLSession no marca la descarga en cuarentena: la app nueva abre sin el aviso de Gatekeeper
        session.downloadTask(with: rel.zip).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let rel = available else { return fail("Se ha perdido la versión a instalar") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("carita-update-\(rel.version)")
        try? fm.removeItem(at: work)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("Carita.zip")
            try fm.moveItem(at: location, to: zip)

            // descomprimir con ditto (conserva la firma) y comprobar lo que ha salido
            let (unzipCode, unzipOut) = Scripts.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path], timeout: 60)
            guard unzipCode == 0 else { return fail("No pude descomprimirla: \(unzipOut)") }
            let newApp = work.appendingPathComponent("Carita.app")
            let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  plist?["CFBundleShortVersionString"] as? String == rel.version else {
                return fail("El zip descargado no es la Carita \(rel.version)")
            }
            let (signCode, _) = Scripts.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path], timeout: 30)
            guard signCode == 0 else { return fail("La firma de la app descargada no es válida") }

            // cambiar la vieja por la nueva de una vez (la vieja sigue en memoria hasta el relanzamiento)
            _ = try fm.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
            try? fm.removeItem(at: work)
        } catch {
            return fail("No pude instalarla: \(error.localizedDescription)")
        }
        onMessage?("¡Listo! Me reinicio con la \(rel.version)…")
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

    private func fail(_ text: String) {
        busy = false
        onMessage?(text)
    }
}
