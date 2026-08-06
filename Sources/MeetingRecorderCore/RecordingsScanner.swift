import Foundation

public enum RecordingsScanner {
    public static func findOrphanedRecordings(
        audioDirectory: URL,
        transcriptsDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let audioContents = try? fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let transcriptContents = (try? fileManager.contentsOfDirectory(
            at: transcriptsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        let wavFiles = audioContents.filter { $0.pathExtension.lowercased() == "wav" }
        let mdBaseNames = Set(
            transcriptContents
                .filter { $0.pathExtension.lowercased() == "md" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        return wavFiles
            .filter { !mdBaseNames.contains($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
