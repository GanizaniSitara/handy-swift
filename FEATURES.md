# Handy.NET parity audit

Audited 2026-10-04, with cancel-shortcut update 2026-10-05 against the local Handy.NET checkout at `e878835`:
`src/Handy/Services/*`, `App.xaml.cs`, `MainWindow.xaml` and its code-behind,
`HistoryWindow`, `HelpWindow`, `RecordingOverlay`, `FEATURES.md`, and `README.md`.
Swift baseline: `4ee5042`, plus the history implementation in v0.3.0.
This is a source audit; it does not imply live microphone or injection validation.

Working-tree update 2026-10-05 (after v0.3.0): recording watchdogs and
single-instance/CLI forwarding are implemented. These additions are not yet in
the public release. All 49 unit tests pass; separate-process IPC checks cover
commands, startup races and crash recovery. An isolated harness using the actual
Dictation source verified discard, ceiling transcription and timer teardown.
The local Apple-Development-signed 0.3.2-dev app is installed: duplicate launch,
show, live recording toggle/cancel (unchanged history) and the Advanced UI were
checked. The model and hotkey loaded without new permission prompts.

The 2026-10-05 shortcut update matches Handy.NET DCT-034: Option+Shift+X is
the alternate cancel chord, alongside existing Option+Shift+C/V recovery keys.
The alternate chord is configurable/disableable; old Ctrl+Shift+X defaults
migrate while custom chords and the enabled state are preserved. Escape remains
available, and cancellation takes priority over a conflicting trigger while active.
Ctrl+Space followed by Option+Shift+X was verified through the installed global
tap: recording returned to idle with history unchanged. The live settings persist
`cancelChordHotkey=Alt+Shift+X` and `cancelChordEnabled=true`; the General page
shows all four shortcuts. C/V routing and matching key-up consumption are covered
by regression tests.

Validation for v0.3.0: `swift test` passed all 29 tests (seven history
tests), and a real AppKit preview of the history view was checked with synthetic
transcripts in an isolated temporary directory. Screenshots covered wrapped text,
Unicode, the clear confirmation, and the empty state. Selecting/deleting one row
and confirming Clear all both persisted the expected JSON. Live
dictation-to-history validation is still pending; this preview did not load the
speech model, register hotkeys, or touch the user's history.

**Present** means implemented; **Partial** means a usable equivalent has gaps;
**Missing** means suitable for a Mac implementation; **N/A** means the Windows
mechanism has no direct Mac equivalent or conflicts with the requirement to avoid
synthetic modifier keys. Defaults below are Handy.NET's, not Swift's.

## Every Handy.NET setting

The following covers all 52 persisted `AppSettings` properties. Runtime-only
`FilePath` is excluded. Keep the same camelCase names when adding Swift settings.
Both serializers currently drop unknown JSON fields on save (despite Handy.NET's
class comment claiming they round-trip).

### Hotkeys and destinations

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `settingsVersion` | `3` | Missing: explicit schema version and migrations. |
| `hotkey` | `Ctrl+Space` | Present: configurable session event tap; consumes its own down/up events without injecting modifiers. |
| `cancelHotkey` | `Escape` | Partial: Escape cancels recording/decoding, but cannot be rebound. |
| `cancelChordHotkey` | `Alt+Shift+X` | Present: Option+Shift+X alternate cancel, configurable in General settings. Legacy Ctrl+Shift+X defaults migrate without replacing custom chords. |
| `cancelChordEnabled` | `true` | Present: disabling the alternate chord leaves Escape available. |
| `taskCaptureHotkey` | `Ctrl+Shift+Space` | Missing: dedicated capture destination. |
| `taskCaptureInbox` | `%LOCALAPPDATA%\Handy\task-inbox` | Missing: Mac inbox and consumer need a decision. The port must write atomic capture envelopes, not create task tickets directly. |
| `copyLastHotkey` | `Alt+Shift+C` | Partial: fixed Option+Shift+C and menu action; history restores the last transcript after restart. |
| `retypeLastHotkey` | `Alt+Shift+V` | Partial: fixed Option+Shift+V and menu action; cannot be rebound. |
| `pushToTalk` | `false` | Missing: only toggle mode is implemented. |

### Typing and clipboard

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `pasteMethod` | `Direct` | Partial: direct Unicode typing only. `None` is a suitable addition. Windows CtrlV/ShiftInsert/CtrlShiftV methods are N/A; a simulated Cmd+V would violate this app's modifier constraint. |
| `pasteDelayMs` | `50` | N/A for current Direct-only mode: .NET uses this for clipboard/chord timing, not Unicode typing. Consider an explicit delivery delay separately. |
| `directCharDelayMs` | `0` | Partial: Swift exposes `charDelayMs` (default 3 ms), a different JSON field. Needs compatibility migration/alias. |
| `directCharDelayMsCitrix` | `2` | Missing: separate per-character delay and Citrix detection on Mac. Windows process-name matching cannot be copied unchanged. |
| `appendTrailingSpace` | `false` | Missing. |
| `clipboardHandling` | `DontModify` | Partial: successful direct typing leaves the clipboard alone; focus-failure copies the remainder. No configurable `CopyToClipboard` behavior. Clipboard save/restore around chord paste is N/A for direct typing. |
| `alwaysCopyTranscriptToClipboard` | `false` | Missing: leave a successful full transcript on the clipboard. Must preserve remainder recovery when typing is interrupted. |
| `pasteFocusPolicy` | `RestoreAndPaste` | Present: RestoreAndPaste, RefuseAndCopy, PasteAnyway; Accessibility window identity and per-character rechecks. |
| `autoSubmitKey` | `None` | Missing: Enter is suitable with a focus recheck. CtrlEnter needs an explicit decision because it synthesizes a modifier. |

