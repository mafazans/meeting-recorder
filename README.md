# Meeting Recorder

Personal macOS menubar app: captures system audio (what you hear) mixed with your microphone
(what you say) during a meeting (no bot joins the call), transcribes it locally after you
click Stop, and saves the transcript to your Obsidian vault. Audio stays local to this
project folder.

## Setup

1. Install whisper.cpp: `brew install whisper-cpp`
2. Confirm the binary path: `which whisper-cli`. If it's not `/opt/homebrew/bin/whisper-cli`,
   update `Config.whisperBinaryPath` in `Sources/MeetingRecorder/Config.swift`.
3. Download the **multilingual `large-v3-turbo`** model (not the `.en` English-only variant
   — meetings here are a mix of Indonesian and English, and the English-only model produces
   garbage on non-English audio):
   ```bash
   mkdir -p ~/whisper-models
   curl -L -o ~/whisper-models/ggml-large-v3-turbo.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
   ```
   This is a ~1.5GB download but runs well under real-time on Apple Silicon (Metal-accelerated)
   and gives noticeably better accuracy on non-English/code-switched speech than smaller
   models (`tiny`/`base`/`small`) — it's distilled from `large-v3` to run ~4x faster at nearly
   the same accuracy. `Config.transcriptionLanguage` is set to `"id"` (Indonesian) — Whisper
   picks one language per transcription, so it decodes as Indonesian while still passing
   through common English words/tech terms it recognizes (deploy, endpoint, timeout, dashboard,
   etc.) mostly intact. True intra-sentence code-switching isn't perfect with any local model.
   If you want the absolute best accuracy regardless of speed/size, `ggml-large-v3.bin`
   (~3.1GB) is the ceiling.

   **Important:** `TranscriptionArgs` passes `-mc 0` (max-context = 0) to `whisper-cli`. Without
   it, `large-v3-turbo` can enter a runaway repetition loop on some audio (observed hanging on
   a real recording, outputting the same token thousands of times) — `-mc 0` disables carrying
   prior segment text as context, which is what triggers the compounding failure. Don't remove
   this flag without re-testing against a real multi-minute recording first.
4. **Optional — for AI-generated meeting minutes:** install the Claude Code CLI (`claude`) and
   make sure it's authenticated (`claude` at `/opt/homebrew/bin/claude`, checked via
   `Config.claudeBinaryPath`). If missing, minutes generation is silently skipped — the
   transcript still saves normally either way.
5. Build: `./scripts/build_app.sh`
6. Launch: `open .build/MeetingRecorder.app`
7. On the first "Start Recording" click, macOS prompts for Screen Recording permission.
   Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch.
8. **Optional — launch automatically at login/boot:** `./scripts/install_launch_agent.sh`.
   Installs a LaunchAgent (`~/Library/LaunchAgents/com.arifmafazan.meetingrecorder.launcher.plist`)
   that opens the app every time you log in. To undo, the script prints the exact
   `launchctl unload` + `rm` commands when it runs.

## Usage

Click the menubar icon > Start Recording. Click again > Stop Recording. Wait for
"Transcribing…" to finish — a notification confirms the transcript is saved.

- **Audio (`.wav`)** is saved to `Recordings/` inside this project folder (gitignored —
  never committed, never synced anywhere).
- **Transcript (`.md`)** is saved to `~/Documents/ObsidianVault/Recordings/` — this syncs
  across your other Macs via the vault, while the (much larger) audio file stays local.
- **Meeting minutes** (`<timestamp>-minutes-<title-slug>.md`) are generated automatically
  right after the transcript, via the `claude` CLI — a short summary plus bulleted action
  items/decisions, with a Claude-generated title as an `# H1` heading and as the filename
  suffix (e.g. `2026-08-06-08-32-29-minutes-3pl-logistics-deploy-review.md`). This is
  best-effort: if `claude` isn't installed or the call fails, it's silently skipped — the
  transcript itself already saved successfully either way.
- All files (audio, transcript, minutes) share the same timestamp-based base filename, so
  they're easy to match up.

If the app crashes or is force-quit mid-recording, relaunch it — it scans for a `.wav`
in `Recordings/` with no matching `.md` in the vault and offers to transcribe it.

**Your own voice is captured too.** `AudioCaptureService` also taps the microphone
(`AVAudioEngine`) in parallel with system audio, starting at the same moment you click Start
Recording. After Stop, the two streams are mixed into the single output WAV — the mic stream
is gated by RMS energy per 100ms chunk (not a single-sample peak check, so a brief transient
like a keyboard click doesn't falsely open the gate), so only chunks where you're actually
speaking get blended in — avoids constantly layering in room/background noise during silence.
If mic permission hasn't been granted yet on first use, capture proceeds with system audio
only and mic starts a bit late once you respond to the permission prompt — `AudioMixer`
accounts for that start-time offset so the mixed result still lines up correctly, it just
means your very first ~few seconds before granting permission won't include your voice.

**Toggle the microphone off** via the menu bar — "Include Microphone" (checkbox, only
togglable while idle) — if you don't want your voice recorded for a given session. This is
the only real control against personal conversations getting captured: RMS gating filters
noise, not context, so it can't distinguish meeting speech from a private conversation
happening while the app is still recording — the mic toggle plus remembering to click Stop
are the actual safeguards. The setting persists across launches (`UserDefaults`).

**Your speech is also labeled separately.** Since the mic and system audio are captured as
genuinely separate streams before mixing, the raw mic-only audio is transcribed a second time
on its own and appended to the transcript file as a clearly marked "## My speech (microphone
only)" section — so it's unambiguous which parts you said yourself, without needing full
speaker diarization (which isn't feasible here — see below). This doubles transcription time
per recording (~10-20s extra on this hardware) and is best-effort: if it fails, the main
transcript still saves normally.

**Speaker diarization (distinguishing multiple *other* participants) is not implemented.**
Evaluated and rejected: the audio is a single mixed stream by the time it's captured (all
meeting participants blended together by the meeting app itself before it ever reaches
ScreenCaptureKit), so real diarization would need a separate ML pipeline (`pyannote.audio` /
`WhisperX`) and accuracy on pre-mixed audio would be mediocre regardless. The mic-vs-system
separation above only distinguishes "me" from "everyone else combined," not who among the
"everyone else" said what.

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
- **Microphone permission is separate from Screen Recording.** As of the mic-mixing feature
  (see Usage), the app also requests Microphone access — its own TCC prompt, independent of
  Screen Recording. Same ad-hoc-signing rebuild friction applies to it too.
- **The `claude` CLI itself triggers Photos/Downloads/MediaLibrary permission prompts,
  attributed to this app.** Confirmed via `log show --predicate 'subsystem == "com.apple.TCC"'`
  — when `MinutesService` spawns `claude -p` as a subprocess, macOS attributes `claude`'s own
  internal permission checks to whichever GUI app launched it (`MeetingRecorder`), regardless
  of what the actual prompt/task is. This is `claude`'s own startup behavior (likely general
  capability-probing for its normal image-reading features), not anything in this app's code
  — nothing here ever reads Photos/Downloads/MediaLibrary. Safe to always deny; considered and
  rejected wrapping the subprocess in a `sandbox-exec` Seatbelt profile to enforce this at the
  OS level — too much risk of silently breaking `claude`'s own network/auth access via an
  undocumented, deprecated API, for a prompt that's just noise, not an actual access risk
  (granting ≠ using; no code path here calls those APIs regardless of grant state).

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
- Settings UI — paths/model/language are constants in `Config.swift`
- Auto-delete of audio after transcription
