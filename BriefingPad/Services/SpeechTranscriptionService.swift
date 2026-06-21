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

class SpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?
    let results: AsyncStream<TranscriptSegment>

    private let locale = Locale(identifier: "ja-JP")
    private var analyzerTask: Task<Void, Never>?

    init() {
        var continuation: AsyncStream<TranscriptSegment>.Continuation?
        self.results = AsyncStream { cont in
            continuation = cont
        }
        self.transcriptionContinuation = continuation
    }

    var isAvailable: Bool {
        get async {
            #if canImport(Speech)
            if #available(macOS 26.0, *) {
                return SpeechTranscriber.supportedLocales.contains {
                    $0.identifier.hasPrefix("ja")
                }
            }
            #endif
            return false
        }
    }

    func checkAvailability() async throws {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let supportedLocales = SpeechTranscriber.supportedLocales

            guard supportedLocales.contains(where: { $0.identifier.hasPrefix("ja") }) else {
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "日本語の音声認識に対応していません"]
                )
            }

            let authStatus = SFSpeechRecognizer.authorizationStatus()
            if authStatus == .denied || authStatus == .restricted {
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "音声認識を開始できません"]
                )
            }

            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .denied || micStatus == .restricted {
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "マイクの使用が許可されていません"]
                )
            }
        } else {
            throw NSError(
                domain: "SpeechTranscriptionService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "音声認識を開始できません"]
            )
        }
        #else
        throw NSError(
            domain: "SpeechTranscriptionService",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "音声認識を開始できません"]
        )
        #endif
    }

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async throws {
        try await checkAvailability()

        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .timeIndexedProgressiveTranscription
            )

            let analyzer = SpeechAnalyzer(modules: [transcriber])

            analyzerTask = Task {
                var utteranceIds: [Int64: UUID] = [:]

                do {
                    let inputSequence = AsyncStream<AnalyzerInput> { continuation in
                        Task {
                            for await buffer in audioStream {
                                if Task.isCancelled { break }

                                // ここはSDKのAnalyzerInput初期化方法に合わせる
                                let input = AnalyzerInput(buffer: buffer)
                                continuation.yield(input)
                            }

                            continuation.finish()
                        }
                    }

                    async let analysis: CMTime? = analyzer.analyzeSequence(inputSequence)

                    for try await result in transcriber.results {
                        if Task.isCancelled { break }
                        
                        let text = String(result.text.characters)
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !text.isEmpty else { continue }

                        let startTime = result.range.start.seconds
                        let endTime = result.range.end.seconds

                        let timeKey = Int64(startTime * 1000)

                        let id: UUID
                        if let existingId = utteranceIds[timeKey] {
                            id = existingId
                        } else {
                            id = UUID()
                            utteranceIds[timeKey] = id
                        }

                        let segment = TranscriptSegment(
                            id: id,
                            sessionId: "",
                            partId: "",
                            text: text,
                            isFinal: result.isFinal,
                            startTime: startTime,
                            endTime: endTime
                        )

                        transcriptionContinuation?.yield(segment)

                        if result.isFinal {
                            utteranceIds.removeValue(forKey: timeKey)
                        }
                    }

                    _ = try await analysis
                } catch {
                    print("SpeechAnalyzer failed: \(error)")
                }
            }
        } else {
            throw NSError(
                domain: "SpeechTranscriptionService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "音声認識を開始できません"]
            )
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
    let results: AsyncStream<TranscriptSegment>

    init() {
        var continuation: AsyncStream<TranscriptSegment>.Continuation?
        self.results = AsyncStream { cont in
            continuation = cont
        }
        self.transcriptionContinuation = continuation
    }

    var isAvailable: Bool {
        get async { true }
    }

    func checkAvailability() async throws {
        // Always available in mock
    }

    private var mockTask: Task<Void, Never>?

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async throws {
        mockTask?.cancel()
        mockTask = nil

        mockTask = Task {
            // Simulate processing audio by occasionally yielding transcript segments
            var count = 0
            for await _ in audioStream {
                if Task.isCancelled { return }
                count += 1
                if count % 20 == 0 { // Faster for feedback
                    let id = UUID()
                    let chunkNum = count / 20

                    // 1st provisional
                    transcriptionContinuation?.yield(TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: "（認識中...）発話チャンク \(chunkNum)",
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0
                    ))

                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }

                    // 2nd provisional (update)
                    transcriptionContinuation?.yield(TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: "（認識中...）確定間近 \(chunkNum)",
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 0.5
                    ))

                    // Shortly after yield final
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    transcriptionContinuation?.yield(TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: "確定した発話 \(chunkNum)",
                        isFinal: true,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 1.0
                    ))
                }
            }
        }
    }

    func stopTranscription() async {
        mockTask?.cancel()
        mockTask = nil
    }
}
