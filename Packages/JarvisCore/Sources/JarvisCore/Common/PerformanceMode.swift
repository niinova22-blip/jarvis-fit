import Foundation

/// Camera / pose processing budget. "Light" mode is for older devices or thermal pressure.
public enum PerformancePreference: String, Codable, CaseIterable, Sendable {
    case automatic, high, light

    public var title: LocalizedText {
        switch self {
        case .automatic: return LocalizedText(tr: "Otomatik", en: "Automatic")
        case .high: return LocalizedText(tr: "Yüksek kalite", en: "High quality")
        case .light: return LocalizedText(tr: "Hafif mod (pil dostu)", en: "Light mode (battery saver)")
        }
    }
}

public struct ProcessingBudget: Equatable, Sendable {
    /// Frames per second captured by the camera.
    public var cameraFPS: Int
    /// Analyse every n-th captured frame.
    public var analyseEvery: Int
    /// Capture resolution (portrait height in pixels).
    public var resolution: Int
    public var isLight: Bool

    public var analysedFPS: Double { Double(cameraFPS) / Double(max(1, analyseEvery)) }

    public static let high = ProcessingBudget(cameraFPS: 30, analyseEvery: 1, resolution: 1280, isLight: false)
    public static let light = ProcessingBudget(cameraFPS: 30, analyseEvery: 2, resolution: 640, isLight: true)
    /// Severe thermal pressure: keep counting but at the minimum useful rate.
    public static let minimal = ProcessingBudget(cameraFPS: 15, analyseEvery: 1, resolution: 640, isLight: true)
}

public enum ThermalLevel: Int, Sendable { case nominal, fair, serious, critical }

public enum PerformancePolicy {
    /// Chooses the processing budget. Rep counting needs ≥ ~12 analysed fps for jumping jacks, so
    /// the minimum budget never drops below 15 fps.
    /// - Parameters:
    ///   - memoryGB: physical memory (iPhone 15 Pro: 8 GB; iPhone 12/13: 4 GB).
    ///   - measuredFPS: pose throughput measured during the current session (nil before measuring).
    public static func budget(preference: PerformancePreference, memoryGB: Double, thermal: ThermalLevel,
                              lowPowerMode: Bool, measuredFPS: Double? = nil) -> ProcessingBudget {
        if thermal == .critical { return .minimal }
        switch preference {
        case .high: return thermal == .serious ? .light : .high
        case .light: return thermal == .serious ? .minimal : .light
        case .automatic:
            if thermal == .serious || lowPowerMode || memoryGB < 5.5 { return .light }
            // Device can't keep up at full resolution → drop to light.
            if let measuredFPS, measuredFPS < 20 { return .light }
            return .high
        }
    }
}
