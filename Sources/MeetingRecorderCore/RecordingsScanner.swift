import Foundation

public enum RecordingsScanner {
    public static func findOrphanedRecordings(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let wavFiles = contents.filter { $0.pathExtension.lowercased() == "wav" }
        let mdBaseNames = Set(
            contents
                .filter { $0.pathExtension.lowercased() == "md" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        return wavFiles
            .filter { !mdBaseNames.contains($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
