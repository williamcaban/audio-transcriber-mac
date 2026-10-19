import AVFoundation

struct AudioFileInfo {
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
}

enum AudioFileInspector {
    static func inspect(url: URL) throws -> AudioFileInfo {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
        return AudioFileInfo(duration: duration, sampleRate: format.sampleRate, channelCount: format.channelCount)
    }
}
