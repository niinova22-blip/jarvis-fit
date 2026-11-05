import Foundation

/// Binary person mask (1 = person) from a segmentation model, row-major, origin top-left.
public struct SilhouetteMask: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func isPerson(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return pixels[y * width + x] > 0
    }

    /// Contiguous run of person pixels on row `y` that contains `x` (or the nearest run).
    public func run(row y: Int, containing x: Int) -> (start: Int, end: Int)? {
        guard y >= 0 && y < height else { return nil }
        var seed = x
        if !isPerson(seed, y) {
            // Search nearby (up to 3% of the width) for the run.
            let radius = max(2, width / 33)
            guard let found = (1...radius).lazy.flatMap({ [x - $0, x + $0] }).first(where: { isPerson($0, y) }) else { return nil }
            seed = found
        }
        var start = seed, end = seed
        while isPerson(start - 1, y) { start -= 1 }
        while isPerson(end + 1, y) { end += 1 }
        return (start, end)
    }

    public func runWidth(row y: Int, containing x: Int) -> Int? {
        run(row: y, containing: x).map { $0.end - $0.start + 1 }
    }

    /// Topmost and bottommost rows containing person pixels.
    public var verticalExtent: (top: Int, bottom: Int)? {
        var top: Int?
        var bottom: Int?
        for y in 0..<height where pixels[(y * width)..<((y + 1) * width)].contains(where: { $0 > 0 }) {
            if top == nil { top = y }
            bottom = y
        }
        guard let top, let bottom else { return nil }
        return (top, bottom)
    }
}

public enum MeasurementSite: String, Codable, CaseIterable, Sendable {
    case chest, waist, hips, thigh, upperArm

    public var title: LocalizedText {
        switch self {
        case .chest: return LocalizedText(tr: "Göğüs", en: "Chest")
        case .waist: return LocalizedText(tr: "Bel", en: "Waist")
        case .hips: return LocalizedText(tr: "Kalça", en: "Hips")
        case .thigh: return LocalizedText(tr: "Uyluk", en: "Thigh")
        case .upperArm: return LocalizedText(tr: "Üst kol", en: "Upper arm")
        }
    }

    /// Relative uncertainty (±) of a camera estimate before and after tape calibration. Limbs are
    /// less reliable: their depth is not visible in the side photo, so a round section is assumed.
    public func relativeUncertainty(calibrated: Bool) -> Double {
        switch self {
        case .chest, .waist, .hips: return calibrated ? 0.03 : 0.07
        case .thigh: return calibrated ? 0.05 : 0.10
        case .upperArm: return calibrated ? 0.06 : 0.12
        }
    }
}

/// Body landmarks in mask pixel coordinates (from the pose detector on the same photo).
public struct ScanLandmarks: Sendable {
    public var shoulderY: Double
    public var hipY: Double
    public var kneeY: Double
    public var centerX: Double
    /// x of one thigh (front photo) between hip and knee.
    public var thighX: Double?
    /// Midpoint between shoulder and elbow of one arm (front photo, arms held away from the body).
    public var upperArmPoint: (x: Double, y: Double)?

    public init(shoulderY: Double, hipY: Double, kneeY: Double, centerX: Double, thighX: Double? = nil, upperArmPoint: (x: Double, y: Double)? = nil) {
        self.shoulderY = shoulderY
        self.hipY = hipY
        self.kneeY = kneeY
        self.centerX = centerX
        self.thighX = thighX
        self.upperArmPoint = upperArmPoint
    }
}

public struct MeasurementEstimate: Codable, Hashable, Sendable {
    public var site: MeasurementSite
    public var valueCm: Double
    public var lowCm: Double
    public var highCm: Double
    public var calibrated: Bool

    /// Display string such as "≈ 84 cm (81–87)".
    public func display() -> String {
        "≈ \(Int(valueCm.rounded())) cm (\(Int(lowCm.rounded()))–\(Int(highCm.rounded())))"
    }
}

/// Estimates circumferences from a front and a side silhouette and the user's height.
///
/// Width (front) and depth (side) at each site are converted to centimetres with the scale
/// height_cm / silhouette_height_px, then the cross-section is approximated as an ellipse
/// (Ramanujan's perimeter). Results are estimates with an explicit range; a one-time tape
/// measurement per site removes most of the systematic error (`calibrationFactors`).
public struct BodyMeasurementEstimator: Sendable {
    public init() {}

