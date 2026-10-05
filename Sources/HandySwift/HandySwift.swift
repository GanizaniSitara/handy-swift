import AppKit

@main
struct HandySwiftApp {
    static func main() {
        // Headless check of ASR + post-processing (everything but mic and typing):
        //   HandySwift --transcribe <audio file>
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--transcribe" {
            Task {
                do {
                    let raw = try await Transcriber().transcribe(file: URL(fileURLWithPath: args[2]))
                    print(Dictation.postProcess(raw, Settings.load()).text)
                    exit(0)
                } catch {
                    FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
                    exit(1)
                }
            }
            dispatchMain()
        }

        let command = args.count == 2 ? SingleInstance.Command(argument: args[1]) : nil
        guard args.count == 1 || command != nil else {
            FileHandle.standardError.write(Data("Usage: HandySwift [--show | --toggle-transcription | --cancel | --transcribe <audio file>]\n".utf8))
            exit(1)
        }
        do {
            // Acquire ownership before loading settings/history, claiming the marker or registering hotkeys.
            let instance = try SingleInstance(directory: Settings.directory)
            guard instance.isPrimary else {
                try instance.forward(command ?? .show)
                return
            }
            let app = NSApplication.shared
            let delegate = AppDelegate()
            delegate.initialCommand = command
            try instance.listen { [weak delegate] in delegate?.handle($0) }
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime((instance, delegate)) { app.run() }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
