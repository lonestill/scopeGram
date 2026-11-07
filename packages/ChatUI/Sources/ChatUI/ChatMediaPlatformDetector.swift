import Foundation
import Cocoa
import Postbox
import TelegramCore
import TelegramMedia

public enum ClientPlatform: String {
    case ios = "iOS"
    case android = "Android"
    case desktop = "Desktop"
    case web = "Web"
    
    public var badgeText: String {
        return self.rawValue
    }
}

public struct MediaDetectionResult {
    public let platform: ClientPlatform
    public let detail: String
    
    public init(platform: ClientPlatform, detail: String) {
        self.platform = platform
        self.detail = detail
    }
}

public final class ChatMediaPlatformDetector {
    public static var isEnabled: Bool {
        return UserDefaults.standard.object(forKey: "scopegram.detectMediaClient") as? Bool ?? true
    }
    
    public static func detect(for message: Message) -> MediaDetectionResult? {
        guard isEnabled else { return nil }
        
        // 1. Check Voice Messages
        for media in message.media {
            if let file = media as? TelegramMediaFile, file.isVoice {
                return detectVoice(file: file)
            }
        }
        
        // 2. Check Round Video Messages (Video Notes)
        for media in message.media {
            if let file = media as? TelegramMediaFile, file.isVideo && file.isInstantVideo {
                return detectVideoNote(file: file)
            }
        }
        
        // 3. Check Photos
        for media in message.media {
            if let image = media as? TelegramMediaImage {
                return detectImage(image: image)
            }
        }
        
        return nil
    }
    
    public static func detectPlatformBadge(for message: Message) -> String? {
        guard let result = detect(for: message) else { return nil }
        return result.platform.badgeText
    }
    
    // MARK: - Voice Message Detection
    
    private static func detectVoice(file: TelegramMediaFile) -> MediaDetectionResult? {
        // Fast-path: Web client MIME types
        let mime = file.mimeType.lowercased()
        if mime.contains("webm") || mime.contains("codecs=opus") {
            return MediaDetectionResult(platform: .web, detail: "Web (MediaRecorder container)")
        }
        
        // Extract voice audio attribute
        var waveformData: Data?
        var durationSec: Int = 0
        for attribute in file.attributes {
            if case let .Audio(isVoice, duration, _, _, waveform) = attribute, isVoice {
                waveformData = waveform
                durationSec = duration
                break
            }
        }
        
        // Missing waveform on duration > 0 is characteristic of Web / Bot API uploads
        guard let bitstream = waveformData, !bitstream.isEmpty else {
            if durationSec > 0 {
                return MediaDetectionResult(platform: .web, detail: "Web / Bot (no waveform)")
            }
            return nil
        }
        
        // Unpack 5-bit waveform samples (0..31)
        let numSamples = Int(Float(bitstream.count * 8) / 5.0)
        guard numSamples >= 10 else { return nil }
        
        var samples: [Int] = []
        samples.reserveCapacity(numSamples)
        
        let totalBits = bitstream.count * 8
        bitstream.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            for i in 0 ..< numSamples {
                let bitOffset = i * 5
                if bitOffset + 5 <= totalBits {
                    let byteOffset = bitOffset / 8
                    let bitInByte = bitOffset % 8
                    let ptr = baseAddress.advanced(by: byteOffset)
                    var value: UInt32 = 0
                    let bytesToRead = min(4, bitstream.count - byteOffset)
                    memcpy(&value, ptr, bytesToRead)
                    let sample = Int((value >> bitInByte) & 0x1F)
                    samples.append(sample)
                }
            }
        }
        
        guard samples.count >= 10 else { return nil }
        
        // Compute waveform metrics
        var leadingZeros = 0
        for s in samples {
            if s == 0 {
                leadingZeros += 1
            } else {
                break
            }
        }
        
