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

    private let audioEngine: AudioEngineProvider
    private var lastLevelUpdateTime: Date = .distantPast
    private let levelUpdateInterval: TimeInterval = 0.1 // 10Hz

    init(audioEngine: AudioEngineProvider = SystemAudioEngineProvider()) {
        self.audioEngine = audioEngine
        checkPermission()
    }

    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
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
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.permissionStatus = granted ? .granted : .denied
                completion(granted)
            }
        }
    }

    func startRecording() {
        guard status != .recording else { return }

        guard permissionStatus == .granted else {
            requestPermission { granted in
                if granted {
                    self.startRecording()
                } else {
                    self.status = .error("マイクの使用が許可されていません")
                }
            }
            return
        }

        do {
            let recordingFormat = audioEngine.inputNodeFormat

            audioEngine.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
                self?.processAudioBuffer(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.status = .recording
            }
        } catch {
            DispatchQueue.main.async {
                self.status = .error("録音の開始に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.removeTap(onBus: 0)

        DispatchQueue.main.async {
            self.status = .idle
            self.audioLevel = .silent
        }
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
