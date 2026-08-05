import AppKit
import MeetingRecorderCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var state: RecordingState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController.update(for: state)
        menuBarController.setOnStartStopClicked { [weak self] in
            self?.handleStartStopClicked()
        }
    }

    private func handleStartStopClicked() {
        let event: RecordingEvent = (state == .idle) ? .startClicked : .stopClicked
        state = RecordingStateMachine.transition(from: state, on: event)
        menuBarController.update(for: state)
    }
}
