import XCTest
import Cocoa
@testable import HandySwift

final class HotkeyTapTests: XCTestCase {
    private let recovery: CGEventFlags = [.maskAlternate, .maskShift]

    private func event(_ key: CGKeyCode, down: Bool = true, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        event.flags = flags
        return event
    }

    func testActiveCancelConsumesBothEdgesEvenAfterModifiersReleasedAndIgnoresRepeat() {
        let tap = HotkeyTap(), done = expectation(description: "cancel once")
        tap.isActive = { true }
        tap.onCancel = { done.fulfill() }
        XCTAssertTrue(tap.handle(type: .keyDown, event: event(7, flags: recovery)) == nil)
        let repeated = event(7, flags: recovery)
        repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(tap.handle(type: .keyDown, event: repeated) == nil)
        tap.isActive = { false }
        XCTAssertTrue(tap.handle(type: .keyUp, event: event(7, down: false)) == nil)
        wait(for: [done], timeout: 1)
        XCTAssertFalse(tap.handle(type: .keyDown, event: event(7, flags: recovery)) == nil)
        XCTAssertFalse(tap.handle(type: .keyUp, event: event(7, down: false)) == nil)
    }

    func testDisabledChordPassesThroughButEscapeStillCancels() {
        let tap = HotkeyTap(), done = expectation(description: "escape")
        tap.isActive = { true }
        tap.cancelChord = nil
        tap.onCancel = { done.fulfill() }
        XCTAssertFalse(tap.handle(type: .keyDown, event: event(7, flags: recovery)) == nil)
        XCTAssertFalse(tap.handle(type: .keyUp, event: event(7, down: false)) == nil)
        XCTAssertTrue(tap.handle(type: .keyDown, event: event(53)) == nil)
        XCTAssertTrue(tap.handle(type: .keyUp, event: event(53, down: false)) == nil)
        wait(for: [done], timeout: 1)
    }

    func testCustomChordAndExactModifierMatching() {
        let tap = HotkeyTap(), done = expectation(description: "custom cancel")
        tap.isActive = { true }
        tap.cancelChord = Shortcut("Alt+Shift+D")
        tap.onCancel = { done.fulfill() }
        XCTAssertFalse(tap.handle(type: .keyDown, event: event(7, flags: recovery)) == nil)
        XCTAssertFalse(tap.handle(type: .keyDown, event: event(2, flags: [.maskAlternate, .maskShift, .maskCommand])) == nil)
        XCTAssertTrue(tap.handle(type: .keyDown, event: event(2, flags: recovery)) == nil)
        XCTAssertTrue(tap.handle(type: .keyUp, event: event(2, down: false)) == nil)
        wait(for: [done], timeout: 1)
    }

    func testCopyAndRetypeRemainOptionShiftCAndV() {
        let tap = HotkeyTap()
        let copy = expectation(description: "copy"), retype = expectation(description: "retype")
        tap.onCopyLast = { copy.fulfill() }
        tap.onRetypeLast = { retype.fulfill() }
        for key in [CGKeyCode(8), 9] {
            XCTAssertTrue(tap.handle(type: .keyDown, event: event(key, flags: recovery)) == nil)
            XCTAssertTrue(tap.handle(type: .keyUp, event: event(key, down: false)) == nil)
        }
        wait(for: [copy, retype], timeout: 1)
    }

    func testCancelWinsOverConflictingToggleWhileActive() {
        let tap = HotkeyTap(), done = expectation(description: "cancel instead of toggle")
        tap.isActive = { true }
        tap.dictation = .cancelDefault
        tap.onCancel = { done.fulfill() }
        tap.onToggle = { XCTFail("Cancel must win while active") }
        XCTAssertTrue(tap.handle(type: .keyDown, event: event(7, flags: recovery)) == nil)
        wait(for: [done], timeout: 1)
    }

    func testSuspendedTapPassesRecoveryShortcutsThrough() {
        let tap = HotkeyTap()
        tap.isActive = { true }
        tap.suspended = true
        for key in [CGKeyCode(7), 8, 9] {
            XCTAssertFalse(tap.handle(type: .keyDown, event: event(key, flags: recovery)) == nil)
            XCTAssertFalse(tap.handle(type: .keyUp, event: event(key, down: false)) == nil)
        }
    }

    func testCtrlSpaceStillTogglesDictation() {
        let tap = HotkeyTap(), done = expectation(description: "ordinary dictation")
        tap.onToggle = { done.fulfill() }
        XCTAssertTrue(tap.handle(type: .keyDown, event: event(49, flags: [.maskControl])) == nil)
        XCTAssertTrue(tap.handle(type: .keyUp, event: event(49, down: false)) == nil)
        wait(for: [done], timeout: 1)
    }
}
