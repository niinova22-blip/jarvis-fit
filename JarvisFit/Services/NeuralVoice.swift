import Foundation
import AVFoundation
import OnnxRuntimeBindings
import JarvisCore

/// JARVIS's own on-device voice: a Piper (VITS) model run with ONNX Runtime.
/// Text -> SpeechText.prepare (caller) -> Phonemizer -> phoneme ids -> model -> 22.05 kHz audio.
/// Bundled files: `<name>.onnx`, `<name>.onnx.json` and, for English, `en_lexicon.tsv`.
final class NeuralVoice: @unchecked Sendable {
    let language: AppLanguage
    let format: AVAudioFormat
    private let env: ORTEnv
    private let session: ORTSession
    private let config: NeuralVoiceConfig
    private let lexicon: [String: String]
    private let lock = NSLock()

    /// Nil when the model is not bundled (the app then uses Apple voices).
    static func load(language: AppLanguage, bundle: Bundle = .main) -> NeuralVoice? {
        let name = NeuralVoiceCatalog.modelName(for: language)
        guard let model = bundle.url(forResource: name, withExtension: "onnx"),
              let configURL = bundle.url(forResource: "\(name).onnx", withExtension: "json") else { return nil }
        do {
            let config = try NeuralVoiceConfig(json: Data(contentsOf: configURL))
            var lexicon: [String: String] = [:]
            if language == .english {
                guard let url = bundle.url(forResource: "en_lexicon", withExtension: "tsv") else { return nil }
                lexicon = Phonemizer.loadLexicon(try String(contentsOf: url, encoding: .utf8))
            }
            return try NeuralVoice(language: language, modelPath: model.path, config: config, lexicon: lexicon)
        } catch {
            print("[NeuralVoice] load failed: \(error)")
            return nil
        }
    }

    private init(language: AppLanguage, modelPath: String, config: NeuralVoiceConfig, lexicon: [String: String]) throws {
        self.language = language
        self.config = config
        self.lexicon = lexicon
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        format = AVAudioFormat(standardFormatWithSampleRate: config.sampleRate, channels: 1)!
    }

    /// Synthesises one sentence (already prepared with SpeechText). Call off the main thread.
    func synthesize(_ sentence: String, rate: Double) -> AVAudioPCMBuffer? {
        let phonemes = language == .turkish ? Phonemizer.turkish(sentence) : Phonemizer.english(sentence, lexicon: lexicon)
        let ids = Phonemizer.phonemeIds(phonemes, idMap: config.phonemeIdMap).map(Int64.init)
        guard ids.count > 3 else { return nil }
        do {
            let input = try ORTValue(tensorData: Self.data(ids), elementType: .int64, shape: [1, NSNumber(value: ids.count)])
            let lengths = try ORTValue(tensorData: Self.data([Int64(ids.count)]), elementType: .int64, shape: [1])
            let scales = try ORTValue(tensorData: Self.data([config.noiseScale, config.lengthScale(rate: rate), config.noiseW]),
                                      elementType: .float, shape: [3])
            lock.lock()
            defer { lock.unlock() }
            let outputs = try session.run(withInputs: ["input": input, "input_lengths": lengths, "scales": scales],
                                          outputNames: ["output"], runOptions: nil)
            guard let output = outputs["output"] else { return nil }
            let data = try output.tensorData() as Data
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
            buffer.frameLength = AVAudioFrameCount(count)
            let channel = buffer.floatChannelData![0]
            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Float.self)
                for i in 0..<count { channel[i] = max(-1, min(1, samples[i])) }
            }
            return buffer
        } catch {
            print("[NeuralVoice] synthesis failed: \(error)")
            return nil
        }
    }

    private static func data<T>(_ values: [T]) -> NSMutableData {
        values.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
    }
}

/// Cancellation flag shared between the main actor and the synthesis queue.
final class SynthesisToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}
