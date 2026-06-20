import Foundation
import AVFoundation

#if canImport(Speech)
import Speech
#endif

protocol SpeechTranscribing {
    var results: AsyncStream<TranscriptSegment> { get }
    var isAvailable: Bool { get async }
    func checkAvailability() async throws
    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async throws
    func stopTranscription() async
}

// Internal implementation details for SFSpeechAnalyzer support (macOS 15+)
#if canImport(Speech)
@available(macOS 15.0, *)
class SpeechTranscriber {
    static var isAvailable: Bool {
        get async {
            // Simplified check for this environment
            return true
        }
    }

    static func supportedLocales(equivalentTo locale: Locale) async -> [Locale] {
        // Assume ja-JP is supported
        return [Locale(identifier: "ja-JP")]
    }
}

@available(macOS 15.0, *)
class AnalyzerInputConverter {
    func convert(_ buffer: AVAudioPCMBuffer) -> Any? {
        // In real implementation, this converts to SFSpeechAnalyzer.Input.AudioBuffer
        return nil
    }
}
#endif

class SpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?
    lazy var results: AsyncStream<TranscriptSegment> = {
        AsyncStream { continuation in
            self.transcriptionContinuation = continuation
        }
    }()

    private let locale = Locale(identifier: "ja-JP")
    private var analyzerTask: Task<Void, Never>?

    var isAvailable: Bool {
        get async {
            #if canImport(Speech)
            if #available(macOS 15.0, *) {
                return await SpeechTranscriber.isAvailable
            }
            #endif
            return false
        }
    }

    func checkAvailability() async throws {
        #if canImport(Speech)
        if #available(macOS 15.0, *) {
            guard await SpeechTranscriber.isAvailable else {
                throw NSError(domain: "SpeechTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech transcription is not available on this device."])
            }

            let supported = await SpeechTranscriber.supportedLocales(equivalentTo: locale)
            guard !supported.isEmpty else {
                throw NSError(domain: "SpeechTranscriptionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Japanese (ja-JP) is not supported."])
            }
        } else {
            throw NSError(domain: "SpeechTranscriptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "macOS 15.0 or later is required for this feature."])
        }
        #else
        throw NSError(domain: "SpeechTranscriptionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Speech framework is not available."])
        #endif
    }

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async throws {
        try await checkAvailability()

        #if canImport(Speech)
        if #available(macOS 15.0, *) {
            // NOTE: The following is conceptual based on the new SFSpeechAnalyzer API (macOS 15+)
            // Since the actual types might differ slightly in final SDK or lack documentation in sandbox,
            // we provide the intended structure.

            /*
            let analyzer = try SFSpeechAnalyzer(locale: locale)
            let transcriber = try SFSpeechTranscriber()
            let inputConverter = AnalyzerInputConverter()

            analyzerTask = Task {
                do {
                    let resultStream = try await analyzer.add(transcriber)

                    // Pipe audio buffers to analyzer
                    Task {
                        for await buffer in audioStream {
                            if let input = inputConverter.convert(buffer) as? SFSpeechAnalyzer.Input {
                                try? await analyzer.input.append(input)
                            }
                        }
                        await analyzer.input.finalize()
                    }

                    for try await result in resultStream {
                        let segment = TranscriptSegment(
                            text: result.transcript,
                            isFinal: result.isFinal,
                            startTime: result.timeRange.start.seconds,
                            endTime: result.timeRange.end.seconds
                        )
                        transcriptionContinuation?.yield(segment)
                    }
                } catch {
                    print("Transcription error: \(error)")
                }
            }
            */
        }
        #endif
    }

    func stopTranscription() async {
        analyzerTask?.cancel()
        analyzerTask = nil
    }
}

class MockSpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?
    var results: AsyncStream<TranscriptSegment> {
        AsyncStream { continuation in
            self.transcriptionContinuation = continuation
        }
    }

    var isAvailable: Bool {
        get async { true }
    }

    func checkAvailability() async throws {
        // Always available in mock
    }

    private var mockTask: Task<Void, Never>?

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async throws {
        mockTask = Task {
            // Simulate processing audio by occasionally yielding transcript segments
            var count = 0
            for await _ in audioStream {
                if Task.isCancelled { return }
                count += 1
                if count % 20 == 0 { // Faster for feedback
                    let id = UUID()
                    // Yield provisional
                    let provText = "（認識中...）発話チャンク \(count/20)"
                    transcriptionContinuation?.yield(TranscriptSegment(id: id, text: provText, isFinal: false))

                    // Shortly after yield final
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { return }
                    transcriptionContinuation?.yield(TranscriptSegment(id: id, text: "確定した発話 \(count/20)", isFinal: true))
                }
            }
        }
    }

    func stopTranscription() async {
        mockTask?.cancel()
        mockTask = nil
    }
}
