import Foundation
@preconcurrency import MLXAudio

// MARK: - TranscriptionResponseFormat

/// Response format for transcription output
public enum TranscriptionResponseFormat {
    case simple // Just text
    case verboseJson // Text with timing and metadata
}

// MARK: - TranscriptionOutput

/// Unified transcription output
public enum TranscriptionOutput: Sendable {
    case simple(String)
    case detailed([TranscriptionResult])
}

// MARK: - SpeechToTextRunner

/// MLXAudio-based implementation for speech recognition
@MainActor
public class SpeechToTextRunner: @unchecked Sendable {
    private var stt: (any STTEngine)?
    private var isRunning = false
    private var selectedModelName: String?

    public init() {}

    /// Load model using MLXAudio's built-in downloader/cache.
    public func loadModel(from modelName: String) async throws {
        let stt = try createSTT(for: modelName)
        try await stt.load()
        self.stt = stt
        self.selectedModelName = modelName
    }

    /// Validate and prepare audio file for transcription
    /// - Parameter url: URL to audio file
    /// - Returns: Path to the prepared audio file (may be converted)
    private func validateAndPrepareAudio(at url: URL) async throws -> String {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioError.transcriptionFailed("Audio file not found: \(url.path)")
        }

        // Basic file size check
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if fileSize == 0 {
            throw AudioError.transcriptionFailed("Audio file is empty")
        }

        // Let MLXAudio handle the actual audio processing
        return url.path
    }

    /// Transcribe audio file with unified options (main interface)
    /// - Parameters:
    ///   - url: URL to audio file
    ///   - language: Language code (e.g., "en", "zh", "ja") or nil for auto-detection
    ///   - temperature: Sampling temperature (0.0-1.0)
    ///   - responseFormat: Response format for output
    /// - Returns: Full transcription results array with timing information when available
    public func transcribe(
        audioFile url: URL,
        language: String? = nil,
        temperature: Float = 0.0,
        responseFormat: TranscriptionResponseFormat = .simple
    ) async throws -> TranscriptionOutput {
        // Prevent concurrent runs
        while isRunning {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        isRunning = true
        defer { isRunning = false }

        guard let stt else {
            throw AudioError.modelLoadFailed("MLXAudio model not initialized")
        }

        // Validate audio file first
        let audioPath = try await validateAndPrepareAudio(at: url)

        // Get results with better error handling
        do {
            let transcription = try await transcribeWithMLXAudio(
                stt: stt,
                audioPath: audioPath,
                language: language,
                temperature: temperature
            )

            // MLXAudio does not currently expose segment metadata in this integration,
            // so we return a single segment for verbose requests.
            switch responseFormat {
            case .simple:
                return .simple(transcription.text)
            case .verboseJson:
                return .detailed([transcription])
            }
        }
        catch {
            // Provide more specific error messages
            let errorMessage = error.localizedDescription
            if errorMessage.contains("1954115647") || errorMessage.contains("coreaudio.avfaudio") {
                throw AudioError
                    .transcriptionFailed(
                        "Audio encoding error: The audio file format is not supported or the file is corrupted. Please try converting to WAV format (16kHz, mono) and try again. Original error: \(errorMessage)"
                    )
            }
            else {
                throw AudioError.transcriptionFailed("Transcription failed: \(errorMessage)")
            }
        }
    }

    // MARK: - Helper Methods

    private func transcribeWithMLXAudio(
        stt: any STTEngine,
        audioPath: String,
        language: String?,
        temperature: Float = 0.0,
        timestamps: TimestampGranularity = .segment // or .word
    ) async throws -> TranscriptionResult {
        let audioURL = URL(fileURLWithPath: audioPath)
        if let language, let sttLanguage = resolveLanguage(language) {
            // Cast to WhisperEngine to access language parameter
            if let whisperEngine = stt as? WhisperEngine {
                let result = try await whisperEngine.transcribe(audioURL, language: sttLanguage, temperature: temperature, timestamps: timestamps)
                return result
            }
        }

        // For non-Whisper engines or no language specified
        if let whisperEngine = stt as? WhisperEngine {
            let result = try await whisperEngine.transcribe(audioURL, temperature: temperature, timestamps: timestamps)
            return result
        }
        else if let funasrEngine = stt as? FunASREngine {
            let result = try await funasrEngine.transcribe(audioURL, temperature: temperature)
            return result
        }

        throw AudioError.transcriptionFailed("Unsupported STT engine type")
    }

    private func resolveLanguage(_ language: String) -> Language? {
        let normalized = language.lowercased()
        switch normalized {
        case "en",
             "english":
            return .english
        case "hu",
             "hungarian":
            return .hungarian
        case "chinese",
             "zh",
             "zh-cn",
             "zh-hans":
            return .chinese
        case "ja",
             "japanese":
            return .japanese
        case "es",
             "spanish":
            return .spanish
        default:
            return nil
        }
    }
}

/// Convenience methods for model integration with Swama
public extension SpeechToTextRunner {
    /// Load model from Swama's model identifier (e.g. "whisper-base", "funasr")
    func loadModel(_ modelIdentifier: String) async throws {
        guard ModelAliasResolver.isAudioModel(modelIdentifier) else {
            throw AudioError
                .invalidInput(
                    "Model '\(modelIdentifier)' is not a supported audio model. Use whisper-* or funasr variants."
                )
        }

        try await loadModel(from: modelIdentifier)
    }
}

// MARK: - Audio Errors

public enum AudioError: Error, LocalizedError {
    case modelLoadFailed(String)
    case audioLoadFailed(String)
    case transcriptionFailed(String)
    case invalidInput(String)
    case modelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(message):
            "Failed to load audio model: \(message)"
        case let .audioLoadFailed(message):
            "Failed to load audio: \(message)"
        case let .transcriptionFailed(message):
            "Transcription failed: \(message)"
        case let .invalidInput(message):
            "Invalid input: \(message)"
        case let .modelNotFound(message):
            message
        }
    }
}

private extension SpeechToTextRunner {
    enum AudioModelKind {
        case whisper
        case funASR
    }
    
    func createSTT(for modelName: String) throws -> any STTEngine {
        switch resolveModelKind(from: modelName) {
        case .funASR:
            return STT.funASR()
        case .whisper:
            let whisperModel = resolveWhisperModel(from: modelName)
            let whisperQuant = resolveWhisperQuant(from: modelName)
            return STT.whisper(model: whisperModel, quantization: whisperQuant)
        }
    }
    
    func resolveModelKind(from modelName: String) -> AudioModelKind {
        let normalized = modelName.lowercased()
        if normalized.hasPrefix("funasr") || normalized.hasPrefix("fun-asr") {
            return .funASR
        }
        return .whisper
    }
    
    func resolveWhisperModel(from modelName: String) -> WhisperModelSize {
        let normalized = modelName.lowercased()
        switch normalized {
        case "whisper-large",
            "whisper-large-v3",
            "whisper-large-v3-4bit",
            "whisper-large-v3-8bit",
            "whisper-large-v3-fp16":
            return .large
        case "whisper-large-turbo",
            "whisper-large-v3-turbo":
            return .largeTurbo
        case "whisper-medium":
            return .medium
        case "whisper-small":
            return .small
        case "whisper-base":
            return .base
        case "whisper-tiny":
            return .tiny
        default:
            return .large
        }
    }

    func resolveWhisperQuant(from modelName: String) -> WhisperQuantization {
        let normalized = modelName.lowercased()
        switch normalized {
        case "whisper-large-v3-8bit":
            return .q8
        case "whisper-large-v3-fp16":
            return .fp16
        default:
            return .q4
        }
    }
}
