# Handy Swift

A native macOS dictation app: press a hotkey, speak, and the text is typed into the window you were in. Speech recognition runs on-device (NVIDIA Parakeet TDT v3 on Apple's Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio)), so audio never leaves the machine.

Handy Swift is a Swift rewrite of [Handy](https://github.com/cjpais/Handy) for macOS. It brings the reliability work from [Handy.NET](https://github.com/GanizaniSitara/handy-dotnet), the Windows port, to the Mac.

## Why another Handy

Upstream Handy on macOS pastes with a simulated Cmd+V. A synthetic modifier like that can collide with other tools that watch the keyboard, which can leave the system's modifier state confused. Handy Swift never synthesises modifier keys:

- The hotkey is read through a session event tap. Handy only observes keys and swallows its own chords.
- Text is typed as Unicode key events with empty modifier flags. A physically held key can't turn a character into a shortcut, and terminals and TUIs that intercept paste still receive the text.

## Features

- **Ctrl+Space** starts and stops dictation, and **Esc** cancels it at any point, including mid-transcription.
- **Recording safeguards.** A microphone that stops delivering audio is discarded after 15 seconds. Recordings stop and transcribe automatically after five minutes. Both limits can be changed or disabled in Advanced settings; silent audio does not trigger the no-input timeout.
- **Single instance.** Opening Handy again shows the running app's settings. Command-line controls forward to that same instance, keeping one hotkey listener and one recording session.
- **Focus guard.** Handy records the window that had focus when you started. If focus moved, it brings that window back before typing. If that fails, the text goes to the clipboard instead of into the wrong app. It re-checks the window before every character.
- **Option+Shift+C** copies the last transcript. **Option+Shift+V** retypes it into the focused window.
- **Transcript history.** Open **History…** from the menu bar to copy, delete or clear saved transcripts. The latest 50 are kept by default, including transcripts recovered to the clipboard; the last transcript remains available after restarting.
- **Filler-word and stutter filter**, language-aware and ported from upstream Handy.
- **Domain terms.** Context-gated phrase corrections, for example "service now" → "ServiceNow", but only near "ticket". They use the same JSON shape as Handy.NET.
- **Recording pill.** A small overlay at the bottom of the screen shows live level bars. It never takes focus.
- **Menu-bar icon.** A disc with an "H" that is blue when idle, red while recording and green while transcribing.
- **Diagnostics.** The log gets one line per dictation (timings, target window, outcome), plus a crash marker. Log location: `~/Library/Logs/HandySwift/handy.log`.

## Install

1. Download the DMG from [Releases](../../releases) and drag **HandySwift** to Applications.
2. The build is **not notarized**. On first launch macOS will block it. Open **System Settings → Privacy & Security** and click **Open Anyway**. Alternatively, run:
   ```
   xattr -dr com.apple.quarantine /Applications/HandySwift.app
   ```
3. Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility). Handy needs it to read the hotkey and type.
4. Grant **Microphone** on your first dictation.

On first launch Handy downloads the speech model, about 470 MB, from Hugging Face. After that it runs offline.

Requires macOS 14 or later on Apple silicon.

## Settings

Use **Settings…** in the menu-bar menu (shortcut, microphone, typing, language, domain terms, history limit, open at login). Settings are stored in `~/Library/Application Support/HandySwift/settings.json` and are re-read on every dictation.

```json
{
  "charDelayMs": 3,
  "pasteFocusPolicy": "RestoreAndPaste",
  "appLanguage": "en",
  "customFillerWords": null,
  "domainCorrections": [
    {
      "to": "ServiceNow",
      "variants": ["service now", "snow"],
      "requiredContext": ["ticket", "incident"],
      "blockedContext": [],
      "caseSensitive": false
    }
  ]
}
```

- `charDelayMs`: the pause between typed characters. Raise it if a terminal drops characters.
- `pasteFocusPolicy`: `RestoreAndPaste` (the default), `RefuseAndCopy` or `PasteAnyway`.
- `customFillerWords`: `null` uses the language defaults, and `[]` turns filler removal off.
- `historyLimit`: number of recent transcripts to retain (default 50, minimum 1). Applying a smaller limit deletes older entries. Transcripts are saved in `history.json` beside settings, using Handy.NET's `Text` / `TimestampUtc` format. History contains transcript text only, with no audio retention.
- `noInputTimeoutMs`: discard recording after this long without audio callbacks (default 15000). `maxRecordingMs`: stop and transcribe at this duration (default 300000). Zero disables either guard. Limits are captured when recording starts and checked once a second.

See [FEATURES.md](FEATURES.md) for the local Handy.NET parity audit and remaining work.

## Build from source

You need Xcode 16 or later.

```
./build-app.sh            # build/HandySwift.app (signs with an Apple Development identity if you have one)
INSTALL=1 ./build-app.sh  # also copies to ~/Applications
./make-dmg.sh             # ad-hoc signed release DMG in build/
swift test                # unit tests
```

`HandySwift --transcribe <audio file>` runs the recognition and post-processing pipeline headless. Use it to check the model without a microphone.

To control the running app from a script, use its executable:

```sh
~/Applications/HandySwift.app/Contents/MacOS/HandySwift --toggle-transcription
~/Applications/HandySwift.app/Contents/MacOS/HandySwift --cancel
~/Applications/HandySwift.app/Contents/MacOS/HandySwift --show
```

If no instance is running, these commands launch the app and apply the command. Headless `--transcribe` stays independent and does not claim the app lock or session marker. Run `python3 scripts/test-single-instance.py` to check command forwarding and crash recovery without starting microphone capture.

## License

MIT, see [LICENSE](LICENSE). FluidAudio is Apache-2.0. The Parakeet model is CC-BY-4.0 (NVIDIA).
