import Foundation
@preconcurrency import AVFoundation

#if canImport(Speech)
import Speech
#endif

protocol SpeechTranscribing {
    var isAvailable: Bool { get async }
    func checkAvailability(localeIdentifier: String?) async throws
    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, localeIdentifier: String?, runID: String?) async throws -> AsyncStream<TranscriptSegment>
    func stopTranscription() async
    func getSupportedLocales() async -> [Locale]
}

class SpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?

    private var analyzerTask: Task<Void, Never>?
    private var supportedLocalesCache: [Locale]?

    init() {}

    var isAvailable: Bool {
        get async {
            #if canImport(Speech)
            if #available(macOS 26.0, *) {
                // If ja-JP or any locale is supported, we consider the service available
                let locales = await getSupportedLocales()
                return !locales.isEmpty
            }
            #endif
            return false
        }
    }

    private func resolveLocale(identifier: String?) async throws -> Locale {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let targetId = identifier ?? "ja-JP"
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: targetId)) else {
                let message = String(format: NSLocalizedString("speechTranscription.error.unsupportedLocaleFormat", comment: ""), targetId)
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            return locale
        }
        #endif
        throw NSError(
            domain: "SpeechTranscriptionService",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.startFailed", comment: "")]
        )
    }

    func checkAvailability(localeIdentifier: String?) async throws {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            _ = try await resolveLocale(identifier: localeIdentifier)

            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .denied || micStatus == .restricted {
                throw NSError(
                    domain: "SpeechTranscriptionService",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.permissionDenied", comment: "")]
                )
            }
        } else {
            throw NSError(
                domain: "SpeechTranscriptionService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.startFailed", comment: "")]
            )
        }
        #else
        throw NSError(
            domain: "SpeechTranscriptionService",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.startFailed", comment: "")]
        )
        #endif
    }

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, localeIdentifier: String?, runID: String?) async throws -> AsyncStream<TranscriptSegment> {
        #if DEBUG
        print("[SpeechTranscriptionService] startTranscription called. locale: \(localeIdentifier ?? "default"), runID: \(runID ?? "nil")")
        #endif
        try await checkAvailability(localeIdentifier: localeIdentifier)

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
            let locale = try await resolveLocale(identifier: localeIdentifier)

            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .timeIndexedProgressiveTranscription
            )

            // Asset preparation
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
                                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.audioConversionFailed", comment: "")]
                                    )
                                    self.transcriptionContinuation?.yield(TranscriptSegment(
                                        id: UUID(),
                                        sessionId: "",
                                        partId: "",
                                        text: String(
                                            format: NSLocalizedString("speechTranscription.error.segmentFormat", comment: ""),
                                            error.localizedDescription
                                        ),
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
                                                text: String(
                                                    format: NSLocalizedString("speechTranscription.error.segmentFormat", comment: ""),
                                                    finalError.localizedDescription
                                                ),
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
                                            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.bufferCreationFailed", comment: "")]
                                        )
                                        self.transcriptionContinuation?.yield(TranscriptSegment(
                                            id: UUID(),
                                            sessionId: "",
                                            partId: "",
                                            text: String(
                                                format: NSLocalizedString("speechTranscription.error.segmentFormat", comment: ""),
                                                error.localizedDescription
                                            ),
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

                        _ = transcriptionContinuation?.yield(segment)
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
                        text: String(
                            format: NSLocalizedString("speechTranscription.error.segmentFormat", comment: ""),
                            error.localizedDescription
                        ),
                        isFinal: true,
                        startTime: 0,
                        endTime: 0
                    )
                    _ = transcriptionContinuation?.yield(segment)
                    #if DEBUG
                    print("[SpeechTranscriptionService] [\(runID ?? "none")] Error segment yielded.")
                    #endif
                    self.transcriptionContinuation?.finish()
                }
            }

            return stream
        } else {
            throw NSError(
                domain: "SpeechTranscriptionService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("speechTranscription.error.startFailed", comment: "")]
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

    func getSupportedLocales() async -> [Locale] {
        if let cached = supportedLocalesCache {
            return cached
        }

        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let locales = await withTaskGroup(of: Locale?.self) { group in
                for id in Locale.availableIdentifiers {
                    group.addTask {
                        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id))
                    }
                }

                var results = [Locale]()
                for await locale in group {
                    if let locale = locale {
                        results.append(locale)
                    }
                }
                return results
            }

            // Deduplicate by identifier and sort by localized display name
            let uniqueLocales = Dictionary(grouping: locales, by: { $0.identifier })
                .compactMap { $0.value.first }

            let sortedLocales = uniqueLocales.sorted {
                let nameA = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let nameB = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return nameA.localizedCompare(nameB) == .orderedAscending
            }

            supportedLocalesCache = sortedLocales
            return sortedLocales
        }
        #endif
        return []
    }
}

class MockSpeechTranscriptionService: SpeechTranscribing {
    private var transcriptionContinuation: AsyncStream<TranscriptSegment>.Continuation?

    init() {}

    var isAvailable: Bool {
        get async { true }
    }

    func checkAvailability(localeIdentifier: String?) async throws {
        // Always available in mock
    }

    private var mockTask: Task<Void, Never>?

    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>, localeIdentifier: String?, runID: String?) async throws -> AsyncStream<TranscriptSegment> {
        #if DEBUG
        print("[MockSpeechTranscriptionService] startTranscription called. locale: \(localeIdentifier ?? "nil"), runID: \(runID ?? "nil")")
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
                    let text1 = String(
                        format: NSLocalizedString("speechTranscription.mock.provisionalStart", comment: ""),
                        chunkNum
                    )
                    let segment1 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text1,
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0
                    )
                    _ = transcriptionContinuation?.yield(segment1)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (FIRST): text=\"\(text1)\"")
                    #endif

                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }

                    // 2nd provisional (update)
                    let text2 = String(
                        format: NSLocalizedString("speechTranscription.mock.provisionalUpdate", comment: ""),
                        chunkNum
                    )
                    let segment2 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text2,
                        isFinal: false,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 0.5
                    )
                    _ = transcriptionContinuation?.yield(segment2)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (INTER): textLen=\(text2.count)")
                    #endif

                    // Shortly after yield final
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    let text3 = String(
                        format: NSLocalizedString("speechTranscription.mock.final", comment: ""),
                        chunkNum
                    )
                    let segment3 = TranscriptSegment(
                        id: id,
                        sessionId: "",
                        partId: "",
                        text: text3,
                        isFinal: true,
                        startTime: Double(count) / 10.0,
                        endTime: Double(count) / 10.0 + 1.0
                    )
                    _ = transcriptionContinuation?.yield(segment3)
                    #if DEBUG
                    print("[MockSpeechTranscriptionService] [\(runID ?? "none")] Yield (FINAL): text=\"\(text3)\"")
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

    func getSupportedLocales() async -> [Locale] {
        return [
            Locale(identifier: "ja-JP"),
            Locale(identifier: "en-US")
        ]
    }
}
