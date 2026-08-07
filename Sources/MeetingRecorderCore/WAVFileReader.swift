import Foundation

public enum WAVFileReader {
    public static func readSamples(from fileURL: URL) throws -> [Int16] {
        let data = try Data(contentsOf: fileURL)
        guard data.count > 44 else { return [] }
        let pcmData = data.subdata(in: 44..<data.count)
        return pcmData.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Int16(littleEndian: $0) }
        }
    }
}
