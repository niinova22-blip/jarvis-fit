import Foundation

/// Guidance for placing the phone so the exercise can be tracked.
public enum FramingStatus: Equatable, Sendable {
    case noPerson
    case stepBack
    case stepCloser
    case moveLeft
    case moveRight
    case showFeet
    case showHead
    case turnSideways
    case faceCamera
    case getIntoPosition
    case ready

    public var cue: LocalizedText {
        switch self {
        case .noPerson: return LocalizedText(tr: "Seni göremiyorum. Kameranın karşısına geç.", en: "I can't see you. Step in front of the camera.")
        case .stepBack: return LocalizedText(tr: "Biraz geri çekil.", en: "Step back a little.")
        case .stepCloser: return LocalizedText(tr: "Biraz yaklaş.", en: "Come a little closer.")
        case .moveLeft: return LocalizedText(tr: "Biraz soluna kay.", en: "Move a little to your left.")
        case .moveRight: return LocalizedText(tr: "Biraz sağına kay.", en: "Move a little to your right.")
        case .showFeet: return LocalizedText(tr: "Ayaklarını göremiyorum, telefonu biraz aşağı eğ ya da geri çekil.", en: "I can't see your feet. Tilt the phone down or step back.")
        case .showHead: return LocalizedText(tr: "Başın kadrajın dışında, biraz geri çekil.", en: "Your head is out of frame, step back.")
        case .turnSideways: return LocalizedText(tr: "Bu hareket için kameraya yan dön.", en: "Turn sideways to the camera for this exercise.")
        case .faceCamera: return LocalizedText(tr: "Bu hareket için yüzünü kameraya dön.", en: "Face the camera for this exercise.")
        case .getIntoPosition: return LocalizedText(tr: "Başlangıç pozisyonuna geç.", en: "Get into the starting position.")
        case .ready: return LocalizedText(tr: "Harika, seni net görüyorum.", en: "Great, I can see you clearly.")
        }
    }
}

/// Checks whether the user is fully and suitably framed for an exercise.
public struct FramingGuide: Sendable {
    public var edgeMargin = 0.03

    public init() {}

    public func evaluate(_ frame: PoseFrame, for exercise: TrackedExercise) -> (status: FramingStatus, view: CameraView) {
        let visible = Joint.allCases.compactMap { joint -> Point2? in frame.imagePoint(joint) }
        guard visible.count >= 6 else { return (.noPerson, .unknown) }

        let features = PoseFeatures(frame)
        let required = exercise.requiredJoints
        let visibleRequired = required.filter { frame.isVisible($0) }.count
        let fraction = Double(visibleRequired) / Double(required.count)

        let minX = visible.map(\.x).min() ?? 0, maxX = visible.map(\.x).max() ?? 1
        let minY = visible.map(\.y).min() ?? 0, maxY = visible.map(\.y).max() ?? 1
        let width = maxX - minX, height = maxY - minY
        let extent = exercise.expectedOrientation == .horizontal ? max(width, height) : height

        if minY < edgeMargin && maxY > 1 - edgeMargin { return (.stepBack, features.view) }
        // Side-view exercises need every required joint of at least one body side.
        func sideComplete(_ side: Side) -> Bool {
            required.filter { $0.rawValue.hasPrefix(side.rawValue) }.allSatisfy { frame.isVisible($0) }
        }
        let missing = fraction < exercise.minimumVisibleFraction
            || (exercise.preferredView == .side && !sideComplete(.left) && !sideComplete(.right))
        if missing {
            let needsFeet = required.contains(.leftAnkle) || required.contains(.leftKnee)
            if needsFeet && !frame.isVisible(.leftAnkle) && !frame.isVisible(.rightAnkle) && !frame.isVisible(.leftKnee) {
                return (.showFeet, features.view)
            }
            if !frame.isVisible(.nose) && !frame.isVisible(.neck) { return (.showHead, features.view) }
            return (.stepBack, features.view)
        }
        if extent > 0.97 { return (.stepBack, features.view) }
        if extent < 0.3 { return (.stepCloser, features.view) }
        // Camera image is mirrored for the user: x < margin means the user should move to their left.
        if minX < edgeMargin { return (.moveLeft, features.view) }
        if maxX > 1 - edgeMargin { return (.moveRight, features.view) }

        let view = features.view
        if !exercise.acceptsAnyView && view != .unknown && view != exercise.preferredView {
            return (exercise.preferredView == .side ? .turnSideways : .faceCamera, view)
        }
        if exercise.expectedOrientation != .unknown && features.orientation != exercise.expectedOrientation {
            return (.getIntoPosition, view)
        }
        return (.ready, view)
    }
}
