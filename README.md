# Meeting Recorder

Personal macOS menubar app: captures system audio during a meeting (no bot joins the call),
transcribes it locally after you click Stop, and saves the transcript to your Obsidian vault.
Audio stays local to this project folder.

## Setup

1. Install whisper.cpp: `brew install whisper-cpp`
2. Confirm the binary path: `which whisper-cli`. If it's not `/opt/homebrew/bin/whisper-cli`,
   update `Config.whisperBinaryPath` in `Sources/MeetingRecorder/Config.swift`.
3. Download the **multilingual** model (not the `.en` English-only variant — meetings here
   are a mix of Indonesian and English, and the English-only model produces garbage on
   non-English audio):
   ```bash
   mkdir -p ~/whisper-models
   curl -L -o ~/whisper-models/ggml-base.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
   ```
   `Config.transcriptionLanguage` is set to `"id"` (Indonesian) — Whisper picks one language
   per transcription, so it decodes as Indonesian while still passing through common English
   words/tech terms it recognizes (deploy, endpoint, testing, dashboard, etc.) mostly intact.
   True intra-sentence code-switching isn't perfect with any local model. If accuracy on fast
   or technical speech matters more than the extra download, swap in `ggml-small.bin`
   (466MB) — noticeably better multilingual accuracy, still fast on Apple Silicon.
4. Build: `./scripts/build_app.sh`
5. Launch: `open .build/MeetingRecorder.app`
6. On the first "Start Recording" click, macOS prompts for Screen Recording permission.
   Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch.

## Usage

Click the menubar icon > Start Recording. Click again > Stop Recording. Wait for
"Transcribing…" to finish — a notification confirms the transcript is saved.

- **Audio (`.wav`)** is saved to `Recordings/` inside this project folder (gitignored —
  never committed, never synced anywhere).
- **Transcript (`.md`)** is saved to `~/Documents/ObsidianVault/Recordings/` — this syncs
  across your other Macs via the vault, while the (much larger) audio file stays local.
- Both files share the same timestamp-based filename (e.g. `2026-08-06-08-31-36.wav` /
  `.md`), so they're easy to match up.

If the app crashes or is force-quit mid-recording, relaunch it — it scans for a `.wav`
in `Recordings/` with no matching `.md` in the vault and offers to transcribe it.

## Known quirks

- **Screen Recording permission resets on rebuild.** This app is ad-hoc code-signed
  (`codesign --sign -`, no paid Apple Developer identity — deliberately, so this project
  doesn't need Xcode or a dev account). macOS ties the Screen Recording grant to the exact
  binary's signature hash, not to a stable app identity, so every time the source changes
  and you rebuild, macOS treats it as a "new app" and asks for permission again — even
  though the toggle in Settings may still show a stale "on" entry from the previous build.
  If Start Recording fails with `SCStreamErrorDomain Code=-3801` after a rebuild: open
  System Settings > Privacy & Security > Screen Recording, remove the old MeetingRecorder
  entry (the `-` button, not just the toggle) if one exists, fully quit the app, relaunch,
  and try Start Recording again. This is purely a rebuild-time annoyance — once you stop
  changing the code, the grant sticks for normal day-to-day use.
- **ScreenCaptureKit's audio permission is bundled with the "Screen Recording" permission.**
  There's no narrower "system audio only" TCC category on macOS, even though this app never
  actually records video (capture is configured with a token 2×2 pixel video size — audio
  only). The scary-sounding system dialog is just how macOS phrases that shared permission
  bucket.
- **System audio only, not microphone.** ScreenCaptureKit captures whatever is currently
  playing through your audio *output* device (speakers or headset) — other call
  participants, videos, music. It does not capture your own microphone input.

## Testing

Automated tests (XCTest) are **deferred** — this machine only has Xcode Command Line Tools
installed, not full Xcode.app, and XCTest (and Swift Testing) cannot actually execute test
bundles under CLT-only (confirmed empirically: both fail to link or silently no-op even with
manual framework/rpath workarounds). Every `MeetingRecorderCore` component was instead
manually smoke-tested during development (e.g. writing a real WAV and verifying with
`afinfo`, running `TranscriptionService` against a real synthesized clip, capturing real
system audio via a temporary harness). Once Xcode.app is installed:

1. Add back a `.testTarget` source directory under `Tests/MeetingRecorderCoreTests/` — the
   original implementation plan (in the Obsidian vault, `Works/Projects/meeting-recorder/plans/`)
   has each test file's exact content preserved inline, marked "(BACKFILL — do not create yet)".
2. Recreate each of those test files verbatim, then run `swift test`.

## Out of scope (for now)

- Live/streaming transcription during the call
- Auto-detecting when a meeting app is active
- Summarization / minutes-of-meeting generation — planned via shelling out to the `claude`
  CLI after transcription (see `future-work.md` in the Obsidian project folder)
- Settings UI — paths are constants in `Config.swift`
- Auto-delete of audio after transcription
