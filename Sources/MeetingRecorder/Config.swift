import Foundation

enum Config {
    static let recordingsDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ObsidianVault/Recordings")

    static let whisperBinaryPath = "/opt/homebrew/bin/whisper-cli"

    static let whisperModelPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("whisper-models/ggml-base.en.bin")
        .path
}
