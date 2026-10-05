#!/usr/bin/env python3
"""Exercise the actual lock/IPC code in separate processes, without mic, history or hotkeys."""
import select
import subprocess
import tempfile
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
harness = r'''
import Foundation

@main struct Harness {
    static func report(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
    static func main() throws {
        let args = CommandLine.arguments
        let owner = try SingleInstance(directory: URL(fileURLWithPath: args[1]), name: args[2])
        if args[3] == "listen" {
            guard owner.isPrimary else { exit(1) }
            report("owner")
            // Deliberately expose the lock-before-listener startup race.
            Thread.sleep(forTimeInterval: 0.75)
            try owner.listen { report("command=\($0.rawValue)") }
            report("ready")
            withExtendedLifetime(owner) { dispatchMain() }
        } else {
            guard !owner.isPrimary else { exit(2) }
            try owner.forward(SingleInstance.Command(argument: args[3])!)
            report("acknowledged")
        }
    }
}
'''


def line(process):
    assert select.select([process.stdout], [], [], 8)[0], "primary did not respond"
    result = process.stdout.readline().decode().strip()
    assert result, f"primary exited: {process.poll()}"
    return result


with tempfile.TemporaryDirectory(prefix="handy-instance-test-") as temporary:
    temp = Path(temporary)
    source = temp / "Harness.swift"
    source.write_text(harness)
    executable = temp / "harness"
    subprocess.run(["swiftc", "-parse-as-library", str(root / "Sources/HandySwift/SingleInstance.swift"),
                    str(source), "-o", str(executable)], check=True)
    base = [str(executable), str(temp / "data"), "handy.test." + uuid.uuid4().hex]
    primary = subprocess.Popen(base + ["listen"], stdout=subprocess.PIPE, bufsize=0)
    try:
        assert line(primary) == "owner"
        for index, command in enumerate(["--toggle-transcription", "--cancel", "--show"], start=1):
            result = subprocess.run(base + [command], capture_output=True, text=True, timeout=8)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == "acknowledged"
            if index == 1:
                assert line(primary) == "ready"
            assert line(primary) == f"command={index}"
        primary.kill()
        primary.wait(timeout=5)
        assert (temp / "data/instance.lock").exists()
        primary = subprocess.Popen(base + ["listen"], stdout=subprocess.PIPE, bufsize=0)
        assert line(primary) == "owner"
        assert line(primary) == "ready"
        result = subprocess.run(base + ["--show"], capture_output=True, text=True, timeout=8)
        assert result.returncode == 0, result.stderr
        assert line(primary) == "command=3"
        print("PASS: command forwarding, startup race, duplicate exclusion and crash recovery")
    finally:
        if primary.poll() is None:
            primary.kill()
        primary.wait(timeout=5)
