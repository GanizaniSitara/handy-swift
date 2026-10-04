import XCTest
@testable import HandySwift

final class ShortcutTests: XCTestCase {
    func testParsesHandyNetNotation() {
        XCTAssertEqual(Shortcut("Ctrl+Space"), Shortcut.dictationDefault)
        XCTAssertEqual(Shortcut("ctrl + shift + d"), Shortcut(keyCode: 2, modifiers: [.maskControl, .maskShift]))
        XCTAssertEqual(Shortcut("Option+F5")?.modifiers, [.maskAlternate])
    }

    func testRoundTripsThroughDescription() {
        for text in ["Ctrl+Space", "Ctrl+Alt+Shift+Cmd+K", "Alt+Shift+C", "Cmd+F12", "Ctrl+`"] {
            XCTAssertEqual(Shortcut(text)?.description, text)
        }
    }

    func testRejectsBareKeysAndUnknownNames() {
        XCTAssertNil(Shortcut("Space"))  // would fire on ordinary typing
        XCTAssertNil(Shortcut("Ctrl+Banana"))
        XCTAssertNil(Shortcut("Ctrl+A+B"))
        XCTAssertEqual(Settings().dictationShortcut, .dictationDefault)
    }
}
