import Foundation

struct MeetingMinutes {
    let title: String
    let body: String

    var titleSlug: String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics
        let slug = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(slug)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

enum MinutesService {
    private static let prompt = """
    First, provide a short 3-6 word title for this meeting, formatted exactly as \
    "Title: <title>" on its own line. Then, on the following lines, summarize this \
    meeting transcript into concise meeting minutes: a short prose summary of what \
    was discussed, followed by a bulleted list of action items or decisions if any \
    were mentioned. If the transcript is too garbled or short to summarize \
    meaningfully, say so briefly (but still provide a best-effort title).
    """

    static func generateMinutes(transcript: String) -> MeetingMinutes? {
        guard FileManager.default.fileExists(atPath: Config.claudeBinaryPath) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Config.claudeBinaryPath)
        process.arguments = ["-p", prompt]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        inputPipe.fileHandleForWriting.write(transcript.data(using: .utf8) ?? Data())
        inputPipe.fileHandleForWriting.closeFile()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        guard let text = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return parse(text)
    }

    private static func parse(_ text: String) -> MeetingMinutes {
        var lines = text.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("Title:") else {
            return MeetingMinutes(title: "Untitled Meeting", body: text)
        }
        let title = firstLine
            .dropFirst("Title:".count)
            .trimmingCharacters(in: .whitespaces)
        lines.removeFirst()
        let body = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingMinutes(title: title.isEmpty ? "Untitled Meeting" : title, body: body)
    }
}
