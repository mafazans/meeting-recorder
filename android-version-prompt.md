# Android Meeting Recorder — Build Prompt

This is a build brief for an Android counterpart to the macOS "Meeting Recorder" project
(`~/Projects/meeting-recorder`, also at `github.com/mafazans/meeting-recorder`). Same
philosophy — no bot joins the call, local-first, personal tool — but with two capability
upgrades the macOS version doesn't have. Paste this into a fresh coding session (Android
Studio + an agent, or a Claude Code session on a machine with Android tooling) to start the
build — this environment can't run/test Android tooling itself.

## Goal

Record meetings on Android: capture **video** (not just audio) via screen capture, with audio
from **both the microphone and system audio output, mixed together** — unlike the macOS
version, which only captures system output and never the mic. Transcribe locally where
feasible, generate structured meeting minutes, same output philosophy as the macOS tool.

## Why this differs from the macOS version (context for whoever builds it)

The macOS tool uses `ScreenCaptureKit`, which captures system audio **output only** — it never
taps the microphone. That means the user's own voice during a call is never recorded, only
what they hear. This was a real limitation discovered mid-project. The Android version should
explicitly fix this by capturing and mixing **both** sources.

Android's equivalent building blocks:
- `MediaProjection` — screen capture (video) and, since Android 10 (API 29), system/internal
  audio via `AudioPlaybackCaptureConfiguration`. **API 29 is a hard minimum** for the system-
  audio piece.
- `AudioRecord` — microphone capture, run in parallel with the above.
- `MediaCodec` + `MediaMuxer` — encode and mux the video track + mixed audio track into an
  MP4 container.

## Requirements

1. **Video + dual-source audio capture.** Use `MediaProjection` for screen video and
   `AudioPlaybackCaptureConfiguration` for system audio; use `AudioRecord` for the microphone
   in parallel. Mix the two PCM streams (simple additive mix with a clipping guard, or a real
   mixer if quality demands it) before muxing with the video track.
2. **Foreground service.** Recording must run as a foreground service with a persistent
   notification (Android requires this for `MediaProjection` + background audio capture) —
   Start/Stop controls live there, similar spirit to the macOS menubar icon.
3. **Storage.** Save the video file to app-local storage (scoped-storage compliant, e.g.
   `Context.getExternalFilesDir()`), auto-named by timestamp — same convention as the macOS
   tool (no manual title entry).
4. **Local transcription.** Port of `whisper.cpp` via Android NDK/JNI (evaluate existing
   Android wrapper projects vs. building the NDK library directly — needs research, this
   environment can't test it). Multilingual model, language `id` (Indonesian) + English mix,
   same as the macOS tool. Model size is a real tradeoff to resolve during the build — mobile
   devices have far less compute/storage headroom than a Mac; `large-v3-turbo` (~1.5GB) worked
   great on an M3 Mac but may be too heavy for many phones.
   **Known landmine from the macOS build:** `large-v3-turbo` entered a runaway repetition loop
   (same token repeated thousands of times, hung for 2+ minutes) on real audio until we passed
   `-mc 0` (disable carrying prior-segment context) to whisper.cpp. If the Android binding
   exposes an equivalent max-context parameter, set it the same way from day one — don't wait
   to rediscover this bug.
5. **Minutes generation.** Same structure as the macOS tool: after transcription, generate
   minutes with an LLM — sections for Executive Summary, Key Decisions, Action Items (flag
   unclear owner/deadline as `[UNCLEAR]` instead of guessing), Open Questions; wrap the
   transcript in `<transcript>` tags in the prompt; instruct it to only use information
   explicitly in the transcript, no invented facts. Unlike macOS, there's no local `claude` CLI
   to shell out to on Android — this needs either a cloud API call (Anthropic API, key stored
   securely, e.g. Android Keystore) or deferring minutes generation to a desktop step later
   (e.g. sync the transcript to the same place the macOS tool watches, or wherever it can be
   picked up manually).
6. **Sync/storage split.** The macOS tool keeps audio local (too large to sync) and transcripts
   in an Obsidian vault folder (synced across Macs). Evaluate whether Obsidian's Android app +
   its sync (Obsidian Sync, or a cloud-backed vault folder) can play the same role for
   transcripts here. Video files should stay device-local regardless, for the same size reason.
7. **UI.** Minimal — persistent notification with Start/Stop, no settings screen. Hardcode
   model path/language/output paths as constants, matching the macOS tool's YAGNI approach.

## Explicitly out of scope (matching the macOS tool's philosophy)

- Live/streaming transcription during the call.
- Auto-detection of meeting apps.
- Settings UI.
- Speaker diarization — evaluated and rejected for the macOS tool (audio is a single mixed
  stream by the time it's captured; real diarization needs a separate ML pipeline and accuracy
  would be mediocre on pre-mixed audio regardless). Same reasoning likely applies here, though
  having a genuinely separate mic-source track might change that calculus — worth a fresh look
  if it comes up, don't assume the macOS conclusion carries over unchanged.

## Open questions to resolve during the build

- Which whisper.cpp Android binding to actually use.
- Model size vs. device capability tradeoff (may need multiple bundled model options, or a
  download-on-first-run step).
- How minutes generation works without a local CLI equivalent to `claude -p`.
- **Privacy footprint is bigger than the macOS tool.** Video capture records whatever is on
  screen during the meeting — shared documents, chat messages, other apps' content, other
  participants' video feeds — not just audio. Worth explicitly confirming with the user this
  is still personal note-taking on calls they're already part of, not broader surveillance,
  before treating this as a drop-in upgrade to the macOS tool's scope.
