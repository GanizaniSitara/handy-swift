import XCTest
@testable import HandySwift

final class HistoryTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testRetainsNewestEntriesAndReloadsAfterRestart() {
        let history = HistoryService(url: url, limit: 2)
        history.add("first")
        history.add("second")
        history.add("third 🗣️")
        history.add(" \n\t ")
        XCTAssertEqual(history.entries.map(\.text), ["second", "third 🗣️"])
        let reloaded = HistoryService(url: url, limit: 2)
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.entries.map(\.text), ["second", "third 🗣️"])
        XCTAssertEqual(reloaded.entries.last!.timestampUtc.timeIntervalSince1970,
                       history.entries.last!.timestampUtc.timeIntervalSince1970, accuracy: 1)
    }

    func testLimitChangeAndStartupTrimPersist() {
        let history = HistoryService(url: url, limit: 5)
        for text in ["a", "b", "c", "d"] { history.add(text) }
        history.setLimit(2)
        XCTAssertEqual(HistoryService(url: url, limit: 5).entries.map(\.text), ["c", "d"])
        let smaller = HistoryService(url: url, limit: 0)
        XCTAssertEqual(smaller.entries.map(\.text), ["d"])
        XCTAssertEqual(HistoryService(url: url, limit: 5).entries.map(\.text), ["d"])
        smaller.setLimit(-10)
        smaller.add("e")
        XCTAssertEqual(smaller.entries.map(\.text), ["e"])
    }

    func testDeletingOneOfIdenticalTranscriptsAndClearingPersist() {
        let history = HistoryService(url: url, limit: 50)
        history.add("same")
        history.add("same")
        let remainingID = history.entries[1].id
        history.remove(history.entries[0].id)
        XCTAssertEqual(history.entries.map(\.id), [remainingID])
        XCTAssertEqual(HistoryService(url: url, limit: 50).entries.count, 1)
        history.clear()
        XCTAssertTrue(HistoryService(url: url, limit: 50).entries.isEmpty)
    }

    func testReadsHandyNetDatesAndWritesCompatibleKeys() throws {
        let json = """
        [{"Text":"fractional","TimestampUtc":"2026-10-04T10:20:30.1234567Z"},
         {"Text":"seconds","TimestampUtc":"2026-10-04T10:20:31Z"}]
        """
        try Data(json.utf8).write(to: url)
        let history = HistoryService(url: url, limit: 50)
        XCTAssertNil(history.error)
        XCTAssertEqual(history.entries.map(\.text), ["fractional", "seconds"])
        history.add("new")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(Set(rows[0].keys), ["Text", "TimestampUtc"])
        XCTAssertTrue((rows[0]["TimestampUtc"] as? String)?.hasSuffix("Z") == true)
    }

    func testCorruptHistoryIsReportedAndNotOverwrittenOnLoad() throws {
        let invalid = Data("not json".utf8)
        try invalid.write(to: url)
        let history = HistoryService(url: url, limit: 50)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNotNil(history.error)
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    func testFailedSaveKeepsTranscriptAvailableAndReportsError() throws {
        let blocked = directory.appendingPathComponent("file")
        try Data().write(to: blocked)
        let history = HistoryService(url: blocked.appendingPathComponent("history.json"), limit: 50)
        history.add("recover this")
        XCTAssertEqual(history.entries.last?.text, "recover this")
        XCTAssertNotNil(history.error)
    }

    func testExistingSettingsDefaultToFiftyAndLimitUsesHandyNetKey() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(Settings.self, from: Data("{}".utf8)).historyLimit, 50)
        XCTAssertEqual(try decoder.decode(Settings.self, from: Data("{\"historyLimit\":3}".utf8)).historyLimit, 3)
        XCTAssertEqual(try decoder.decode(Settings.self, from: Data("{\"historyLimit\":0}".utf8)).historyLimit, 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any])
        XCTAssertEqual(json["historyLimit"] as? Int, 50)
    }
}
