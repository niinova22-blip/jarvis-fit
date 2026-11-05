import Foundation

/// Per-exercise signals and thresholds.
///
/// Thresholds are joint angles in degrees measured in the 2D image (aspect-ratio corrected).
/// They are starting values from biomechanics references (e.g. parallel squat ≈ 90–100° knee
/// flexion angle) and must be validated with recorded real-device sessions — see
/// docs/DEVICE_TESTING.md. The rep counter relaxes the start threshold per user (perspective).
extension RepExerciseSpec {
    public static func spec(for exercise: TrackedExercise, view: CameraView) -> RepExerciseSpec {
        switch exercise {
        case .squat: return view == .front ? squatFront : squatSide
        case .pushUp: return pushUp
        case .lunge: return lunge
        case .jumpingJack: return jumpingJack
        case .bicepsCurl: return bicepsCurl
        case .shoulderPress: return shoulderPress
        case .lateralRaise: return lateralRaise
        case .gluteBridge: return gluteBridge
        case .crunch: return crunch
        case .plank:
            preconditionFailure("Plank is timed; use PlankAnalyzer")
        }
    }

    static let noChecks: (PoseFeatures, RepPhase) -> [FormIssue] = { _, _ in [] }
    static let noExtremeCheck: (Double) -> FormIssue? = { _ in nil }

    // MARK: Squat

    /// Side view: knee angle (hip–knee–ankle) of the visible leg.
    static let squatSide = RepExerciseSpec(
        exercise: .squat,
        config: RepSignalConfig(startThreshold: 160, turnThreshold: 100, controlledRepDuration: 1.0),
        signal: { f in
            guard f.orientation != .horizontal else { return nil }
            return f.bilateral({ f.kneeAngle($0) }, combine: min)
        },
        frameChecks: { f, phase in
            guard phase == .turn || phase == .returning, let lean = f.torsoLean else { return [] }
            // Some forward lean is normal; beyond ~50° at the bottom the chest is collapsing.
            return lean > 50 ? [.squatTorsoLean] : []
        },
        partialIssue: .squatTooShallow,
        extremeCheck: noExtremeCheck
    )

    /// Front view: knee angles are foreshortened, so depth is the vertical hip-above-knee extent
    /// relative to the vertical knee-above-ankle extent (≈1 standing, ≈0 with thighs parallel;
    /// 0.6 ≈ 85–90° knee angle). Knee valgus is checked here.
    static let squatFront = RepExerciseSpec(
        exercise: .squat,
        config: RepSignalConfig(startThreshold: 0.85, turnThreshold: 0.6, controlledRepDuration: 1.0, startTolerance: 0.12),
        signal: { f in squatDepthRatio(f) },
        frameChecks: { f, phase in
            guard phase == .turn || phase == .returning, let ratio = f.kneeToAnkleWidthRatio else { return [] }
            return ratio < 0.75 ? [.squatKneesCaveIn] : []
        },
        partialIssue: .squatTooShallow,
        extremeCheck: noExtremeCheck
    )

    public static func squatDepthRatio(_ f: PoseFeatures) -> Double? {
        guard f.orientation != .horizontal else { return nil }
        func ratio(_ side: Side) -> Double? {
            guard let hip = f.frame.point(.hip(side)), let knee = f.frame.point(.knee(side)),
                  let ankle = f.frame.point(.ankle(side)) else { return nil }
            let shin = ankle.y - knee.y
            guard shin > 1e-4 else { return nil }
            return (knee.y - hip.y) / shin
        }
        return f.bilateral(ratio)
    }

    // MARK: Push-up

    static let pushUp = RepExerciseSpec(
        exercise: .pushUp,
        config: RepSignalConfig(startThreshold: 150, turnThreshold: 100, controlledRepDuration: 0.8),
        signal: { f in
            guard f.orientation == .horizontal else { return nil }
            return f.bilateral({ f.elbowAngle($0) }, combine: min)
        },
        frameChecks: { f, _ in
            let side = f.bestSide { [.shoulder($0), .hip($0), .ankle($0)] }
            guard let line = f.bodyLine(side), line < 162,
                  let s = f.frame.point(.shoulder(side)), let h = f.frame.point(.hip(side)),
                  let a = f.frame.point(.ankle(side)) else { return [] }
            return [PlankAnalyzer.hipDeviation(shoulder: s, hip: h, foot: a) == .plankHipsSag ? .pushUpHipsSag : .pushUpHipsPike]
        },
        partialIssue: .pushUpTooShallow,
        extremeCheck: noExtremeCheck
    )

    // MARK: Lunge

    static let lunge = RepExerciseSpec(
        exercise: .lunge,
        config: RepSignalConfig(startThreshold: 155, turnThreshold: 110, controlledRepDuration: 1.0),
        signal: { f in
            guard f.orientation != .horizontal else { return nil }
            // The front leg bends the most; both legs bend in a lunge, unlike a squat stance width.
            return f.bilateral({ f.kneeAngle($0) }, combine: min)
        },
        frameChecks: { f, phase in
            guard phase == .turn, let lean = f.torsoLean else { return [] }
            return lean > 30 ? [.lungeTorsoLean] : []
        },
        partialIssue: .lungeTooShallow,
        extremeCheck: noExtremeCheck
    )

