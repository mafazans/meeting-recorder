import AppKit
import MeetingRecorderCore

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let startStopItem: NSMenuItem
    private var onStartStopClicked: (() -> Void)?

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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
        startStopItem.target = self
    }

    func setOnStartStopClicked(_ handler: @escaping () -> Void) {
        onStartStopClicked = handler
    }

    func update(for state: RecordingState) {
        switch state {
        case .idle:
            startStopItem.title = "Start Recording"
            startStopItem.isEnabled = true
            statusItem.button?.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Idle")
        case .recording:
            startStopItem.title = "Stop Recording"
            startStopItem.isEnabled = true
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        case .transcribing:
            startStopItem.title = "Transcribing…"
            startStopItem.isEnabled = false
            statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
        }
    }

    @objc private func handleStartStopClicked() {
        onStartStopClicked?()
    }
}
