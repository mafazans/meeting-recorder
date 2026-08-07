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

    private var audioEngine: AVAudioEngine?
    private var micWriter: WAVFileWriter?
    private var micConverter: AVAudioConverter?
    private var micFileURL: URL?
    private var systemFileURL: URL?
    private var recordingStartDate: Date?
    private var micTapStartDate: Date?

    func startCapture(outputDirectory: URL, captureMicrophone: Bool = true) async throws -> URL {
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
        systemFileURL = fileURL
        micFileURL = nil
        recordingStartDate = Date()

        if captureMicrophone {
            startMicCaptureIfAuthorized(timestamp: timestamp)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture"))
        try await stream.startCapture()
        self.stream = stream

        return fileURL
    }

    /// Returns the URL of the raw, unmixed microphone-only WAV, if the mic was captured
    /// this session — the caller can use it to produce a separate "what I said"
    /// transcript before it's cleaned up. Returns nil if the mic wasn't captured.
    func stopCapture() async throws -> URL? {
        try await stream?.stopCapture()
        stream = nil
        wavWriter?.finalize()
        wavWriter = nil
        converter = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        micWriter?.finalize()
        micWriter = nil
        micConverter = nil

        return mixMicIntoSystemAudioIfAvailable()
    }

    // MARK: - Microphone capture (mixed into the system-audio WAV on stop)

    private func startMicCaptureIfAuthorized(timestamp: String) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginMicCapture(timestamp: timestamp)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.beginMicCapture(timestamp: timestamp)
                }
            }
        default:
            break
        }
    }

    private func beginMicCapture(timestamp: String) {
        guard audioEngine == nil else { return }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(timestamp)-mic.wav")
        guard let writer = try? WAVFileWriter(fileURL: fileURL, sampleRate: 16000, channels: 1, bitsPerSample: 16) else {
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.appendMicBuffer(buffer, inputFormat: inputFormat)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            writer.finalize()
            return
        }

        audioEngine = engine
        micWriter = writer
        micFileURL = fileURL
        micTapStartDate = Date()
    }

    private func appendMicBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        if micConverter == nil {
            micConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let micConverter else { return }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { return }

        var conversionError: NSError?
        micConverter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let int16Data = outputBuffer.int16ChannelData else { return }

        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: int16Data[0], count: frameLength))
        micWriter?.append(samples: samples)
    }

    /// Mixes the captured mic audio into the system-audio WAV in place, then returns the
    /// mic-only WAV's URL so the caller can transcribe it separately before deleting it.
    /// The caller owns cleanup of the returned file — it is intentionally not deleted here.
    private func mixMicIntoSystemAudioIfAvailable() -> URL? {
        defer {
            systemFileURL = nil
            recordingStartDate = nil
            micTapStartDate = nil
        }

        guard let systemFileURL, let micFileURL,
              FileManager.default.fileExists(atPath: micFileURL.path) else {
            return nil
        }

        guard let systemSamples = try? WAVFileReader.readSamples(from: systemFileURL),
              let micSamples = try? WAVFileReader.readSamples(from: micFileURL) else {
            return nil
        }

        var offsetSamples = 0
        if let recordingStartDate, let micTapStartDate, micTapStartDate > recordingStartDate {
            let offsetSeconds = micTapStartDate.timeIntervalSince(recordingStartDate)
            offsetSamples = Int(offsetSeconds * targetFormat.sampleRate)
        }

        let mixed = AudioMixer.mix(
            primary: systemSamples,
            secondary: micSamples,
            secondaryOffsetSamples: offsetSamples
        )

        guard let writer = try? WAVFileWriter(fileURL: systemFileURL, sampleRate: 16000, channels: 1, bitsPerSample: 16) else {
            return nil
        }
        writer.append(samples: mixed)
        writer.finalize()

        return micFileURL
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
