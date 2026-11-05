import Foundation

/// Exercises the Live Coach can track with the camera.
public enum TrackedExercise: String, CaseIterable, Codable, Sendable {
    case squat, pushUp, lunge, jumpingJack, plank, bicepsCurl, shoulderPress, lateralRaise, gluteBridge, crunch

    public var name: LocalizedText {
        switch self {
        case .squat: return LocalizedText(tr: "Squat", en: "Squat")
        case .pushUp: return LocalizedText(tr: "Şınav", en: "Push-up")
        case .lunge: return LocalizedText(tr: "Lunge", en: "Lunge")
        case .jumpingJack: return LocalizedText(tr: "Jumping jack", en: "Jumping jack")
        case .plank: return LocalizedText(tr: "Plank", en: "Plank")
        case .bicepsCurl: return LocalizedText(tr: "Biceps curl", en: "Biceps curl")
        case .shoulderPress: return LocalizedText(tr: "Omuz press", en: "Shoulder press")
        case .lateralRaise: return LocalizedText(tr: "Yana açış", en: "Lateral raise")
        case .gluteBridge: return LocalizedText(tr: "Glute bridge", en: "Glute bridge")
        case .crunch: return LocalizedText(tr: "Mekik (crunch)", en: "Crunch")
        }
    }

    /// Time-based exercises are held, not counted.
    public var isTimed: Bool { self == .plank }

    /// Camera placement that gives the most reliable tracking.
    public var preferredView: CameraView {
        switch self {
        case .pushUp, .plank, .gluteBridge, .crunch: return .side
        case .squat, .lunge: return .side
        case .jumpingJack, .bicepsCurl, .shoulderPress, .lateralRaise: return .front
        }
    }

    /// Whether the exercise can also be counted from the other view (with reduced form feedback).
    public var acceptsAnyView: Bool {
        switch self {
        case .squat, .bicepsCurl, .shoulderPress, .lunge: return true
        default: return false
        }
    }

    public var expectedOrientation: BodyOrientation {
        switch self {
        case .pushUp, .plank, .gluteBridge, .crunch: return .horizontal
        default: return .standing
        }
    }

    /// Joints that must be visible to analyse the exercise.
    public var requiredJoints: [Joint] {
        switch self {
        case .squat, .lunge:
            return [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder]
        case .pushUp:
            return [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip]
        case .plank:
            return [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        case .jumpingJack:
            return [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        case .bicepsCurl, .shoulderPress:
            return [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case .lateralRaise:
            return [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftHip, .rightHip]
        case .gluteBridge, .crunch:
            return [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee]
        }
    }

    /// In side view only one body side needs to be visible.
    public var minimumVisibleFraction: Double {
        preferredView == .side ? 0.5 : 0.75
    }

    /// Form aspects that a single 2D camera cannot judge reliably for this exercise. The coach
    /// never gives corrections about these; they are listed in the UI as "not assessed".
    public var unassessableFormAspects: [LocalizedText] {
        switch self {
        case .squat:
            return [LocalizedText(tr: "Ağırlığın topukta olup olmadığı", en: "Weight distribution over heels"),
                    LocalizedText(tr: "Bel bölgesinin yuvarlanması (yandan bakış dışında)", en: "Lower-back rounding (outside side view)")]
        case .pushUp:
            return [LocalizedText(tr: "Dirseklerin gövdeye açısı (önden)", en: "Elbow flare (needs a top view)")]
        case .lunge:
            return [LocalizedText(tr: "Ön dizin içe kaçması (yandan bakışta)", en: "Front knee caving (in side view)")]
        case .jumpingJack:
            return [LocalizedText(tr: "İniş yumuşaklığı", en: "Landing softness")]
        case .plank:
            return [LocalizedText(tr: "Karın kaslarının aktif olup olmadığı", en: "Core bracing")]
        case .bicepsCurl:
            return [LocalizedText(tr: "Bilek bükülmesi", en: "Wrist curling")]
        case .shoulderPress:
            return [LocalizedText(tr: "Bel çukurluğunun artması (önden)", en: "Lower-back arching (from the front)")]
        case .lateralRaise:
            return [LocalizedText(tr: "Omuz silkme", en: "Shoulder shrugging")]
        case .gluteBridge:
            return [LocalizedText(tr: "Kalça kaslarının aktivasyonu", en: "Glute activation")]
        case .crunch:
            return [LocalizedText(tr: "Boyun çekme ve form ayrıntıları (yalnızca tekrar sayılır)", en: "Neck pulling and form details (reps only)")]
        }
    }

    public var setupInstruction: LocalizedText {
        switch preferredView {
        case .side:
            return LocalizedText(tr: "Telefonu yere, yan tarafına yaklaşık iki buçuk metre uzağa koy. Tüm vücudun görünsün.",
                                 en: "Place the phone on the floor about two and a half meters to your side so your whole body is visible.")
        default:
            return LocalizedText(tr: "Telefonu bel hizasında, karşına yaklaşık iki metre uzağa koy. Baştan ayağa görünmelisin.",
                                 en: "Place the phone at waist height about two meters in front of you. You should be visible head to toe.")
        }
    }
}
