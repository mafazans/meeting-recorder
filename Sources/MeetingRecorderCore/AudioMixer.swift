import Foundation

/// Mixes a secondary audio stream (e.g. microphone) into a primary one (e.g. system
/// audio), gating the secondary stream so only chunks with real signal get merged in
/// (avoids blending in constant background hiss/room noise during silence).
public enum AudioMixer {
    public static func mix(
        primary: [Int16],
        secondary: [Int16],
        secondaryOffsetSamples: Int = 0,
        secondaryGateRMSThreshold: Double = 800,
        gateChunkSize: Int = 1600
    ) -> [Int16] {
        let offset = max(0, secondaryOffsetSamples)
        let count = max(primary.count, offset + secondary.count)
        var result = [Int16](repeating: 0, count: count)

        var i = 0
        while i < count {
            let end = min(i + gateChunkSize, count)

            let secondaryStart = max(i, offset) - offset
            let secondaryEnd = max(0, min(end, offset + secondary.count) - offset)
            let isActive: Bool
            if secondaryStart < secondaryEnd, secondaryStart >= 0, secondaryEnd <= secondary.count {
                let chunk = secondary[secondaryStart..<secondaryEnd]
                let sumOfSquares = chunk.reduce(0.0) { $0 + Double($1) * Double($1) }
                let rms = (sumOfSquares / Double(chunk.count)).squareRoot()
                isActive = rms > secondaryGateRMSThreshold
            } else {
                isActive = false
            }

            for j in i..<end {
                let primarySample = j < primary.count ? Int32(primary[j]) : 0
                var secondarySample: Int32 = 0
                if isActive {
                    let secondaryIndex = j - offset
                    if secondaryIndex >= 0, secondaryIndex < secondary.count {
                        secondarySample = Int32(secondary[secondaryIndex])
                    }
                }
                let sum = primarySample + secondarySample
                result[j] = Int16(max(Int32(Int16.min), min(Int32(Int16.max), sum)))
            }
            i = end
        }
        return result
    }
}
