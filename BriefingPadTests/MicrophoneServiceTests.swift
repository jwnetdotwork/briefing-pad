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
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("Failed to create AVAudioFormat in MockAudioEngineProvider")
        }
        return format
    }
}

class MockPermissionProvider: PermissionProvider {
    var status: AVAuthorizationStatus = .notDetermined
    var requestAccessCalled = false
    var requestAccessResult = true

    func authorizationStatus() -> AVAuthorizationStatus {
        return status
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestAccessCalled = true
        completion(requestAccessResult)
    }
}

class MicrophoneServiceTests: XCTestCase {

    var service: MicrophoneService!
    var mockEngine: MockAudioEngineProvider!
    var mockPermission: MockPermissionProvider!

    override func setUp() {
        super.setUp()
        mockEngine = MockAudioEngineProvider()
        mockPermission = MockPermissionProvider()
        service = MicrophoneService(audioEngine: mockEngine, permissionProvider: mockPermission)
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
        addTeardownBlock { cancellable.cancel() }

        service.stopRecording()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockEngine.stopCalled)
        XCTAssertTrue(mockEngine.removeTapCalled)
        XCTAssertEqual(service.status, .idle)
    }

    func testStartRecordingRequiresPermission() {
        mockPermission.status = .denied
        service.checkPermission() // Update service state

        let expectation = XCTestExpectation(description: "Status updates to .error")
        let cancellable = service.$status
            .dropFirst()
            .sink { status in
                if case .error = status {
                    expectation.fulfill()
                }
            }
        addTeardownBlock { cancellable.cancel() }

        service.startRecording()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(mockEngine.startCalled)
        XCTAssertFalse(mockPermission.requestAccessCalled) // Should NOT call requestAccess if already denied
        if case .error(let message) = service.status {
            XCTAssertEqual(message, "マイクの使用が許可されていません")
        } else {
            XCTFail("Status should be .error")
        }
    }

    func testStartRecordingWithUndeterminedPermission() {
        mockPermission.status = .notDetermined
        mockPermission.requestAccessResult = true
        service.checkPermission()

        let expectation = XCTestExpectation(description: "Status updates to .recording")
        let cancellable = service.$status
            .sink { status in
                if status == .recording {
                    expectation.fulfill()
                }
            }
        addTeardownBlock { cancellable.cancel() }

        service.startRecording()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockPermission.requestAccessCalled)
        XCTAssertTrue(mockEngine.startCalled)
        XCTAssertEqual(service.status, .recording)
    }
}
