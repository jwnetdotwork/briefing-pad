import Foundation
import AVFoundation

#if canImport(Speech)
import Speech
#endif

protocol SpeechTranscribing {
    var isAvailable: Bool { get async }
    func checkAvailability() async throws
    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, runID: String?) async throws -> AsyncStream<TranscriptSegment>
    func stopTranscription() async
}

class SpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?

    private var analyzerTask: Task<Void, Never>?

    init() {}

    var isAvailable: Bool {
        get async {
            #if canImport(Speech)
            if #available(macOS 26.0, *) {
                return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) != nil
            }
            #endif
            return false
        }
    }

    private func resolveLocale() async throws -> Locale {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
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
            _ = try await resolveLocale()

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

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, runID: String?) async throws -> AsyncStream<TranscriptSegment> {
        #if DEBUG
        print("[SpeechTranscriptionService] startTranscription called. runID: \(runID ?? "nil")")
        #endif
        try await checkAvailability()

        let stream = AsyncStream<TranscriptSegment> { continuation in
            self.transcriptionContinuation = continuation
            continuation.onTermination = { termination in
                #if DEBUG
                print("[SpeechTranscriptionService] results stream onTermination: \(termination) (runID: \(runID ?? "none"))")
                #endif
            }
        }

        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let locale = try await resolveLocale()

            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .timeIndexedProgressiveTranscription
            )

            // 資産の準備（日本語モデルの準備）
            if let assetRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                #if DEBUG
                print("[SpeechTranscriptionService] [\(runID ?? "none")] Requesting asset installation...")
                #endif
                try await assetRequest.downloadAndInstall()
                #if DEBUG
                print("[SpeechTranscriptionService] [\(runID ?? "none")] Asset installation completed.")
                #endif
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])

            analyzerTask = Task {
                #if DEBUG
                print("[SpeechTranscriptionService] [\(runID ?? "none")] Analyzer task started.")
                #endif
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
                                    targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: buffer.format)
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
                                    } else {
                                        let error = NSError(
                                            domain: "SpeechTranscriptionService",
                                            code: 6,
                                            userInfo: [NSLocalizedDescriptionKey: "バッファの作成に失敗しました"]
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
                                }
                            }

                            continuation.finish()
                        }
                    }

                    async let analysis: CMTime? = analyzer.analyzeSequence(inputSequence)

                    var isFirstResult = true
                    for try await result in transcriber.results {
                        if Task.isCancelled {
                            #if DEBUG
                            print("[SpeechTranscriptionService] [\(runID ?? "none")] transcriber.results loop cancelled.")
                            #endif
                            break
                        }
                        
                        let text = String(result.text.characters)
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                        #if DEBUG
                        let duration = result.range.end.seconds - result.range.start.seconds
                        if isFirstResult || result.isFinal {
                            print("[SpeechTranscriptionService] [\(runID ?? "none")] Result (\(isFirstResult ? "FIRST" : "FINAL")): isFinal=\(result.isFinal), textLen=\(text.count), duration=\(String(format: "%.2f", duration))s, text=\"\(text)\"")
                            isFirstResult = false
                        } else {
//                            print("[SpeechTranscriptionService] [\(runID ?? "none")] Result (INTER): isFinal=\(result.isFinal), textLen=\(text.count), duration=\(String(format: "%.2f", duration))s")
                        }
                        #endif

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

                        let yieldResult = transcriptionContinuation?.yield(segment)
                        #if DEBUG
//                        print("[SpeechTranscriptionService] [\(runID ?? "none")] yield result: \(String(describing: yieldResult)), isFinal: \(segment.isFinal), text: \"\(segment.text)\"")
                        #endif

                        if result.isFinal {
                            utteranceIds.removeValue(forKey: timeKey)
                        }
                    }

                    _ = try await analysis
                    #if DEBUG
                    print("[SpeechTranscriptionService] [\(runID ?? "none")] Analyzer task finished normally.")
                    #endif
                    self.transcriptionContinuation?.finish()
                } catch {
                    #if DEBUG
                    if error is CancellationError {
                        print("[SpeechTranscriptionService] [\(runID ?? "none")] Analyzer task cancelled.")
                    } else {
                        print("[SpeechTranscriptionService] [\(runID ?? "none")] Analyzer task failed: \(error)")
                    }
                    #endif
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
                    let yieldResult = transcriptionContinuation?.yield(segment)
                    #if DEBUG
                    print("[SpeechTranscriptionService] [\(runID ?? "none")] Error segment yield result: \(String(describing: yieldResult))")
                    #endif
                    self.transcriptionContinuation?.finish()
                }
            }

            return stream
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
        #if DEBUG
        print("[SpeechTranscriptionService] stopTranscription called.")
        #endif
        analyzerTask?.cancel()
        analyzerTask = nil
        transcriptionContinuation?.finish()
        transcriptionContinuation = nil
    }
}

class MockSpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?

    init() {}

    var isAvailable: Bool {
        get async { true }
    }

    func checkAvailability() async throws {
        // Always available in mock
    }

    private var mockTask: Task<Void, Never>?

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, runID: String?) async throws -> AsyncStream<TranscriptSegment> {
        #if DEBUG
        print("[MockSpeechTranscriptionService] startTranscription called. runID: \(runID ?? "nil")")
        #endif
        mockTask?.cancel()
        mockTask = nil

        let stream = AsyncStream<TranscriptSegment> { continuation in
            self.transcriptionContinuation = continuation
            continuation.onTermination = { termination in
                #if DEBUG
                print("[MockSpeechTranscriptionService] results stream onTermination: \(termination) (runID: \(runID ?? "none"))")
                #endif
            }
        }

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
                    let text1 = "（認識中...）発話チャンク \(chunkNum)"
                    let segment1 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text1,
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0
                    )
                    let yieldResult1 = transcriptionContinuation?.yield(segment1)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (FIRST): result=\(String(describing: yieldResult1)), text=\"\(text1)\"")
                    #endif

                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }

                    // 2nd provisional (update)
                    let text2 = "（認識中...）確定間近 \(chunkNum)"
                    let segment2 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text2,
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 0.5
                    )
                    let yieldResult2 = transcriptionContinuation?.yield(segment2)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (INTER): result=\(String(describing: yieldResult2)), textLen=\(text2.count)")
                    #endif

                    // Shortly after yield final
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    let text3 = "確定した発話 \(chunkNum)"
                    let segment3 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text3,
                        isFinal: true,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 1.0
                    )
                    let yieldResult3 = transcriptionContinuation?.yield(segment3)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (FINAL): result=\(String(describing: yieldResult3)), text=\"\(text3)\"")
                    #endif
                }
            }
            self.transcriptionContinuation?.finish()
        }

        return stream
    }

    func stopTranscription() async {
        #if DEBUG
        print("[MockSpeechTranscriptionService] stopTranscription called.")
        #endif
        mockTask?.cancel()
        mockTask = nil
        transcriptionContinuation?.finish()
        transcriptionContinuation = nil
    }
}
