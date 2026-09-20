import ArgumentParser
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Get and set persistent options (model, language).",
        subcommands: [List.self, Get.self, Set.self, Unset.self, Path.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show effective config (defaults included)."
        )

        func run() throws {
            let config = ConfigStore.load()
            print("model=\(config.resolvedModelID)")
            print("language=\(config.resolvedLanguage)")
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print one config value."
        )

        @Argument(help: "Key (model or language).")
        var key: String

        func run() throws {
            let config = ConfigStore.load()
            switch key {
            case "model":
                print(config.resolvedModelID)
            case "language":
                print(config.resolvedLanguage)
            default:
                throw ValidationError(ConfigValidationError.unknownKey(key).description)
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a config value."
        )

        @Argument(help: "Key (model or language).")
        var key: String

        @Argument(help: "Value.")
        var value: String

        func run() throws {
            var config = ConfigStore.load()
            switch key {
            case "model":
                guard ModelRegistry.find(value) != nil else {
                    throw ValidationError(ConfigValidationError.unknownModel(value).description)
                }
                config.model = value
            case "language":
                guard let code = LanguageCode.resolve(value) else {
                    throw ValidationError(ConfigValidationError.unknownLanguage(value).description)
                }
                config.language = code
                if let current = ModelRegistry.find(config.resolvedModelID),
                   !current.supports(language: code),
                   let multi = ConfigResolver.firstMultilingualModel()
                {
                    config.model = multi.id
                    print("note: switched model to \(multi.id) (\(current.id) is English-only)")
                }
            default:
                throw ValidationError(ConfigValidationError.unknownKey(key).description)
            }

            do {
                _ = try ConfigResolver.validated(
                    modelID: config.resolvedModelID,
                    language: config.resolvedLanguage
                )
            } catch {
                throw ValidationError("\(error)")
            }

            try ConfigStore.save(config)
            switch key {
            case "model":
                print("model = \(config.resolvedModelID)")
            case "language":
                print("language = \(config.resolvedLanguage)")
            default:
                break
            }
        }
    }

    struct Unset: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a key and fall back to the default."
        )

        @Argument(help: "Key (model or language).")
        var key: String

        func run() throws {
            var config = ConfigStore.load()
            switch key {
            case "model":
                config.model = nil
            case "language":
                config.language = nil
            default:
                throw ValidationError(ConfigValidationError.unknownKey(key).description)
            }
            do {
                _ = try ConfigResolver.validated(
                    modelID: config.resolvedModelID,
                    language: config.resolvedLanguage
                )
            } catch {
                throw ValidationError("\(error)")
            }
            try ConfigStore.save(config)
            print("\(key) unset · now \(key == "model" ? config.resolvedModelID : config.resolvedLanguage)")
        }
    }

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the config file path."
        )

        func run() {
            print(ConfigStore.url.path)
        }
    }
}
