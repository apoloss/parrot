import ApplicationServices
import ArgumentParser
import AVFoundation
import Darwin
import Foundation

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Walk through first-run permission setup."
    )

    func run() throws {
        print("parrot setup")
        print("============")
        print()
        print("Parrot needs two permissions:")
        print("  1. Accessibility — to detect the Fn key globally and inject text at the cursor.")
        print("  2. Microphone — to record audio while Fn is held (or toggled on).")
        print()
        print("These attach to your terminal app (Terminal/iTerm/Ghostty/etc.), not parrot itself.")
        print()

        try waitForAccessibility()
        print()
        try waitForMicrophone()
        print()
        try configureModelAndLanguage()
        print()
        print("✓ all set. Run `parrot` to start the daemon.")
        print("  change later with `parrot config set model …` / `parrot config set language …`")
    }

    private func waitForAccessibility() throws {
        if AXIsProcessTrusted() {
            print("✓ accessibility already granted")
            return
        }

        print("→ opening accessibility prompt...")
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        print()
        print("  1. Toggle your terminal on in the Accessibility list.")
        print("  2. Re-run `parrot setup` — macOS only picks up the grant on a fresh process.")
        throw ExitCode(0)
    }

    private func waitForMicrophone() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            print("✓ microphone already granted")
            return
        case .denied, .restricted:
            print("✗ microphone is denied — macOS won't re-prompt once denied.")
            print("  opening Settings → Privacy & Security → Microphone...")
            openSettings("Privacy_Microphone")
            print("  enable your terminal, then re-run `parrot setup`.")
            throw ExitCode(1)
        case .notDetermined:
            print("→ requesting microphone access...")
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                granted = ok
                semaphore.signal()
            }
            semaphore.wait()
            if granted {
                print("  ✓ microphone granted")
            } else {
                print("  ✗ microphone denied")
                throw ExitCode(1)
            }
        @unknown default:
            print("? microphone in unknown state")
        }
    }

    private func openSettings(_ pane: String) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [url]
        try? task.run()
    }

    private func configureModelAndLanguage() throws {
        if ConfigStore.exists {
            let config = ConfigStore.load()
            print("✓ config already set")
            print("  model:    \(config.resolvedModelID)")
            print("  language: \(config.resolvedLanguage)")
            print("  file:     \(ConfigStore.url.path)")
            return
        }

        print("Model and language")
        print("------------------")
        print("Press enter to keep the default. Change later with `parrot config`.")
        print()

        let models = ModelRegistry.shared
        for (i, m) in models.enumerated() {
            let mark = m.recommended ? "★ " : "  "
            let langs = m.languages.contains("multi") ? "multilingual" : "English only"
            let size = String(format: "%4d MB", m.sizeMB)
            print("  \(i + 1)) \(mark)\(m.id.padding(toLength: 26, withPad: " ", startingAt: 0)) \(size)  \(langs)")
        }

        let defaultIndex = (models.firstIndex(where: { $0.recommended }) ?? 0) + 1
        var chosenModel: TranscriptionModel?
        while chosenModel == nil {
            let raw = TerminalPrompt.ask("Model", default: String(defaultIndex))
            if let idx = Int(raw), models.indices.contains(idx - 1) {
                chosenModel = models[idx - 1]
            } else if let m = ModelRegistry.find(raw) {
                chosenModel = m
            } else {
                print("  unknown model. enter 1–\(models.count) or a model id.")
                if !TerminalPrompt.isInteractive { throw ExitCode(1) }
            }
        }
        var model = chosenModel!

        print()
        print("Language (ISO code). Common:")
        for (code, name) in LanguageCode.common {
            print("  \(code)  \(name)")
        }

        var language = ParrotConfig.defaultLanguage
        while true {
            let raw = TerminalPrompt.ask("Language", default: ParrotConfig.defaultLanguage)
            if let code = LanguageCode.resolve(raw) {
                language = code
                break
            }
            print("  unknown language. use an ISO code (en, es, pt) or a name (english, spanish).")
            if !TerminalPrompt.isInteractive { throw ExitCode(1) }
        }

        if !model.supports(language: language) {
            if let multi = ConfigResolver.firstMultilingualModel() {
                print()
                print("  \(model.id) is English-only.")
                let switchTo = TerminalPrompt.ask(
                    "Switch to \(multi.id) for \(language)?",
                    default: "Y"
                )
                if switchTo.lowercased().hasPrefix("n") {
                    print("  keeping language en")
                    language = "en"
                } else {
                    model = multi
                }
            } else {
                throw ValidationError(
                    ConfigValidationError.languageNotSupported(language: language, model: model.id).description
                )
            }
        }

        var config = ParrotConfig()
        config.model = model.id
        config.language = language
        try ConfigStore.save(config)
        print()
        print("✓ wrote \(ConfigStore.url.path)")
        print("  model:    \(model.id)")
        print("  language: \(language)")

        print()
        try warmup(model)
    }

    private func warmup(_ model: TranscriptionModel) throws {
        print("→ downloading/loading \(model.id)…")
        let transcriber = WhisperKitTranscriber(model: model, language: "en")
        let sem = DispatchSemaphore(value: 0)
        var capturedError: Error?
        Task.detached {
            do { try await transcriber.warmUp() } catch { capturedError = error }
            sem.signal()
        }
        sem.wait()
        if let capturedError {
            print("  ! warmup failed: \(capturedError)")
            print("  you can retry later with `parrot models download \(model.id)`")
        }
    }
}

enum TerminalPrompt {
    static var isInteractive: Bool {
        isatty(FileHandle.standardInput.fileDescriptor) != 0
    }

    static func ask(_ question: String, default defaultValue: String) -> String {
        print("\(question) [\(defaultValue)]: ", terminator: "")
        fflush(stdout)
        guard isInteractive else {
            print(defaultValue)
            return defaultValue
        }
        guard let line = readLine() else { return defaultValue }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}
