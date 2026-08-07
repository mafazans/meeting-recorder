import AppKit
import UserNotifications
import MeetingRecorderCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private let audioCapture = AudioCaptureService()
    private var state: RecordingState = .idle
    private var currentRecordingStart: Date?
    private var currentWavURL: URL?
    private var micEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "micEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "micEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        menuBarController = MenuBarController()
        menuBarController.update(for: state)
        menuBarController.updateMicToggle(isOn: micEnabled)
        menuBarController.setOnStartStopClicked { [weak self] in
            self?.handleStartStopClicked()
        }
        menuBarController.setOnMicToggleClicked { [weak self] in
            self?.handleMicToggleClicked()
        }
        checkForOrphanedRecordings()
    }

    private func handleMicToggleClicked() {
        micEnabled.toggle()
        menuBarController.updateMicToggle(isOn: micEnabled)
    }

    private func handleStartStopClicked() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        Task { @MainActor in
            do {
                let fileURL = try await audioCapture.startCapture(
                    outputDirectory: Config.audioDirectory,
                    captureMicrophone: micEnabled
                )
                currentWavURL = fileURL
                currentRecordingStart = Date()
                state = RecordingStateMachine.transition(from: state, on: .startClicked)
                menuBarController.update(for: state)
            } catch {
                showAlert(title: "Couldn't start recording", message: describeCaptureError(error))
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        Task { @MainActor in
            var micFileURL: URL?
            do {
                micFileURL = try await audioCapture.stopCapture()
            } catch {
                showAlert(title: "Error stopping recording", message: "\(error)")
            }

            state = RecordingStateMachine.transition(from: state, on: .stopClicked)
            menuBarController.update(for: state)

            guard let wavURL = currentWavURL, let start = currentRecordingStart else { return }
            let end = Date()

            do {
                let transcript = try await Task.detached {
                    try TranscriptionService.transcribe(wavFileURL: wavURL)
                }.value

                let transcriptForFile = await appendMicTranscriptIfAvailable(
                    to: transcript,
                    micFileURL: micFileURL
                )

                let mdURL = Config.transcriptsDirectory.appendingPathComponent(
                    wavURL.deletingPathExtension().appendingPathExtension("md").lastPathComponent
                )
                let metadata = RecordingMetadata(date: start, startTime: start, endTime: end)
                try TranscriptWriter.write(transcript: transcriptForFile, metadata: metadata, to: mdURL)
                notify(title: "Transcript saved", body: mdURL.lastPathComponent)

                let minutesTask = Task.detached {
                    MinutesService.generateMinutes(transcript: transcript)
                }
                if let minutes = await minutesTask.value {
                    try? writeMinutes(minutes, alongside: mdURL)
                }
            } catch {
                showAlert(title: "Transcription failed", message: describeTranscriptionError(error))
            }

            currentWavURL = nil
            currentRecordingStart = nil
            state = RecordingStateMachine.transition(from: state, on: .transcriptionFinished)
            menuBarController.update(for: state)
        }
    }

    private func checkForOrphanedRecordings() {
        let orphans = RecordingsScanner.findOrphanedRecordings(
            audioDirectory: Config.audioDirectory,
            transcriptsDirectory: Config.transcriptsDirectory
        )
        guard let firstOrphan = orphans.first else { return }

        let alert = NSAlert()
        alert.messageText = "Unfinished recording found"
        alert.informativeText = "Found \(firstOrphan.lastPathComponent) with no transcript. Transcribe it now?"
        alert.addButton(withTitle: "Transcribe")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            transcribeOrphan(firstOrphan)
        }
    }

    private func transcribeOrphan(_ wavURL: URL) {
        do {
            let transcript = try TranscriptionService.transcribe(wavFileURL: wavURL)
            let mdURL = Config.transcriptsDirectory.appendingPathComponent(
                wavURL.deletingPathExtension().appendingPathExtension("md").lastPathComponent
            )
            let attrs = try FileManager.default.attributesOfItem(atPath: wavURL.path)
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            let metadata = RecordingMetadata(date: modDate, startTime: modDate, endTime: modDate)
            try TranscriptWriter.write(transcript: transcript, metadata: metadata, to: mdURL)
            notify(title: "Transcript saved", body: mdURL.lastPathComponent)

            if let minutes = MinutesService.generateMinutes(transcript: transcript) {
                try? writeMinutes(minutes, alongside: mdURL)
            }
        } catch {
            showAlert(title: "Transcription failed", message: describeTranscriptionError(error))
        }
    }

    /// Transcribes the raw mic-only audio separately and appends it as a clearly labeled
    /// section, so it's unambiguous which parts of the transcript came from the user's
    /// own microphone. Best-effort — falls back to the unmodified transcript on any failure.
    /// Always deletes the temporary mic file, since AudioCaptureService intentionally left
    /// that cleanup to the caller.
    private func appendMicTranscriptIfAvailable(to transcript: String, micFileURL: URL?) async -> String {
        guard let micFileURL else { return transcript }
        defer { try? FileManager.default.removeItem(at: micFileURL) }

        let micTranscript = try? await Task.detached {
            try TranscriptionService.transcribe(wavFileURL: micFileURL)
        }.value

        guard let micTranscript, !micTranscript.isEmpty else { return transcript }
        return transcript + "\n\n---\n\n## My speech (microphone only)\n\n" + micTranscript
    }

    private func writeMinutes(_ minutes: MeetingMinutes, alongside transcriptURL: URL) throws {
        let baseName = transcriptURL.deletingPathExtension().lastPathComponent
        let minutesURL = transcriptURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)-minutes-\(minutes.titleSlug).md")
        let content = "# \(minutes.title)\n\n\(minutes.body)\n"
        try content.write(to: minutesURL, atomically: true, encoding: .utf8)
    }

    private func describeCaptureError(_ error: Error) -> String {
        "Check that Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording, then try again.\n\n\(error)"
    }

    private func describeTranscriptionError(_ error: Error) -> String {
        if let error = error as? TranscriptionError {
            switch error {
            case .binaryNotFound:
                return "whisper-cli not found at \(Config.whisperBinaryPath). Run `brew install whisper-cpp`."
            case .modelNotFound:
                return "Model not found at \(Config.whisperModelPath). Download a ggml model and place it there."
            case .processFailed(let code):
                return "whisper-cli exited with status \(code)."
            case .outputNotFound:
                return "whisper-cli did not produce an output file."
            }
        }
        return "\(error)"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
