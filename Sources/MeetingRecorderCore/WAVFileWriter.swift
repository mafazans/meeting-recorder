import Foundation

public enum WAVFileWriterError: Error {
    case cannotOpenFile(URL)
}

public final class WAVFileWriter {
    private let fileHandle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private let bitsPerSample: UInt16
    private var dataByteCount: UInt32 = 0

    public init(
        fileURL: URL,
        sampleRate: UInt32 = 16000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) throws {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: fileURL.path) else {
            throw WAVFileWriterError.cannotOpenFile(fileURL)
        }
        self.fileHandle = handle
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        handle.write(Data(repeating: 0, count: 44))
    }

    public func append(samples: [Int16]) {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        fileHandle.write(data)
        dataByteCount += UInt32(data.count)
    }

    public func finalize() {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = 36 + dataByteCount

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(littleEndianBytes(of: riffChunkSize))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(littleEndianBytes(of: UInt32(16)))
        header.append(littleEndianBytes(of: UInt16(1)))
        header.append(littleEndianBytes(of: channels))
        header.append(littleEndianBytes(of: sampleRate))
        header.append(littleEndianBytes(of: byteRate))
        header.append(littleEndianBytes(of: blockAlign))
        header.append(littleEndianBytes(of: bitsPerSample))
        header.append(contentsOf: Array("data".utf8))
        header.append(littleEndianBytes(of: dataByteCount))

        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(header)
        fileHandle.closeFile()
    }

    private func littleEndianBytes<T: FixedWidthInteger>(of value: T) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<T>.size)
    }
}
