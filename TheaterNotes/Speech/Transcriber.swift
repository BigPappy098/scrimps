import Foundation
import Speech

enum TranscriberError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Speech recognition isn't available on this device right now."
    }
}

/// Wraps Apple's on-device speech recognition. Cast names are passed as
/// `contextualStrings` so the engine is biased toward getting them right.
final class Transcriber {
    static let shared = Transcriber()

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(url: URL, contextualStrings: [String]) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw TranscriberError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }
        // Keep it on-device when possible: free, private, and works offline.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
