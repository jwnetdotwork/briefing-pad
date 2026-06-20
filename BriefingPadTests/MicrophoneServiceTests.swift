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
        let expectation = XCTestExpectation(description: "Status updates to .idle")

        let cancellable = service.$status
            .dropFirst()
            .sink { status in
                if status == .idle {
                    expectation.fulfill()
                }
            }

        service.stopRecording()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockEngine.stopCalled)
        XCTAssertTrue(mockEngine.removeTapCalled)
        XCTAssertEqual(service.status, .idle)
        cancellable.cancel()
    }

    func testStartRecordingRequiresPermission() {
        service.permissionStatus = .denied

        let expectation = XCTestExpectation(description: "Status updates to .error")
        let cancellable = service.$status
            .dropFirst()
            .sink { status in
                if case .error = status {
                    expectation.fulfill()
                }
            }

        service.startRecording()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(mockEngine.startCalled)
        if case .error(let message) = service.status {
            XCTAssertEqual(message, "マイクの使用が許可されていません")
        } else {
            XCTFail("Status should be .error")
        }
        cancellable.cancel()
    }
}
