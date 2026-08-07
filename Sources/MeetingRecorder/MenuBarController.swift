import AppKit
import MeetingRecorderCore

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let startStopItem: NSMenuItem
    private let micToggleItem: NSMenuItem
    private var onStartStopClicked: (() -> Void)?
    private var onMicToggleClicked: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Idle")

        let menu = NSMenu()
        startStopItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(handleStartStopClicked),
            keyEquivalent: ""
        )
        menu.addItem(startStopItem)

        micToggleItem = NSMenuItem(
            title: "Include Microphone",
            action: #selector(handleMicToggleClicked),
            keyEquivalent: ""
        )
        menu.addItem(micToggleItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
        startStopItem.target = self
        micToggleItem.target = self
    }

    func setOnStartStopClicked(_ handler: @escaping () -> Void) {
        onStartStopClicked = handler
    }

    func setOnMicToggleClicked(_ handler: @escaping () -> Void) {
        onMicToggleClicked = handler
    }

    func updateMicToggle(isOn: Bool) {
        micToggleItem.state = isOn ? .on : .off
    }

    func update(for state: RecordingState) {
        switch state {
        case .idle:
            startStopItem.title = "Start Recording"
            startStopItem.isEnabled = true
            micToggleItem.isEnabled = true
            statusItem.button?.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Idle")
        case .recording:
            startStopItem.title = "Stop Recording"
            startStopItem.isEnabled = true
            micToggleItem.isEnabled = false
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        case .transcribing:
            startStopItem.title = "Transcribing…"
            startStopItem.isEnabled = false
            micToggleItem.isEnabled = false
            statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
        }
    }

    @objc private func handleStartStopClicked() {
        onStartStopClicked?()
    }

    @objc private func handleMicToggleClicked() {
        onMicToggleClicked?()
    }
}
