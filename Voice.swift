// Hablarle a Carita: mantienes un atajo, escucha (reconocimiento en español, en el propio Mac)
// y deja lo que has dicho escrito en la terminal de esa sesión, sin pulsar Intro.

import AppKit
import AVFoundation
import Speech
import ApplicationServices
import Carbon.HIToolbox

/// Micrófono + reconocimiento de voz. Va contando lo que entiende y, al soltar, da el texto final.
final class Listener: NSObject {
    var onText: ((String) -> Void)?       // lo que va entendiendo
    var onDone: ((String) -> Void)?       // el texto final (puede ir vacío)
    var onProblem: ((String) -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishTimer: Timer?
    private(set) var held = false          // el atajo sigue pulsado
    private var running = false
    private var text = ""

    func start() {
        held = true
        text = ""
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            checkMicrophone()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                self?.performSelector(onMainThread: #selector(Listener.permissionsChanged), with: nil, waitUntilDone: false)
            }
        default:
            fail(T("No tengo permiso para entenderte: Ajustes del Sistema → Privacidad y seguridad → Reconocimiento de voz → Carita", "I'm not allowed to understand you: System Settings → Privacy & Security → Speech Recognition → Carita"))
        }
    }

    @objc func permissionsChanged() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return fail(T("Sin permiso de reconocimiento de voz no te puedo entender", "Without speech recognition permission I can't understand you"))
        }
        if held { checkMicrophone() } else { onProblem?(T("¡Gracias! Ya puedes hablarme: mantén el atajo y habla", "Thanks! You can talk to me now: hold the shortcut and speak")) }
    }

    private func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.performSelector(onMainThread: #selector(Listener.microphoneChanged), with: nil, waitUntilDone: false)
            }
        default:
            fail(T("No tengo permiso para el micrófono: Ajustes del Sistema → Privacidad y seguridad → Micrófono → Carita", "I'm not allowed to use the microphone: System Settings → Privacy & Security → Microphone → Carita"))
        }
    }

    @objc func microphoneChanged() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            return fail(T("Sin micrófono no te oigo", "I can't hear you without the microphone"))
        }
        if held { begin() } else { onProblem?(T("¡Gracias! Ya puedes hablarme: mantén el atajo y habla", "Thanks! You can talk to me now: hold the shortcut and speak")) }
    }

    private func begin() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: appLanguage == "en" ? "en-US" : "es-ES"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            return fail(T("El reconocimiento de voz en español no está disponible ahora mismo", "English speech recognition isn't available right now"))
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // nada sale del Mac
        request = req
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return fail(T("No puedo usar el micrófono: \(error.localizedDescription)", "I can't use the microphone: \(error.localizedDescription)"))
        }
        running = true
        // el reconocedor llama en la cola principal (su `queue` por defecto)
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let r = result {
                self.text = r.bestTranscription.formattedString
                self.onText?(self.text)
                if r.isFinal { self.finish() }
            } else if error != nil {
                self.finish()
            }
        }
    }

    /// Has soltado el atajo: deja de escuchar y espera (poco) al texto final.
    func stop() {
        held = false
        guard running else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        finishTimer?.invalidate()
        finishTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(finish), userInfo: nil, repeats: false)
    }

    @objc private func finish() {
        guard running else { return }
        running = false
        finishTimer?.invalidate()
        finishTimer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        onDone?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func fail(_ message: String) {
        held = false
        running = false
        onProblem?(message)
    }
}

/// Lleva el texto a la terminal de una sesión: la trae al frente y lo pega, sin Intro.
final class Typist: NSObject {
    var onMessage: ((String) -> Void)?
    private var pending = ""
    private var send = false
    private var savedClipboard: String?

    /// `term`: app de la terminal (bundle id); `tty`: la pestaña (p. ej., «ttys002»), si se sabe.
    /// `send`: pulsar Intro después de pegar.
    func type(_ text: String, term: String?, tty: String, send: Bool) {
        pending = text
        self.send = send
        bringToFront(term: term, tty: tty)
        // un momento para que la ventana llegue al frente antes de pegar
        Timer.scheduledTimer(timeInterval: 0.4, target: self, selector: #selector(paste), userInfo: nil, repeats: false)
    }

    private func bringToFront(term: String?, tty: String) {
        if term == "com.apple.Terminal" && !tty.isEmpty {
            // Terminal deja elegir la pestaña por su tty (pide el permiso de Automatización una vez)
            let src = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "/dev/\(tty)" then
                            set selected of t to true
                            set index of w to 1
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            if err == nil { return }
            debugLog("no pude elegir la pestaña de Terminal: \(err ?? [:])")
        }
        if let id = term, let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        }
    }

    @objc private func paste() {
        let pb = NSPasteboard.general
        savedClipboard = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(pending, forType: .string)

        // pegar como si fuera tu teclado necesita el permiso de Accesibilidad
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            savedClipboard = nil   // el texto se queda en el portapapeles para que lo pegues tú
            onMessage?(T("Te lo dejo copiado: pégalo con ⌘V. Si me das permiso de Accesibilidad, lo escribo yo", "It's on your clipboard: paste it with ⌘V. Give me Accessibility permission and I'll type it myself"))
            return
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        if send {
            // un respiro para que la terminal reciba el pegado antes del Intro
            Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(pressReturn), userInfo: nil, repeats: false)
            onMessage?(T("¡Enviado!", "Sent!"))
        } else {
            onMessage?(T("Escrito. Revísalo y dale a Intro", "Typed. Check it and press Return"))
        }
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(restoreClipboard), userInfo: nil, repeats: false)
    }

    @objc private func pressReturn() {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Te devuelve lo que tenías copiado antes.
    @objc private func restoreClipboard() {
        guard let old = savedClipboard else { return }
        savedClipboard = nil
        let pb = NSPasteboard.general
        guard pb.string(forType: .string) == pending else { return }   // si has copiado otra cosa, no se toca
        pb.clearContents()
        pb.setString(old, forType: .string)
    }
}