        var trailingZeros = 0
        for s in samples.reversed() {
            if s == 0 {
                trailingZeros += 1
            } else {
                break
            }
        }
        
        var maxSample = 0
        var totalZeros = 0
        var totalStep = 0
        var maxStep = 0
        for i in 0 ..< samples.count {
            let s = samples[i]
            if s > maxSample { maxSample = s }
            if s == 0 { totalZeros += 1 }
            if i > 0 {
                let step = abs(s - samples[i - 1])
                totalStep += step
                if step > maxStep { maxStep = step }
            }
        }
        let avgStep = Double(totalStep) / Double(max(1, samples.count - 1))
        
        // 1. Android Signature:
        // Android's AudioRecord buffer warm-up always starts with 2+ zero samples.
        // Also Android's exponential smoothing filter results in smooth transitions (avgStep <= 3.2).
        if leadingZeros >= 2 {
            return MediaDetectionResult(platform: .android, detail: "Android (AudioRecord latency signature)")
        }
        
        // 2. Desktop Signature:
        // Desktop (tdesktop) uses uncompressed mic capture without iOS VoiceProcessingIO AGC,
        // resulting in sharp transients with large max step differences.
        if maxStep >= 18 && avgStep > 3.5 {
            return MediaDetectionResult(platform: .desktop, detail: "Desktop (Direct PCM capture)")
        }
        
        // 3. iOS Signature:
        // iOS AudioUnit VoiceProcessingIO starts warm with ambient AGC noise (leadingZeros <= 1),
        // with standard peak normalization across 100 samples.
        if leadingZeros <= 1 && maxSample >= 12 {
            return MediaDetectionResult(platform: .ios, detail: "iOS (VoiceProcessingIO AGC signature)")
        }
        
        // Fallback checks
        if trailingZeros >= 2 && totalZeros > 5 {
            return MediaDetectionResult(platform: .android, detail: "Android (Audio buffer flush)")
        }
        