    // MARK: Jumping jack

    static let jumpingJack = RepExerciseSpec(
        exercise: .jumpingJack,
        config: RepSignalConfig(startThreshold: 45, turnThreshold: 135, partialFraction: 0.5,
                                minRepDuration: 0.3, controlledRepDuration: 0, startTolerance: 20),
        signal: { f in
            guard f.orientation == .standing else { return nil }
            return f.bilateral({ f.armElevation($0) })
        },
        frameChecks: { f, phase in
            guard phase == .turn, let width = f.stanceWidthRatio else { return [] }
            return width < 1.5 ? [.jackLegsNarrow] : []
        },
        partialIssue: .jackArmsLow,
        extremeCheck: noExtremeCheck,
        issueFrameShare: 0.15
    )

    // MARK: Biceps curl

    static let bicepsCurl = RepExerciseSpec(
        exercise: .bicepsCurl,
        config: RepSignalConfig(startThreshold: 145, turnThreshold: 70, controlledRepDuration: 0.8, startTolerance: 20),
        signal: { f in
            guard f.orientation == .standing else { return nil }
            return f.bilateral({ f.elbowAngle($0) }, combine: min)
        },
        frameChecks: { f, phase in
            guard phase != .start else { return [] }
            // Upper arm should stay close to vertical; swinging moves the elbow forward/up.
            let swinging = [Side.left, .right].contains { side in
                guard let shoulder = f.frame.point(.shoulder(side)), let elbow = f.frame.point(.elbow(side)),
                      let elbowAngle = f.elbowAngle(side), elbowAngle < 120 else { return false }
                return Geometry.angleFromVertical(shoulder, elbow) > 35
            }
            return swinging ? [.curlElbowSwing] : []
        },
        partialIssue: nil,
        extremeCheck: noExtremeCheck
    )

    // MARK: Shoulder press

    static let shoulderPress = RepExerciseSpec(
        exercise: .shoulderPress,
        config: RepSignalConfig(startThreshold: 105, turnThreshold: 155, controlledRepDuration: 0.8, startTolerance: 20),
        signal: { f in
            guard f.orientation == .standing else { return nil }
            func pressAngle(_ side: Side) -> Double? {
                guard let wrist = f.frame.point(.wrist(side)), let elbow = f.frame.point(.elbow(side)),
                      wrist.y < elbow.y else { return nil } // hands above elbows = pressing position
                return f.elbowAngle(side)
            }
            return f.bilateral(pressAngle, combine: min)
        },
        frameChecks: noChecks,
        partialIssue: .pressPartialLockout,
        extremeCheck: noExtremeCheck
    )

    // MARK: Lateral raise

    static let lateralRaise = RepExerciseSpec(
        exercise: .lateralRaise,
        config: RepSignalConfig(startThreshold: 30, turnThreshold: 75, controlledRepDuration: 0.9),
        signal: { f in
            guard f.orientation == .standing else { return nil }
            return f.bilateral({ f.shoulderAbduction($0) })
        },
        frameChecks: { f, phase in
            guard phase == .turn, let l = f.shoulderAbduction(.left), let r = f.shoulderAbduction(.right) else { return [] }
            return abs(l - r) > 25 ? [.raiseUneven] : []
        },
        partialIssue: nil,
        extremeCheck: { $0 > 115 ? .raiseTooHigh : nil }
    )

    // MARK: Glute bridge

    static let gluteBridge = RepExerciseSpec(
        exercise: .gluteBridge,
        config: RepSignalConfig(startThreshold: 145, turnThreshold: 165, partialFraction: 0.4,
                                controlledRepDuration: 0.8, startTolerance: 10),
        signal: { f in
            guard f.orientation == .horizontal else { return nil }
            let side = f.bestSide { [.shoulder($0), .hip($0), .knee($0)] }
            // Knees must be bent (feet on the floor) to distinguish from a plank.
            guard let knee = f.kneeAngle(side), knee < 130 else { return nil }
            return f.hipAngle(side)
        },
        frameChecks: noChecks,
        partialIssue: .bridgeTooLow,
        extremeCheck: noExtremeCheck
    )

    // MARK: Crunch (rep counting only — form is not assessed)

    static let crunch = RepExerciseSpec(
        exercise: .crunch,
        config: RepSignalConfig(startThreshold: 120, turnThreshold: 105, partialFraction: 0.6,
                                minRepDuration: 0.4, controlledRepDuration: 0.6, startTolerance: 12),
        signal: { f in
            guard f.orientation == .horizontal else { return nil }
            let side = f.bestSide { [.shoulder($0), .hip($0), .knee($0)] }
            guard let knee = f.kneeAngle(side), knee < 130 else { return nil }
            return f.hipAngle(side)
        },
        frameChecks: noChecks,
        partialIssue: nil,
        extremeCheck: noExtremeCheck
    )
}
