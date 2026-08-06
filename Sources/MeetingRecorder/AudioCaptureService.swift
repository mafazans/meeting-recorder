import Foundation
import ScreenCaptureKit
import AVFoundation
import MeetingRecorderCore

enum AudioCaptureError: Error {
    case noDisplayAvailable
}

final class AudioCaptureService: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var wavWriter: WAVFileWriter?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    func startCapture(outputDirectory: URL) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let timestamp = Self.timestampFormatter.string(from: Date())
        let fileURL = outputDirectory.appendingPathComponent("\(timestamp).wav")
        let writer = try WAVFileWriter(fileURL: fileURL, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        wavWriter = writer

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture"))
        try await stream.startCapture()
        self.stream = stream

        return fileURL
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
        wavWriter?.finalize()
        wavWriter = nil
        converter = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcmBuffer = sampleBuffer.asPCMBuffer() else { return }

        if converter == nil {
            converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / pcmBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { return }

        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        guard conversionError == nil, let int16Data = outputBuffer.int16ChannelData else { return }

        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: int16Data[0], count: frameLength))
        wavWriter?.append(samples: samples)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()
}

private extension CMSampleBuffer {
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else { return nil }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard let dataPointer else { return nil }

        if let floatData = buffer.floatChannelData {
            memcpy(floatData[0], dataPointer, totalLength)
        } else if let int16Data = buffer.int16ChannelData {
            memcpy(int16Data[0], dataPointer, totalLength)
        }
        return buffer
    }
}