    public static func ellipsePerimeter(width: Double, depth: Double) -> Double {
        let a = width / 2, b = depth / 2
        return .pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
    }

    /// Body cross-sections are rounder-cornered than an ellipse in the torso; this empirical
    /// shape factor is a starting value and is replaced by tape calibration when available.
    static let shapeFactor: [MeasurementSite: Double] = [.chest: 1.0, .waist: 1.0, .hips: 1.0, .thigh: 1.0, .upperArm: 1.0]

    struct SiteWidths {
        var widthPx: Double
        var depthPx: Double?
    }

    public func estimate(front: SilhouetteMask, frontLandmarks: ScanLandmarks,
                         side: SilhouetteMask?, sideLandmarks: ScanLandmarks?,
                         heightCm: Double, calibrationFactors: [MeasurementSite: Double] = [:]) -> [MeasurementEstimate] {
        guard let frontExtent = front.verticalExtent else { return [] }
        let frontScale = heightCm / Double(frontExtent.bottom - frontExtent.top + 1)
        var sideScale: Double?
        if let side, let extent = side.verticalExtent { sideScale = heightCm / Double(extent.bottom - extent.top + 1) }

        func torsoRows(_ l: ScanLandmarks) -> (chest: Int, waistRange: ClosedRange<Int>, hipRange: ClosedRange<Int>) {
            let torso = l.hipY - l.shoulderY
            let chest = Int(l.shoulderY + torso * 0.28)
            let waistLow = Int(l.shoulderY + torso * 0.55), waistHigh = Int(l.shoulderY + torso * 0.85)
            let hipLow = Int(l.hipY - torso * 0.05), hipHigh = Int(l.hipY + torso * 0.25)
            return (chest, min(waistLow, waistHigh)...max(waistLow, waistHigh), min(hipLow, hipHigh)...max(hipLow, hipHigh))
        }

        func width(_ mask: SilhouetteMask, row: Int, x: Double) -> Double? { mask.runWidth(row: row, containing: Int(x)).map(Double.init) }

        var results: [MeasurementEstimate] = []
        let fr = torsoRows(frontLandmarks)
        let sr = sideLandmarks.map(torsoRows)

        func measure(_ site: MeasurementSite, frontPx: Double?, sidePx: Double?, assumeRound: Bool) {
            guard let frontPx, frontPx > 0 else { return }
            let widthCm = frontPx * frontScale
            let depthCm: Double
            if let sidePx, let sideScale { depthCm = sidePx * sideScale }
            else if assumeRound { depthCm = widthCm }
            else { return }
            let raw = Self.ellipsePerimeter(width: widthCm, depth: depthCm) * (Self.shapeFactor[site] ?? 1)
            let factor = calibrationFactors[site].map { min(1.25, max(0.8, $0)) }
            let value = raw * (factor ?? 1)
            let u = site.relativeUncertainty(calibrated: factor != nil)
            results.append(MeasurementEstimate(site: site, valueCm: value, lowCm: value * (1 - u), highCm: value * (1 + u), calibrated: factor != nil))
        }

        // Chest: single row below the armpits.
        measure(.chest, frontPx: width(front, row: fr.chest, x: frontLandmarks.centerX),
                sidePx: sr.flatMap { r in side.flatMap { width($0, row: r.chest, x: sideLandmarks!.centerX) } }, assumeRound: false)
        // Waist: narrowest front row in the waist band; side depth at the same relative height.
        let waistRows = fr.waistRange.compactMap { row in width(front, row: row, x: frontLandmarks.centerX).map { (row, $0) } }
        if let narrowest = waistRows.min(by: { $0.1 < $1.1 }) {
            var sideDepth: Double?
            if let side, let sideLandmarks {
                let relative = (Double(narrowest.0) - frontLandmarks.shoulderY) / (frontLandmarks.hipY - frontLandmarks.shoulderY)
                let row = Int(sideLandmarks.shoulderY + relative * (sideLandmarks.hipY - sideLandmarks.shoulderY))
                sideDepth = width(side, row: row, x: sideLandmarks.centerX)
            }
            measure(.waist, frontPx: narrowest.1, sidePx: sideDepth, assumeRound: false)
        }
        // Hips: widest front row in the hip band; deepest side row in the same band.
        let hipFront = fr.hipRange.compactMap { width(front, row: $0, x: frontLandmarks.centerX) }.max()
        let hipSide: Double? = {
            guard let side, let sideLandmarks, let r = sr else { return nil }
            return r.hipRange.compactMap { width(side, row: $0, x: sideLandmarks.centerX) }.max()
        }()
        measure(.hips, frontPx: hipFront, sidePx: hipSide, assumeRound: false)
        // Thigh: one leg, 30% of the way from hip to knee (round section assumed).
        if let thighX = frontLandmarks.thighX {
            let row = Int(frontLandmarks.hipY + (frontLandmarks.kneeY - frontLandmarks.hipY) * 0.3)
            measure(.thigh, frontPx: width(front, row: row, x: thighX), sidePx: nil, assumeRound: true)
        }
        // Upper arm: arm held away from the torso (A-pose) so its run is separate from the body.
        if let arm = frontLandmarks.upperArmPoint {
            measure(.upperArm, frontPx: width(front, row: Int(arm.y), x: arm.x), sidePx: nil, assumeRound: true)
        }
        return results
    }

