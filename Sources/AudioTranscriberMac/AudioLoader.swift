import AVFoundation
import Foundation

enum AudioLoaderError: Error {
    case unsupportedFormat
    case conversionFailed
}

/// Reads and resamples an audio/video file's audio track incrementally, one
/// bounded chunk at a time, directly off disk -- memory use stays capped at
/// roughly one chunk's size regardless of how long the source file is.
///
/// This replaces an earlier version that decoded the WHOLE file into a
/// single in-memory Float array before any chunking happened. That worked
/// for normal-length recordings, but a real ~8GB video file crashed the
/// app: that single allocation gets into the multi-gigabyte range for a
/// long enough file, which is usually an unrecoverable OOM kill rather than
/// a catchable Swift error (hence no clear failure message at the time).
/// Streaming the decode itself -- not just the 30s chunking Qwen3-ASR's
/// fixed encoder window already required -- fixes that for files of any
/// length.
final class ChunkedAudioReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let sourceChunkFrames: AVAudioFrameCount
    private var reachedEndOfFile = false

    init(url: URL, targetSampleRate: Double = 16000, chunkSeconds: Double = 30) throws {
        file = try AVAudioFile(forReading: url)
        sourceFormat = file.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioLoaderError.unsupportedFormat
        }
        self.targetFormat = targetFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioLoaderError.unsupportedFormat
        }
        self.converter = converter

        sourceChunkFrames = AVAudioFrameCount(chunkSeconds * sourceFormat.sampleRate)
    }

    /// Returns the next chunk of mono Float32 samples at the target sample
    /// rate, or nil once the file is exhausted. The AVAudioConverter is
    /// reused across calls by design (Apple's documented streaming-
    /// conversion pattern): besides avoiding per-chunk setup cost, it also
    /// avoids resampling-edge artifacts a fresh converter per chunk would
    /// introduce at chunk boundaries.
    func nextChunk() throws -> [Float]? {
        guard !reachedEndOfFile else { return nil }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat, frameCapacity: sourceChunkFrames
        ) else {
            throw AudioLoaderError.conversionFailed
        }
        try file.read(into: sourceBuffer, frameCount: sourceChunkFrames)

        guard sourceBuffer.frameLength > 0 else {
            reachedEndOfFile = true
            return nil
        }
        if sourceBuffer.frameLength < sourceChunkFrames {
            reachedEndOfFile = true
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
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
