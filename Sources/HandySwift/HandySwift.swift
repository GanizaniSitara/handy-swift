import AppKit

@main
struct HandySwiftApp {
    static func main() {
        // Headless check of the ASR path: HandySwift --transcribe <audio file>
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--transcribe" {
            Task {
                do {
                    print(try await Transcriber().transcribe(file: URL(fileURLWithPath: args[2])))
                    exit(0)
                } catch {
                    FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
                    exit(1)
                }
            }
            dispatchMain()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
