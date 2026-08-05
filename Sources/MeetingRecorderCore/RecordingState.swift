public enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
}

public enum RecordingEvent {
    case startClicked
    case stopClicked
    case transcriptionFinished
}

public enum RecordingStateMachine {
    public static func transition(from state: RecordingState, on event: RecordingEvent) -> RecordingState {
        switch (state, event) {
        case (.idle, .startClicked):
            return .recording
        case (.recording, .stopClicked):
            return .transcribing
        case (.transcribing, .transcriptionFinished):
            return .idle
        default:
            return state
        }
    }
}
