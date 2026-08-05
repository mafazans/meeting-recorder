import Foundation
import MeetingRecorderCore

enum TranscriptionError: Error {
    case binaryNotFound
    case modelNotFound
    case processFailed(Int32)
    case outputNotFound
}

enum TranscriptionService {
    static func transcribe(wavFileURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: Config.whisperBinaryPath) else {
            throw TranscriptionError.binaryNotFound
        }
        guard FileManager.default.fileExists(atPath: Config.whisperModelPath) else {
            throw TranscriptionError.modelNotFound
        }

        let outputBasePath = wavFileURL.deletingPathExtension().path
        let args = TranscriptionArgs.buildArguments(
            modelPath: Config.whisperModelPath,
            inputWAVPath: wavFileURL.path,
            outputBasePath: outputBasePath
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Config.whisperBinaryPath)
        process.arguments = args
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(process.terminationStatus)
        }

        let outputTextPath = outputBasePath + ".txt"
        guard let text = try? String(contentsOfFile: outputTextPath, encoding: .utf8) else {
            throw TranscriptionError.outputNotFound
        }
        try? FileManager.default.removeItem(atPath: outputTextPath)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
