import Foundation

enum Engine: String, Codable {
    case whisperKit
    case parakeet
}

struct TranscriptionModel: Codable {
    let id: String
    let displayName: String
    let engine: Engine
    /// Engine-specific identifier (e.g. "openai_whisper-base.en" for WhisperKit).
    let whisperKitID: String?
    let sizeMB: Int
    let languages: [String]
    let recommended: Bool

    /// English-only models list `en`; multilingual models list `multi`.
    func supports(language: String) -> Bool {
        languages.contains("multi") || languages.contains(language)
    }
}

struct ModelsManifest: Codable {
    let models: [TranscriptionModel]
}
