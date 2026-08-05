import Foundation

public struct RecordingMetadata {
    public let date: Date
    public let startTime: Date
    public let endTime: Date

    public init(date: Date, startTime: Date, endTime: Date) {
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
    }

    public var durationSeconds: Int {
        Int(endTime.timeIntervalSince(startTime))
    }
}

public enum TranscriptWriter {
    public static func renderMarkdown(
        transcript: String,
        metadata: RecordingMetadata,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = timeZone

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.timeZone = timeZone

        let dateString = dateFormatter.string(from: metadata.date)
        let startString = timeFormatter.string(from: metadata.startTime)
        let endString = timeFormatter.string(from: metadata.endTime)

        return """
        ---
        date: \(dateString)
        start_time: \(startString)
        end_time: \(endString)
        duration: \(metadata.durationSeconds)s
        ---

        \(transcript)

        """
    }

    public static func write(
        transcript: String,
        metadata: RecordingMetadata,
        to fileURL: URL
    ) throws {
        let markdown = renderMarkdown(transcript: transcript, metadata: metadata)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
