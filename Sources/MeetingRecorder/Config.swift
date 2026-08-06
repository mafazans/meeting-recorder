import Foundation

enum Config {
    static let audioDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Projects/meeting-recorder/Recordings")

    static let transcriptsDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ObsidianVault/Recordings")

    static let whisperBinaryPath = "/opt/homebrew/bin/whisper-cli"

    static let whisperModelPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("whisper-models/ggml-large-v3-turbo.bin")
        .path

    static let transcriptionLanguage = "id"

    static let claudeBinaryPath = "/opt/homebrew/bin/claude"
}
