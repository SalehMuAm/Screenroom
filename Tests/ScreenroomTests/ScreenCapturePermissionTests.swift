import XCTest
@testable import Screenroom

final class ScreenCapturePermissionTests: XCTestCase {
    @MainActor
    func testImmediateDisplayRecordingChecksBroadAccess() {
        var requestCount = 0
        let permission = ScreenCapturePermission(preflight: { false }, request: {
            requestCount += 1
            return false
        })

        XCTAssertThrowsError(try permission.ensure(for: .display, directDisplay: true))
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testAuthorizedImmediateDisplayRecordingDoesNotPrompt() throws {
        let permission = ScreenCapturePermission(preflight: { true }, request: {
            XCTFail("Existing recording access must be reused")
            return false
        })
        try permission.ensure(for: .display, directDisplay: true)
    }

    @MainActor
    func testGrantedAccessDoesNotRequestAgain() throws {
        var requestCount = 0
        let permission = ScreenCapturePermission(preflight: { true }, request: {
            requestCount += 1
            return true
        })

        try permission.ensure(for: .region)
        try permission.ensure(for: .region)

        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testUnavailableAccessRequestsOnlyOnceAcrossAttempts() {
        var requestCount = 0
        let permission = ScreenCapturePermission(preflight: { false }, request: {
            requestCount += 1
            return false
        })

        for _ in 0..<3 {
            XCTAssertThrowsError(try permission.ensure(for: .region)) { error in
                XCTAssertTrue(error is ScreenCapturePermissionError)
            }
        }

        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testAccessGrantedByRequestAllowsCaptureImmediately() throws {
        var granted = false
        let permission = ScreenCapturePermission(preflight: { granted }, request: {
            granted = true
            return true
        })

        try permission.ensure(for: .region)
    }

    @MainActor
    func testLaterApprovalIsRecheckedWithoutAnotherRequest() throws {
        var granted = false
        var requestCount = 0
        let permission = ScreenCapturePermission(preflight: { granted }, request: {
            requestCount += 1
            return false
        })

        XCTAssertThrowsError(try permission.ensure(for: .region))
        granted = true
        try permission.ensure(for: .region)

        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testRequestResultDoesNotReplaceCheckingUsableAccess() {
        let permission = ScreenCapturePermission(preflight: { false }, request: { true })

        XCTAssertThrowsError(try permission.ensure(for: .region))
    }

    @MainActor
    func testSystemPickerSourcesDoNotCheckOrRequestBroadAccess() throws {
        var preflightCount = 0
        var requestCount = 0
        let permission = ScreenCapturePermission(preflight: {
            preflightCount += 1
            return false
        }, request: {
            requestCount += 1
            return false
        })

        try permission.ensure(for: .window)
        try permission.ensure(for: .display)

        XCTAssertEqual(preflightCount, 0)
        XCTAssertEqual(requestCount, 0)
    }
}