### Audio, feedback, and recording guards

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `microphoneDeviceName` | empty/system default | Present: native device picker and device selection at capture start. |
| `beepOnStart` | `false` | Missing: independent feedback toggle. |
| `beepOnStop` | `false` | Missing. |
| `beepOnCancel` | `false` | Missing. |
| `beepVolume` | `0.5` | Missing: configurable tone volume. Existing error beeps are not recording feedback. |
| `vadEnabled` | `true` | Missing: explicit speech detection/edge trim before ASR; the 300 ms minimum recording guard is not VAD. |
| `vadThreshold` | `0.3` | Missing. |
| `vadPaddingMs` | `500` | Missing. |
| `vadMaxSilenceMs` | `30000` | Missing setting, but also unwired in the audited .NET runtime: only settings load/UI/save references exist. Its comment describes segment closure; the actual edge-trim call uses its fixed 480 ms hangover default. Do not copy the comment as a working feature. |
| `noInputTimeoutMs` | `15000` | Present: discard recording when audio callbacks stall, measuring from capture start or latest callback; silent samples count as input. Zero disables; Advanced settings. |
| `maxRecordingMs` | `300000` | Present: stop and transcribe at the hard ceiling. Zero disables; Advanced settings. Both guards use monotonic time and check once a second. |
| `preRollMs` | `250` | Missing: .NET captures continuously and retains a pre-trigger ring buffer; Swift starts capture on demand. |
| `postRollMs` | `200` | Missing: grace capture after release/stop. |
| `saveLastAudioForDiagnostics` | `false` | Missing: opt-in last raw/trimmed capture export. |
| `backgroundRecognitionEnabled` | `false` | Missing: speculative pause decoding and final prefix/tail splice, with cancellation protection. |
| `backgroundPauseTriggerMs` | `600` | Missing. |
| `backgroundMinNewSpeechMs` | `1500` | Missing. |
| `backgroundSilenceBarThreshold` | `0.15` | Missing. |

### Interface, startup, and history

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `autostart` | `false` | Partial: Open at Login works through SMAppService and appears in settings/menu; no JSON field. Native registration remains the source of truth. |
| `startHidden` | `true` | Partial: always starts as a menu-bar accessory; no option to show settings at launch. |
| `showTrayIcon` | `true` | Partial: menu-bar icon always shown. Hiding it should wait for CLI/single-instance recovery so settings remain accessible. |
| `overlayPosition` | `Bottom` | Partial: nonactivating, click-through pill with five live bars, fixed bottom placement; Top/None missing. |
| `historyLimit` | `50` | Present in current history work: latest N entries, minimum one; no time-based retention. Atomic `history.json`, newest-first browser, copy/delete/clear confirmation, settings limit and restart recovery. |

### Models and post-processing

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `transcriptionBackend` | `Parakeet` | Partial: Parakeet TDT v3 via FluidAudio/CoreML/Neural Engine; no Whisper backend or selector. .NET's ONNX cache is not interchangeable with CoreML models. |
| `parakeetVariant` | `Auto` | Missing: v3 fixed; v2/auto selection absent. |
| `whisperModel` | `base` | Missing: no Whisper models/download UI. |
| `whisperVocabularyPromptEnabled` | `false` | Missing; depends on a Whisper backend. Parakeet domain correction is post-processing, not recognizer biasing. |
| `whisperCarryInitialPrompt` | `true` | Missing; depends on a Whisper backend. |
| `appLanguage` | `en` | Present: selects the language-specific filler filter; does not translate the UI or force the ASR language. |
| `customFillerWords` | `null` | Present: null = defaults, empty = disabled, nonempty = custom list; settings UI. |
| `domainCorrections` | empty list | Present: enabled/from/to/variants/requiredContext/blockedContext/caseSensitive/notes JSON, filler-first processing and applied-rule logging. Partial editor: notes are retained but not editable. |

### Logging

| JSON field | .NET default | Swift status and behavior |
|---|---|---|
| `logDisplayVerbosity` | `Normal` | Missing: log page reads the last 400 lines; no tier filter or live subscription. |
| `logFileVerbosity` | `Debug` | Missing: no file verbosity filter. Lifecycle lines currently always pass through. |

## Features outside settings