        return MediaDetectionResult(platform: .ios, detail: "iOS (Waveform profile)")
    }
    
    // MARK: - Video Note Detection
    
    private static func detectVideoNote(file: TelegramMediaFile) -> MediaDetectionResult? {
        guard let rep = file.previewRepresentations.first else { return nil }
        let w = Int(rep.dimensions.width)
        let h = Int(rep.dimensions.height)
        
        if w == 400 || h == 400 || w == 360 || h == 360 {
            return MediaDetectionResult(platform: .android, detail: "Android (Camera2 round note: \(w)x\(h))")
        }
        if w == 384 || h == 384 {
            return MediaDetectionResult(platform: .ios, detail: "iOS (AVFoundation round note: \(w)x\(h))")
        }
        return nil
    }
    
    // MARK: - Photo Detection
    
    private static func detectImage(image: TelegramMediaImage) -> MediaDetectionResult? {
        // Live Photo / Animated photo check
        if image.video != nil || !image.videoRepresentations.isEmpty {
            return MediaDetectionResult(platform: .ios, detail: "iOS (Live Photo)")
        }
        
        guard let maxRep = image.representations.max(by: { $0.dimensions.width * $0.dimensions.height < $1.dimensions.width * $1.dimensions.height }) else {
            return nil
        }
        
        let w = Int(maxRep.dimensions.width)
        let h = Int(maxRep.dimensions.height)
        guard w > 0, h > 0 else { return nil }
        
        let longSide = max(w, h)
        let shortSide = min(w, h)
        let ratio = Double(longSide) / Double(shortSide)
        let isLandscape = w > h
        
        // 1. Android Screen Signatures (20:9, 20.5:9, 21:9):
        // 20:9 is exclusive to Android phones (Samsung, Xiaomi, Pixel, OnePlus: 1080x2400 downscaled to 576x1280).
        if longSide == 1280 && (shortSide >= 574 && shortSide <= 578) {
            return MediaDetectionResult(platform: .android, detail: "Android (20:9 screen: \(w)x\(h))")
        }
        if ratio >= 2.215 && ratio <= 2.235 {
            return MediaDetectionResult(platform: .android, detail: "Android (20:9 display: \(w)x\(h))")
        }
        // 20.5:9 Samsung screens (1440x3088 -> 598x1280 or 562x1280)
        if longSide == 1280 && (shortSide >= 558 && shortSide <= 565) {
            return MediaDetectionResult(platform: .android, detail: "Android (20.5:9 Samsung screen: \(w)x\(h))")
        }
        // 21:9 Sony Xperia phones
        if longSide == 1280 && (shortSide >= 545 && shortSide <= 552) {
            return MediaDetectionResult(platform: .android, detail: "Android (21:9 Sony screen: \(w)x\(h))")
        }
        // 19:9 Android screens
        if longSide == 1280 && (shortSide >= 600 && shortSide <= 610) {
            return MediaDetectionResult(platform: .android, detail: "Android (19:9 screen: \(w)x\(h))")
        }
        
        // 2. iOS Screen Signatures:
        // iPhone 19.5:9 screens (iPhone X through 16: 1170x2532 / 1179x2556 / 1284x2778 downscaled to 591x1280 or 592x1280).
        if longSide == 1280 && (shortSide == 591 || shortSide == 592) {
            return MediaDetectionResult(platform: .ios, detail: "iOS (iPhone 19.5:9 screen: \(w)x\(h))")
        }
        if ratio >= 2.160 && ratio <= 2.174 && (shortSide >= 588 && shortSide <= 595) {
            return MediaDetectionResult(platform: .ios, detail: "iOS (iPhone screen: \(w)x\(h))")
        }
        // iPad Pro 11" screen (2388x1668 downscaled to 1280x894)
        if longSide == 1280 && (shortSide >= 892 && shortSide <= 896) {
            return MediaDetectionResult(platform: .ios, detail: "iOS (iPad Pro 11\" screen: \(w)x\(h))")
        }
        
        // 3. Desktop Screen Signatures:
        // MacBook 16:10 Retina screens (2560x1600, 2880x1800 downscaled to 1280x800)
        if isLandscape && longSide == 1280 && shortSide == 800 {
            return MediaDetectionResult(platform: .desktop, detail: "Desktop (Mac 16:10 display: 1280x800)")
        }
        // Ultrawide PC monitors (21:9: 2560x1080 / 3440x1440 downscaled to 1280x536)
        if isLandscape && longSide == 1280 && (shortSide >= 533 && shortSide <= 540) {
            return MediaDetectionResult(platform: .desktop, detail: "Desktop (21:9 Ultrawide display: \(w)x\(h))")
        }
        // Super Ultrawide PC monitors (32:9: 5120x1440 downscaled to 1280x360)
        if isLandscape && longSide == 1280 && (shortSide >= 355 && shortSide <= 365) {
            return MediaDetectionResult(platform: .desktop, detail: "Desktop (32:9 Monitor: \(w)x\(h))")
        }
        // Standard 16:9 PC monitor screenshot (1920x1080 / 2560x1440 downscaled to 1280x720)
        if isLandscape && longSide == 1280 && shortSide == 720 {
            return MediaDetectionResult(platform: .desktop, detail: "Desktop (16:9 Display: 1280x720)")
        }
        
        // 4. Camera Photos (Standard 4:3 ratio: 1280x960):
        if longSide == 1280 && shortSide == 960 {
            if let thumb = image.immediateThumbnailData, !thumb.isEmpty {
                // Stripped thumbnail analysis: Apple ImageIO vs Android libjpeg-turbo
                if thumb.count <= 110 {
                    return MediaDetectionResult(platform: .ios, detail: "iOS (Camera 4:3)")
                } else {
                    return MediaDetectionResult(platform: .android, detail: "Android (Camera 4:3)")
                }
            }
        }
        
        return nil
    }
}
