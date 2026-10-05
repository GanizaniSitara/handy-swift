import XCTest
@testable import HandySwift

final class SingleInstanceTests: XCTestCase {
    func testOwnershipAndCleanReleaseWithoutDeletingLockFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: SingleInstance? = try SingleInstance(directory: directory)
        XCTAssertTrue(first!.isPrimary)
        let second = try SingleInstance(directory: directory)
        XCTAssertFalse(second.isPrimary)
        first = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("instance.lock").path))
        let replacement = try SingleInstance(directory: directory)
        XCTAssertTrue(replacement.isPrimary)
        withExtendedLifetime((second, replacement)) {}
    }

    func testLockFailureDoesNotPretendToBePrimary() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        XCTAssertThrowsError(try SingleInstance(directory: file.appendingPathComponent("data")))
    }

    func testCommandsMatchHandyNetAndRejectUnknownFlags() {
        XCTAssertEqual(SingleInstance.Command(argument: "--toggle-transcription"), .toggle)
        XCTAssertEqual(SingleInstance.Command(argument: "--cancel"), .cancel)
        XCTAssertEqual(SingleInstance.Command(argument: "--show"), .show)
        XCTAssertNil(SingleInstance.Command(argument: "--unknown"))
    }
}
