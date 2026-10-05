import XCTest
@testable import HandySwift

final class CancelChordTests: XCTestCase {
    func testDefaultsMatchLatestHandyNetAndRoundTrip() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.cancelChordHotkey, "Alt+Shift+X")
        XCTAssertTrue(settings.cancelChordEnabled)
        XCTAssertEqual(settings.cancelChordShortcut, .cancelDefault)
        XCTAssertEqual(settings.cancelChordShortcut?.symbols, "⌥⇧X")
        let copy = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(copy.cancelChordHotkey, settings.cancelChordHotkey)
        XCTAssertEqual(copy.cancelChordEnabled, settings.cancelChordEnabled)
    }

    func testOldDefaultMigratesOnDiskAndRetainsUnknownFieldsAndDisabledState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        try Data("{\"cancelChordHotkey\":\"ctrl+shift+x\",\"cancelChordEnabled\":false,\"hotkey\":\"Alt+D\",\"newerField\":42}".utf8).write(to: url)
        let settings = Settings.load(from: url)
        XCTAssertEqual(settings.cancelChordHotkey, "Alt+Shift+X")
        XCTAssertFalse(settings.cancelChordEnabled)
        XCTAssertNil(settings.cancelChordShortcut)
        XCTAssertEqual(settings.hotkey, "Alt+D")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["cancelChordHotkey"] as? String, "Alt+Shift+X")
        XCTAssertEqual(saved["cancelChordEnabled"] as? Bool, false)
        XCTAssertEqual(saved["newerField"] as? Int, 42)
        XCTAssertEqual(Settings.load(from: url).cancelChordHotkey, "Alt+Shift+X")
    }

    func testCustomChordIsNotMigratedOrRewritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("{\"cancelChordHotkey\":\"Ctrl+Alt+K\",\"cancelChordEnabled\":true}".utf8)
        try data.write(to: url)
        let settings = Settings.load(from: url)
        XCTAssertEqual(settings.cancelChordHotkey, "Ctrl+Alt+K")
        XCTAssertEqual(settings.cancelChordShortcut, Shortcut("Ctrl+Alt+K"))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testExistingInstallPersistsNewDefaultsWithoutDroppingOtherKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"newerField\":42}".utf8).write(to: url)
        XCTAssertEqual(Settings.load(from: url).cancelChordShortcut, .cancelDefault)
        let data = try Data(contentsOf: url)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(saved["cancelChordHotkey"] as? String, "Alt+Shift+X")
        XCTAssertEqual(saved["cancelChordEnabled"] as? Bool, true)
        XCTAssertEqual(saved["newerField"] as? Int, 42)
        _ = Settings.load(from: url)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testInvalidChordFallsBackWithoutReplacingSavedCustomValue() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{\"cancelChordHotkey\":\"invalid\"}".utf8))
        XCTAssertEqual(settings.cancelChordHotkey, "invalid")
        XCTAssertEqual(settings.cancelChordShortcut, .cancelDefault)
    }
}
