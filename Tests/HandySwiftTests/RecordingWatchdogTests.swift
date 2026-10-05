import XCTest
@testable import HandySwift

final class RecordingWatchdogTests: XCTestCase {
    private let policy = RecordingWatchdog(startedAt: 100, noInputTimeoutMs: 15_000, maxRecordingMs: 300_000)

    func testMissingInputDiscardsAtBoundary() {
        XCTAssertEqual(policy.action(now: 114.999, lastInputAt: nil), .none)
        XCTAssertEqual(policy.action(now: 115, lastInputAt: nil), .discard)
    }

    func testSilentCallbacksKeepRecordingButDisconnectedInputTimesOut() {
        XCTAssertEqual(policy.action(now: 130, lastInputAt: 129), .none)
        XCTAssertEqual(policy.action(now: 144, lastInputAt: 129), .discard)
    }

    func testCeilingTranscribesAndTakesPrecedenceOverInputTimeout() {
        XCTAssertEqual(policy.action(now: 399.999, lastInputAt: 399), .none)
        XCTAssertEqual(policy.action(now: 400, lastInputAt: 399), .transcribe)
        XCTAssertEqual(policy.action(now: 400, lastInputAt: nil), .transcribe)
    }

    func testGuardsCanBeDisabledIndependently() {
        let noCeiling = RecordingWatchdog(startedAt: 100, noInputTimeoutMs: 15_000, maxRecordingMs: 0)
        XCTAssertEqual(noCeiling.action(now: 500, lastInputAt: 499), .none)
        XCTAssertEqual(noCeiling.action(now: 500, lastInputAt: nil), .discard)
        let onlyCeiling = RecordingWatchdog(startedAt: 100, noInputTimeoutMs: 0, maxRecordingMs: 300_000)
        XCTAssertEqual(onlyCeiling.action(now: 115, lastInputAt: nil), .none)
        XCTAssertEqual(onlyCeiling.action(now: 400, lastInputAt: nil), .transcribe)
        let disabled = RecordingWatchdog(startedAt: 100, noInputTimeoutMs: 0, maxRecordingMs: 0)
        XCTAssertEqual(disabled.action(now: 10_000, lastInputAt: nil), .none)
    }

    func testLegacySettingsAndHandyNetFields() throws {
        let decoder = JSONDecoder()
        let defaults = try decoder.decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults.noInputTimeoutMs, 15_000)
        XCTAssertEqual(defaults.maxRecordingMs, 300_000)
        let settings = try decoder.decode(Settings.self, from: Data("{\"noInputTimeoutMs\":0,\"maxRecordingMs\":60000}".utf8))
        XCTAssertEqual(settings.noInputTimeoutMs, 0)
        XCTAssertEqual(settings.maxRecordingMs, 60_000)
        let invalid = try decoder.decode(Settings.self, from: Data("{\"noInputTimeoutMs\":-1,\"maxRecordingMs\":-1}".utf8))
        XCTAssertEqual(invalid.noInputTimeoutMs, 0)
        XCTAssertEqual(invalid.maxRecordingMs, 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(json["noInputTimeoutMs"] as? Int, 0)
        XCTAssertEqual(json["maxRecordingMs"] as? Int, 60_000)
    }
}
