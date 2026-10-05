import Foundation
import CoreFoundation
import Darwin

/// A kernel-held lock survives stale files and is released even after a crash.
/// Secondary processes send commands over a per-user local message port.
final class SingleInstance {
    enum Command: Int32 {
        case toggle = 1, cancel, show

        init?(argument: String) {
            switch argument {
            case "--toggle-transcription": self = .toggle
            case "--cancel": self = .cancel
            case "--show": self = .show
            default: return nil
            }
        }
    }

    let isPrimary: Bool
    private let descriptor: Int32
    private let name: String
    private var port: CFMessagePort?
    private var handler: ((Command) -> Void)?

    init(directory: URL, name: String = "com.user.handyswift.commands.\(getuid())") throws {
        self.name = name
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("instance.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Self.systemError() }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            isPrimary = true
        } else {
            let code = errno
            guard code == EWOULDBLOCK else {
                close(fd)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            }
            isPrimary = false
        }
        descriptor = fd
    }

    func listen(_ handler: @escaping (Command) -> Void) throws {
        precondition(isPrimary)
        self.handler = handler
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        var shouldFree = DarwinBoolean(false)
        guard let port = CFMessagePortCreateLocal(nil, name as CFString, { _, id, _, info in
            guard let info, let command = Command(rawValue: id) else { return nil }
            let owner = Unmanaged<SingleInstance>.fromOpaque(info).takeUnretainedValue()
            owner.handler?(command)
            return Unmanaged.passRetained(Data([1]) as CFData)
        }, &context, &shouldFree) else {
            throw NSError(domain: "HandySwift", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open the local command listener."])
        }
        self.port = port
        CFMessagePortSetDispatchQueue(port, .main)
    }

    func forward(_ command: Command) throws {
        precondition(!isPrimary)
        // Another process may have claimed the lock just before opening its listener.
        var remote: CFMessagePort?
        for _ in 0..<20 {
            remote = CFMessagePortCreateRemote(nil, name as CFString)
            if remote != nil { break }
            usleep(100_000)
        }
        guard let remote else {
            throw NSError(domain: "HandySwift", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Handy Swift is running but its command listener is unavailable."])
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, command.rawValue, nil, 2, 2,
                                             CFRunLoopMode.defaultMode.rawValue, &reply)
        let acknowledgement = reply?.takeRetainedValue()
        guard status == kCFMessagePortSuccess, acknowledgement != nil else {
            throw NSError(domain: "HandySwift", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "The running Handy Swift did not acknowledge the command."])
        }
    }

    deinit {
        if let port { CFMessagePortInvalidate(port) }
        close(descriptor)
        // Never unlink the lock: a concurrent opener could otherwise lock another inode.
    }

    private static func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
