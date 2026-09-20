import Foundation
import WhisperKit

/// Persistent daemon options. File format is a tiny TOML subset:
///
/// ```toml
/// model = "whisper-base.en"
/// language = "en"
/// ```
///
/// Resolution order: CLI flags > this file > built-in defaults.
struct ParrotConfig: Equatable {
    var model: String?
    var language: String?

    static let defaultModelID = "whisper-base.en"
    static let defaultLanguage = "en"

    var resolvedModelID: String { model ?? Self.defaultModelID }
    var resolvedLanguage: String { language ?? Self.defaultLanguage }

    static func parse(_ text: String) -> ParrotConfig {
        var config = ParrotConfig()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            switch key {
            case "model": config.model = value
            case "language": config.language = value
            default: break
            }
        }
        return config
    }

    func serialize() -> String {
        var lines = ["# parrot config — `parrot config set <key> <value>`"]
        if let model {
            lines.append("model = \"\(model)\"")
        }
        if let language {
            lines.append("language = \"\(language)\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum ConfigStore {
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["PARROT_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/parrot/config.toml")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func load() -> ParrotConfig {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return ParrotConfig() }
        return ParrotConfig.parse(text)
    }

    static func save(_ config: ParrotConfig) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try config.serialize().write(to: url, atomically: true, encoding: .utf8)
    }
}

enum LanguageCode {
    static let common: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("pt", "Portuguese"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
    ]

    /// Accepts an ISO code (`es`) or English name (`spanish`).
    static func resolve(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if Constants.languageCodes.contains(s) { return s }
        return Constants.languages[s]
    }
}

enum ConfigValidationError: Error, CustomStringConvertible {
    case unknownKey(String)
    case unknownModel(String)
    case unknownLanguage(String)
    case languageNotSupported(language: String, model: String)

    var description: String {
        switch self {
        case .unknownKey(let key):
            return "unknown config key: \(key)\n  valid keys: model, language"
        case .unknownModel(let id):
            return "unknown model: \(id)\n  run `parrot models list` to see options"
        case .unknownLanguage(let raw):
            return "unknown language: \(raw)\n  use an ISO code (en, es, pt, …) or a name (english, spanish)"
        case .languageNotSupported(let language, let model):
            return "\(model) is English-only; cannot use language \(language)\n  parrot config set model whisper-large-v3-turbo"
        }
    }
}

enum ConfigResolver {
    static func resolve(cliModel: String?, cliLanguage: String?) throws -> (TranscriptionModel, String) {
        let file = ConfigStore.load()
        let modelID = cliModel ?? file.resolvedModelID
        let languageRaw = cliLanguage ?? file.resolvedLanguage
        return try validated(modelID: modelID, language: languageRaw)
    }

    static func validated(modelID: String, language: String) throws -> (TranscriptionModel, String) {
        guard let model = ModelRegistry.find(modelID) else {
            throw ConfigValidationError.unknownModel(modelID)
        }
        guard let code = LanguageCode.resolve(language) else {
            throw ConfigValidationError.unknownLanguage(language)
        }
        guard model.supports(language: code) else {
            throw ConfigValidationError.languageNotSupported(language: code, model: modelID)
        }
        return (model, code)
    }

    static func firstMultilingualModel() -> TranscriptionModel? {
        ModelRegistry.shared.first { $0.languages.contains("multi") }
    }
}
