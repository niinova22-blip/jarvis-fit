import Foundation

/// Form problems that can be detected reliably from a single 2D camera in the stated view.
public enum FormIssue: String, Codable, CaseIterable, Sendable {
    case squatTooShallow
    case squatKneesCaveIn
    case squatTorsoLean
    case pushUpTooShallow
    case pushUpHipsSag
    case pushUpHipsPike
    case lungeTooShallow
    case lungeTorsoLean
    case jackArmsLow
    case jackLegsNarrow
    case plankHipsSag
    case plankHipsPike
    case curlElbowSwing
    case curlPartialExtension
    case pressPartialLockout
    case raiseTooHigh
    case raiseUneven
    case bridgeTooLow
    case tooFast

    /// Spoken/visual cue for the issue.
    public var cue: LocalizedText {
        switch self {
        case .squatTooShallow: return LocalizedText(tr: "Biraz daha derine in.", en: "Go a little deeper.")
        case .squatKneesCaveIn: return LocalizedText(tr: "Dizlerini dışarı doğru it.", en: "Push your knees out.")
        case .squatTorsoLean: return LocalizedText(tr: "Göğsünü yukarıda tut.", en: "Keep your chest up.")
        case .pushUpTooShallow: return LocalizedText(tr: "Göğsünü yere biraz daha yaklaştır.", en: "Lower your chest a bit more.")
        case .pushUpHipsSag: return LocalizedText(tr: "Kalçan düşüyor, karnını sık.", en: "Hips are sagging, brace your core.")
        case .pushUpHipsPike: return LocalizedText(tr: "Kalçanı biraz indir, vücudun düz olsun.", en: "Lower your hips, keep a straight line.")
        case .lungeTooShallow: return LocalizedText(tr: "Arka dizini yere biraz daha yaklaştır.", en: "Drop your back knee a little lower.")
        case .lungeTorsoLean: return LocalizedText(tr: "Gövdeni dik tut.", en: "Keep your torso upright.")
        case .jackArmsLow: return LocalizedText(tr: "Kollarını başının üstüne kadar kaldır.", en: "Bring your arms all the way overhead.")
        case .jackLegsNarrow: return LocalizedText(tr: "Ayaklarını biraz daha aç.", en: "Jump your feet wider.")
        case .plankHipsSag: return LocalizedText(tr: "Kalçan düşüyor, biraz yukarı al.", en: "Hips are dropping, lift them slightly.")
        case .plankHipsPike: return LocalizedText(tr: "Kalçan çok yüksek, biraz indir.", en: "Hips are too high, lower them a bit.")
        case .curlElbowSwing: return LocalizedText(tr: "Dirseklerini gövdene sabitle.", en: "Keep your elbows pinned to your sides.")
        case .curlPartialExtension: return LocalizedText(tr: "Kolunu aşağıda tamamen aç.", en: "Fully extend your arms at the bottom.")
        case .pressPartialLockout: return LocalizedText(tr: "Kollarını yukarıda tamamen uzat.", en: "Press all the way up.")
        case .raiseTooHigh: return LocalizedText(tr: "Omuz hizasında dur.", en: "Stop at shoulder height.")
        case .raiseUneven: return LocalizedText(tr: "İki kolunu eşit kaldır.", en: "Raise both arms evenly.")
        case .bridgeTooLow: return LocalizedText(tr: "Kalçanı biraz daha yukarı it.", en: "Drive your hips a bit higher.")
        case .tooFast: return LocalizedText(tr: "Biraz yavaşla, hareketi kontrollü yap.", en: "Slow down and control the movement.")
        }
    }

    /// The camera view in which the issue can be assessed.
    public var requiredView: CameraView? {
        switch self {
        case .squatKneesCaveIn, .jackArmsLow, .jackLegsNarrow, .raiseUneven: return .front
        case .squatTorsoLean, .pushUpHipsSag, .pushUpHipsPike, .lungeTorsoLean, .plankHipsSag, .plankHipsPike, .bridgeTooLow:
            return .side
        default: return nil
        }
    }
}
