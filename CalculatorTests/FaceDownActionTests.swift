import XCTest
@testable import Calculator

final class FaceDownActionTests: XCTestCase {
    func testPresetsIncludeCalculatorYouTubeAndGmail() {
        XCTAssertTrue(FaceDownAction.allCases.contains(.calculator))
        XCTAssertTrue(FaceDownAction.allCases.contains(.youtube))
        XCTAssertTrue(FaceDownAction.allCases.contains(.gmail))
    }

    func testWebsiteAddsHTTPSForBareHostname() {
        XCTAssertEqual(FaceDownAction.safeWebsite("example.com/path")?.absoluteString,
                       "https://example.com/path")
    }

    func testWebsiteAcceptsHTTPS() {
        XCTAssertEqual(FaceDownAction.safeWebsite("https://example.com/")?.host,
                       "example.com")
    }

    func testWebsiteRejectsUntrustedSchemes() {
        XCTAssertNil(FaceDownAction.safeWebsite("javascript:alert(1)"))
        XCTAssertNil(FaceDownAction.safeWebsite("file:///private/test"))
        XCTAssertNil(FaceDownAction.safeWebsite("http://example.com"))
        XCTAssertNil(FaceDownAction.safeWebsite(""))
    }
}
