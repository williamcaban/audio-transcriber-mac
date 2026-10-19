import AVFoundation
import Foundation

enum AudioLoaderError: Error {
    case unsupportedFormat
    case conversionFailed
}

/// Decodes any AVFoundation-readable audio/video file into mono Float32
/// PCM samples at the given sample rate -- the raw format Qwen3ASRRuntime's
/// `transcribe(audio:sampleRate:...)` expects.
enum AudioLoader {
    static func loadMonoFloatSamples(url: URL, targetSampleRate: Double = 16000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioLoaderError.unsupportedFormat
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioLoaderError.unsupportedFormat
        }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioLoaderError.conversionFailed
        }
        try file.read(into: sourceBuffer)

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1024
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: targetFrameCapacity
        ) else {
            throw AudioLoaderError.conversionFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error {
            throw conversionError ?? AudioLoaderError.conversionFailed
        }

        guard let channelData = targetBuffer.floatChannelData else {
            throw AudioLoaderError.conversionFailed
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(targetBuffer.frameLength)))
    }
}
