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

/// Checks whether the camera sees enough of the user to count the exercise.
///
/// There is no required distance, phone height or camera angle: counting falls back to
/// view-independent signals (`AdaptiveSignalSpec`), so the guide only asks for the joints the
/// exercise really needs (`TrackedExercise.coreJoints`) and for the person not to be tiny.
/// Upper-body exercises work in a close-up; legs only need to be visible for leg exercises.
public struct FramingGuide: Sendable {
    /// Below this body height (fraction of the image) the person is too far to track reliably.
    public var minimumExtent = 0.12

    public init() {}

    public func evaluate(_ frame: PoseFrame, for exercise: TrackedExercise) -> (status: FramingStatus, view: CameraView) {
        let visible = Joint.allCases.compactMap { joint -> Point2? in frame.imagePoint(joint) }
        guard visible.count >= 4 else { return (.noPerson, .unknown) }
        let features = PoseFeatures(frame)

        let missing = exercise.coreJoints.filter { group in !group.contains { frame.isVisible($0) } }
        if let group = missing.first {
            let lowerBody: Set<Joint> = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
            if group.allSatisfy({ lowerBody.contains($0) }) { return (.showFeet, features.view) }
            if !frame.isVisible(.nose) && !frame.isVisible(.neck) && !frame.isVisible(.leftShoulder) && !frame.isVisible(.rightShoulder) {
                return (.showHead, features.view)
            }
            return (.stepBack, features.view)
        }

        let minY = visible.map(\.y).min() ?? 0, maxY = visible.map(\.y).max() ?? 1
        let minX = visible.map(\.x).min() ?? 0, maxX = visible.map(\.x).max() ?? 1
        if max(maxY - minY, maxX - minX) < minimumExtent { return (.stepCloser, features.view) }
        return (.ready, features.view)
    }
}
