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
    You will be given a meeting transcript wrapped in <transcript> tags below. \
    Produce meeting minutes from it.

    First, output a short 3-6 word title, formatted exactly as "Title: <title>" \
    on its own line.

    Then, output these exact sections, each as a Markdown heading:

    ## Executive Summary
    2-3 sentences on the meeting's primary objective and outcome.

    ## Key Decisions
    A list of what was agreed upon and why. If none, write "No decisions were made."

    ## Action Items
    A list of action items, each stating who owns it, what it is, and the deadline \
    if one was given. If the owner or deadline is unclear from the transcript, write \
    "[UNCLEAR]" for that part instead of guessing. If there are none, write \
    "No action items."

    ## Open Questions
    Anything left unresolved, or items where the owner/timeline is vague or missing. \
    If none, write "None."

    Rules:
    - Only include information explicitly stated in the transcript. Do not infer or \
    invent names, dates, or facts that aren't there.
    - If the transcript is too garbled or short to summarize meaningfully, say so \
    briefly in the Executive Summary and leave the other sections minimal — but still \
    provide a best-effort title.
    """

    private static func wrapTranscript(_ transcript: String) -> String {
        "<transcript>\n\(transcript)\n</transcript>"
    }

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

        let wrapped = wrapTranscript(transcript)
        inputPipe.fileHandleForWriting.write(wrapped.data(using: .utf8) ?? Data())
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
