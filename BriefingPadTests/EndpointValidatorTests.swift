import XCTest
@testable import BriefingPad

final class EndpointValidatorTests: XCTestCase {

    func testHTTPSAllowedForAnyHost() throws {
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "https://api.openai.com/v1"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "https://example.com"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "https://1.1.1.1"))
    }

    func testHTTPAllowedForLocalhost() throws {
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://localhost:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://127.0.0.1:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://[::1]:11434"))
    }

    func testHTTPAllowedForLocalDomains() throws {
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://my-server.local:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://ai-box.local"))
    }

    func testHTTPAllowedForPrivateIPv4() throws {
        // 10.0.0.0/8
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://10.0.0.5:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://10.255.255.255"))

        // 172.16.0.0/12
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://172.16.0.1:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://172.31.255.255:11434"))

        // 192.168.0.0/16
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://192.168.1.10:11434"))

        // 100.64.0.0/10
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://100.64.0.1:11434"))
        XCTAssertNoThrow(try EndpointValidator.validate(urlString: "http://100.127.255.255"))
    }

    func testHTTPBlockedForExternalHosts() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://example.com"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://8.8.8.8"))
    }

    func testHTTPBlockedForOtherIPv6() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://[fe80::1]"))
    }

    func testUserinfoProhibited() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "https://user:pass@example.com"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://user@localhost"))
    }

    func testBlockedSpecialIPv4() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://0.0.0.0"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://255.255.255.255"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "http://224.0.0.1")) // Multicast
    }

    func testUnsupportedSchemes() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "ftp://example.com"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "ws://localhost"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "javascript:alert(1)"))
        XCTAssertThrowsError(try EndpointValidator.validate(urlString: "file:///tmp"))
    }

    func testNormalization() throws {
        let url1 = try EndpointValidator.validate(urlString: "https://api.openai.com/v1/")
        XCTAssertEqual(url1.absoluteString, "https://api.openai.com/v1")

        let url2 = try EndpointValidator.validate(urlString: " http://localhost:11434 ")
        XCTAssertEqual(url2.absoluteString, "http://localhost:11434")
    }
}
