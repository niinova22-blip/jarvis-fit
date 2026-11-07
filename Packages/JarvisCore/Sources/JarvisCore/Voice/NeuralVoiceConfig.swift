import Foundation

/// The parts of a Piper voice config (`<model>.onnx.json`) the app needs to run the model.
public struct NeuralVoiceConfig: Equatable, Sendable {
    public var sampleRate: Double
    public var phonemeIdMap: [String: Int]
    public var noiseScale: Float
    public var lengthScale: Float
    public var noiseW: Float

    public init(sampleRate: Double, phonemeIdMap: [String: Int], noiseScale: Float = 0.667, lengthScale: Float = 1, noiseW: Float = 0.8) {
        self.sampleRate = sampleRate
        self.phonemeIdMap = phonemeIdMap
        self.noiseScale = noiseScale
        self.lengthScale = lengthScale
        self.noiseW = noiseW
    }

    public init(json data: Data) throws {
        struct Raw: Decodable {
            struct Audio: Decodable { var sample_rate: Double }
            struct Inference: Decodable { var noise_scale: Float?; var length_scale: Float?; var noise_w: Float? }
            var audio: Audio
            var inference: Inference?
            var phoneme_id_map: [String: [Int]]
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        self.init(sampleRate: raw.audio.sample_rate,
                  phonemeIdMap: raw.phoneme_id_map.compactMapValues { $0.first },
                  noiseScale: raw.inference?.noise_scale ?? 0.667,
                  lengthScale: raw.inference?.length_scale ?? 1,
                  noiseW: raw.inference?.noise_w ?? 0.8)
    }

    /// Piper's length scale for a speaking-rate multiplier (> 1 = faster = shorter).
    public func lengthScale(rate: Double) -> Float {
        lengthScale / Float(max(0.5, min(2, rate)))
    }
}

/// NOVA's own voices bundled with the app (trained by tools/voice; male voices).
public enum NeuralVoiceCatalog {
    public static func modelName(for language: AppLanguage) -> String {
        language == .turkish ? "jarvis_tr_george" : "jarvis_en_michael"
    }

    /// The bundled voices are male; they are used when a male voice is wanted and the user has not
    /// picked a specific system voice.
    public static func shouldUse(enabled: Bool, wantedGender: VoiceCandidate.Gender, manualVoicePicked: Bool) -> Bool {
        enabled && wantedGender == .male && !manualVoicePicked
    }
}
