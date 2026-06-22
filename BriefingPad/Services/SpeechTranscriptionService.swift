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
                return SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) != nil
            }
            #endif
            return false
        }
    }

    private func resolveLocale() throws -> Locale {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            guard let locale = SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "日本語の音声認識に対応していません"]
                )
            }
            return locale
        }
        #endif
        throw NSError(
            domain: "SpeechTranscriptionService",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "音声認識を開始できません"]
        )
    }

    func checkAvailability() async throws {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            _ = try resolveLocale()

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
            let locale = try resolveLocale()

            // 資産の準備（日本語モデルの準備）
            let assetRequest = AssetInventory.assetInstallationRequest(supporting: locale)
            if assetRequest.status != .installed {
                // ダウンロードが必要な場合は、完了まで待機する
                for await status in assetRequest.progress {
                    if status == .installed { break }
                }
            }

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
                            var converter: AVAudioConverter?
                            var targetFormat: AVAudioFormat?

                            for await buffer in audioStream {
                                if Task.isCancelled { break }

                                // ターゲットフォーマットの取得とコンバーターの初期化
                                if targetFormat == nil {
                                    targetFormat = SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: buffer.format)
                                    if let target = targetFormat {
                                        converter = AVAudioConverter(from: buffer.format, to: target)
                                    }
                                }

                                guard let target = targetFormat, let conv = converter else {
                                    // 変換不可の場合はエラー終了
                                    let error = NSError(
                                        domain: "SpeechTranscriptionService",
                                        code: 5,
                                        userInfo: [NSLocalizedDescriptionKey: "オーディオ形式の変換に失敗しました"]
                                    )
                                    self.transcriptionContinuation?.yield(TranscriptSegment(
                                        id: UUID(),
                                        sessionId: "",
                                        partId: "",
                                        text: "Error: \(error.localizedDescription)",
                                        isFinal: true,
                                        startTime: 0,
                                        endTime: 0
                                    ))
                                    continuation.finish()
                                    return
                                }

                                if target == buffer.format {
                                    continuation.yield(AnalyzerInput(buffer: buffer))
                                } else {
                                    // フォーマット変換
                                    let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)
                                    if let outputBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frameCount) {
                                        var error: NSError?
                                        let status = conv.convert(to: outputBuffer, error: &error) { _, outStatus in
                                            outStatus.pointee = .haveData
                                            return buffer
                                        }

                                        if status == .error || error != nil {
                                            let finalError = error ?? NSError(domain: "SpeechTranscriptionService", code: 5, userInfo: nil)
                                            print("Audio conversion failed: \(finalError)")
                                            self.transcriptionContinuation?.yield(TranscriptSegment(
                                                id: UUID(),
                                                sessionId: "",
                                                partId: "",
                                                text: "Error: \(finalError.localizedDescription)",
                                                isFinal: true,
                                                startTime: 0,
                                                endTime: 0
                                            ))
                                            continuation.finish()
                                            return
                                        }

                                        continuation.yield(AnalyzerInput(buffer: outputBuffer))
                                    }
                                }
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
                    let segment = TranscriptSegment(
                        id: UUID(),
                        sessionId: "",
                        partId: "",
                        text: "Error: \(error.localizedDescription)",
                        isFinal: true,
                        startTime: 0,
                        endTime: 0
                    )
                    transcriptionContinuation?.yield(segment)
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
