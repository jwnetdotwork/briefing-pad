import Foundation
import AVFoundation
import Combine

enum MicrophonePermissionStatus {
    case undetermined
    case granted
    case denied
}

enum MicrophoneStatus: Equatable {
    case idle
    case starting
    case recording
    case error(String)
}

enum AudioLevel: String {
    case silent = "無音"
    case low = "小"
    case mid = "中"
    case high = "大"

    static func from(amplitude: Float) -> AudioLevel {
        if amplitude < 0.01 { return .silent }
        if amplitude < 0.1 { return .low }
        if amplitude < 0.4 { return .mid }
        return .high
    }
}

protocol AudioEngineProvider {
    func start() throws
    func stop()
    func prepare()
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock)
    func removeTap(onBus bus: AVAudioNodeBus)
    var inputNodeFormat: AVAudioFormat { get }
}

protocol PermissionProvider {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(completion: @escaping (Bool) -> Void)
}

class SystemPermissionProvider: PermissionProvider {
    func authorizationStatus() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }
    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

class SystemAudioEngineProvider: AudioEngineProvider {
    private let audioEngine = AVAudioEngine()

    func start() throws { try audioEngine.start() }
    func stop() { audioEngine.stop() }
    func prepare() { audioEngine.prepare() }
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {
        audioEngine.inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }
    func removeTap(onBus bus: AVAudioNodeBus) {
        audioEngine.inputNode.removeTap(onBus: bus)
    }
    var inputNodeFormat: AVAudioFormat {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }
}

class MicrophoneService: ObservableObject {
    @Published var permissionStatus: MicrophonePermissionStatus = .undetermined
    @Published var status: MicrophoneStatus = .idle
    @Published var audioLevel: AudioLevel = .silent

    private var audioBufferContinuations: [UUID: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]

    private let audioEngine: AudioEngineProvider
    private let permissionProvider: PermissionProvider
    private var lastLevelUpdateTime: Date = .distantPast
    private let levelUpdateInterval: TimeInterval = 0.1 // 10Hz

    private var isStartingRecording = false

    func createAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        let id = UUID()
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(50)) { continuation in
            objc_sync_enter(self)
            self.audioBufferContinuations[id] = continuation
            objc_sync_exit(self)

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                objc_sync_enter(self)
                self.audioBufferContinuations.removeValue(forKey: id)
                objc_sync_exit(self)
            }
        }
    }
    private var currentPermissionRequestID = 0

    init(
        audioEngine: AudioEngineProvider = SystemAudioEngineProvider(),
        permissionProvider: PermissionProvider = SystemPermissionProvider()
    ) {
        self.audioEngine = audioEngine
        self.permissionProvider = permissionProvider
        checkPermission()
    }

    func checkPermission() {
        let status = permissionProvider.authorizationStatus()
        switch status {
        case .authorized:
            self.permissionStatus = .granted
        case .denied, .restricted:
            self.permissionStatus = .denied
        case .notDetermined:
            self.permissionStatus = .undetermined
        @unknown default:
            self.permissionStatus = .undetermined
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        permissionProvider.requestAccess { granted in
            DispatchQueue.main.async {
                self.permissionStatus = granted ? .granted : .denied
                completion(granted)
            }
        }
    }

    func startRecording() {
        guard status != .recording && !isStartingRecording else { return }
        isStartingRecording = true
        status = .starting

        switch permissionStatus {
        case .granted:
            performStartRecording()
        case .undetermined:
            let requestID = currentPermissionRequestID
            requestPermission { [weak self] granted in
                guard let self = self, self.currentPermissionRequestID == requestID else { return }
                if granted {
                    self.performStartRecording()
                } else {
                    self.isStartingRecording = false
                    self.status = .error("マイクの使用が許可されていません")
                }
            }
        case .denied:
            isStartingRecording = false
            status = .error("マイクの使用が許可されていません")
        }
    }

    private func performStartRecording() {
        do {
            let recordingFormat = audioEngine.inputNodeFormat

            audioEngine.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
                guard let self = self else { return }
                self.processAudioBuffer(buffer)

                objc_sync_enter(self)
                let continuations = Array(self.audioBufferContinuations.values)
                objc_sync_exit(self)

                for continuation in continuations {
                    continuation.yield(buffer)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isStartingRecording = false
                self.status = .recording
            }
        } catch {
            audioEngine.removeTap(onBus: 0)
            DispatchQueue.main.async {
                self.isStartingRecording = false
                self.status = .error("録音の開始に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording() {
        cancelPendingOperations()
        audioEngine.stop()
        audioEngine.removeTap(onBus: 0)

        DispatchQueue.main.async {
            self.status = .idle
            self.audioLevel = .silent
        }
    }

    func cancelPendingOperations() {
        currentPermissionRequestID += 1
        isStartingRecording = false
    }

    func cancelPendingOperationsAndStop() {
        cancelPendingOperations()
        stopRecording()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdateTime) >= levelUpdateInterval else { return }
        lastLevelUpdateTime = now

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = UInt32(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            sum += channelData[i] * channelData[i]
        }

        let rms = sqrt(sum / Float(frameLength))
        let level = AudioLevel.from(amplitude: rms)

        DispatchQueue.main.async {
            self.audioLevel = level
        }

        // Phase 2-2 will handle more complex processing here
    }
}
