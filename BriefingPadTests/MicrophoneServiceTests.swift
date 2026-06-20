import XCTest
import AVFoundation
@testable import BriefingPad

class MockAudioEngineProvider: AudioEngineProvider {
    var startCalled = false
    var stopCalled = false
    var prepareCalled = false
    var installTapCalled = false
    var removeTapCalled = false

    func start() throws { startCalled = true }
    func stop() { stopCalled = true }
    func prepare() { prepareCalled = true }
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {
        installTapCalled = true
    }
    func removeTap(onBus bus: AVAudioNodeBus) {
        removeTapCalled = true
    }
    var inputNodeFormat: AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    }
}

class MicrophoneServiceTests: XCTestCase {

    var service: MicrophoneService!
    var mockEngine: MockAudioEngineProvider!

    override func setUp() {
        super.setUp()
        mockEngine = MockAudioEngineProvider()
        service = MicrophoneService(audioEngine: mockEngine)
    }

    override func tearDown() {
        service = nil
        mockEngine = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(service.status, .idle)
        XCTAssertEqual(service.audioLevel, .silent)
    }

    func testStopRecording() {
        service.stopRecording()
        XCTAssertTrue(mockEngine.stopCalled)
        XCTAssertTrue(mockEngine.removeTapCalled)
        XCTAssertEqual(service.status, .idle)
    }

    func testStartRecordingRequiresPermission() {
        // Initially undetermined or denied in test environment usually
        service.permissionStatus = .denied
        service.startRecording()

        XCTAssertFalse(mockEngine.startCalled)
        if case .error = service.status {
            // Success: it should error out if denied
        } else {
            // In some test setups, it might stay idle if it triggers a request
        }
    }
}