| Handy.NET feature | Swift status and Mac implications |
|---|---|
| Settings sidebar General/Advanced/Models/Log, staged edits and Apply | Present. No independent backend/download controls yet. |
| Tray state colors, Settings/History/Copy Last/Cancel/Exit | Partial: state colors, Settings, History, Copy Last, Retype Last, Log, login, Quit; Cancel menu action missing. |
| JSON history interoperability | Present in current history work: `Text` and `TimestampUtc` keys; accepts ISO-8601 timestamps with/without fractional seconds. Settings keys use camelCase instead. |
| Cancel during decoding leaves no history/paste/capture | Present: generation check before delivery/history. Native inference finishes in the background. |
| In-app Help and Domain Terms guide | Missing: Help currently opens a browser README. Offline in-app guidance is suitable. |
| Single-instance mutex and command forwarding | Present: kernel-held file lock with per-user local message port; secondary launches show settings without loading a second model, claiming the marker or installing another hotkey tap. Lock releases on clean exit or crash. |
| `--toggle-transcription`, `--cancel`, `--show` | Present: acknowledged forwarding to the running instance, or launch and apply when no instance exists. Finder reopens show settings. |
| `--start-hidden`, `--no-tray` | Partial/N/A: hidden startup is already the default; no override flags. Tray suppression needs a safe recovery route. |
| `--transcribe-file`, `--data-dir` isolation | Partial: Swift `--transcribe <audio file>` prints post-processed text to stdout, but no flag alias, isolated settings directory, or `last-transcript.txt`. Does not add runtime history or mutate the session marker. |
| `--bench-additive`, split selection, latency/Vocabulary A/B/WER benches | Missing: suitable developer tools after backend/speculative work. |
| Model discovery, environment override, reusable upstream cache | Partial: automatic CoreML download/cache through FluidAudio. ONNX/GGML discovery paths and `HANDY_MODEL_DIR` are N/A for current CoreML backend. |
| Download progress, explicit download actions, active/pending model status | Partial: model loading/failure label and Show in Finder; no progress/retry/selection UI. |
| Paste destination verification and mid-injection guard | Present using AX app/window identity; checks every character. Remote windows within one Citrix viewer cannot be distinguished reliably by either platform's outer-window guard. |
| Refused-input detection / elevated-window diagnosis | N/A: Windows SendInput count/UIPI access-denied codes do not exist for CGEvent posting. Partial Mac equivalent: TCC preflight is present; posted events cannot guarantee target acceptance. |
| Stuck-trigger recovery after missing key-up | Partial: tap re-enables after timeout/user input; no physical-key-state recovery or latch polling. Essential with future push-to-talk. |
| Crash marker, session identity, phase, heartbeat, clean exit | Partial: marker with PID/time/phase and clean SIGTERM/quit; no session UUID/version/heartbeat. Headless transcription does not claim the marker. |
| Unfilterable lifecycle logging | Present: no log filter exists. Preserve lifecycle bypass when adding tiers. |
| Per-dictation diagnostics | Partial: recording/ASR durations, sample count/peak, mic/target, corrections and delivery outcome; lacks separate VAD/post/history/paste timings and engine/version fields. |
| Log rotation while running, five generations at 500,000 bytes | Missing: Swift log currently grows without rotation. |
| Git-derived version in title/footer | Partial: packaged semantic version in settings footer; no commit-count/SHA/dirty suffix. |
| Task capture envelope with source and foreground metadata | Missing: atomic `.capture.json` containing schema/capture ID, UTC timestamps, source, destination, raw/final transcript and foreground metadata; copy fallback on write failure. Windows HWND/class fields need Mac equivalents. |
| Diagnostic audio exports | Missing: opt-in raw capture and ASR input WAVs. |

## Scope corrections

- Mute while recording is absent from Handy.NET (its FEATURES.md explicitly lists
  this as upstream-only). It is an additional Mac feature, not a parity gap.
- Neither Handy.NET nor this app has an external API, Apple Speech selector,
  LLM cleanup, signed updater, or UI localization. These are separate product
  decisions; the latest task handoff prioritizes parity with Handy.NET.
- Neural Engine acceleration is already a Mac improvement. Copying the Windows
  CPU-only runtime is unnecessary.
- Preserve the rule against fake modifier injection and the stable local
  Apple Development signing identity. Do not publish without approval.

## Suggested implementation order

1. Finish/validate history, including retention changes, persistence, and a real
   window screenshot. Keep transcripts and screenshots out of the public repo.
2. Recording watchdogs and single-instance/CLI forwarding are implemented;
   next, configurable recovery/cancel chords and push-to-talk with physical-key recovery.
3. Always-copy, trailing space, delivery delay/None mode, Top/None overlay,
   audio tones, offline help, and bounded logs. Preserve focus-failure recovery.
4. Task capture once the Mac inbox/consumer is selected. Do not silently route
   it into the task corpus or use tasks-cli without a consumer design.
5. VAD and pre/post-roll; benchmark soft speech edges and natural pauses before
   enabling speculative prefix/tail recognition.
6. Model choice/Whisper, prompting and developer benchmark parity.