    /// Calibration factor from a tape measurement taken at the same time as a scan.
    public static func calibrationFactor(tapeCm: Double, rawEstimateCm: Double) -> Double? {
        guard tapeCm > 10, rawEstimateCm > 10 else { return nil }
        let factor = tapeCm / rawEstimateCm
        // Outside this range the scan itself is likely wrong (clothing, pose); don't calibrate.
        return (0.8...1.25).contains(factor) ? factor : nil
    }
}

/// Simple posture indicators that a single photo can support.
public struct PostureReport: Codable, Hashable, Sendable {
    /// Degrees; positive = right shoulder lower (front photo).
    public var shoulderTiltDegrees: Double?
    /// Degrees; positive = right hip lower (front photo).
    public var hipTiltDegrees: Double?
    /// Horizontal ear-to-shoulder offset relative to torso length (side photo); larger = head further forward.
    public var forwardHeadRatio: Double?

    public static func analyze(front: PoseFrame?, side: PoseFrame?) -> PostureReport {
        var report = PostureReport()
        if let front {
            if let l = front.point(.leftShoulder), let r = front.point(.rightShoulder) {
                report.shoulderTiltDegrees = atan2(r.y - l.y, abs(r.x - l.x)) * 180 / .pi
            }
            if let l = front.point(.leftHip), let r = front.point(.rightHip) {
                report.hipTiltDegrees = atan2(r.y - l.y, abs(r.x - l.x)) * 180 / .pi
            }
        }
        if let side {
            let f = PoseFeatures(side)
            let s = f.bestSide { [.ear($0), .shoulder($0), .hip($0)] }
            if let ear = side.point(.ear(s)), let shoulder = side.point(.shoulder(s)), let torso = f.torsoLength, torso > 0 {
                report.forwardHeadRatio = abs(ear.x - shoulder.x) / torso
            }
        }
        return report
    }

    /// Observations worth mentioning (never diagnoses).
    public func observations() -> [LocalizedText] {
        var notes: [LocalizedText] = []
        if let tilt = shoulderTiltDegrees, abs(tilt) > 3 {
            notes.append(LocalizedText(tr: "Omuzların arasında yaklaşık \(Int(abs(tilt).rounded()))° yükseklik farkı görünüyor.",
                                       en: "There is about a \(Int(abs(tilt).rounded()))° height difference between your shoulders."))
        }
        if let tilt = hipTiltDegrees, abs(tilt) > 3 {
            notes.append(LocalizedText(tr: "Kalça hizanda yaklaşık \(Int(abs(tilt).rounded()))° fark görünüyor.",
                                       en: "Your hips appear about \(Int(abs(tilt).rounded()))° uneven."))
        }
        if let ratio = forwardHeadRatio, ratio > 0.18 {
            notes.append(LocalizedText(tr: "Başın omuz hizasının önünde duruyor olabilir.", en: "Your head may sit forward of your shoulders."))
        }
        if !notes.isEmpty {
            notes.append(LocalizedText(tr: "Bu tek fotoğraftan yapılan bir gözlemdir, teşhis değildir. Ağrın varsa bir uzmana danış.",
                                       en: "This is an observation from a single photo, not a diagnosis. If you have pain, consult a professional."))
        }
        return notes
    }
}
