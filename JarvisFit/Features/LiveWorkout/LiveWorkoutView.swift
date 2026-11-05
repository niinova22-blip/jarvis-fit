import SwiftUI
import AVFoundation
import JarvisCore

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let connection = uiView.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

/// Draws the tracked skeleton over the aspect-filled preview.
struct SkeletonOverlay: View {
    let frame: PoseFrame?
    let imageSize: CGSize
    let mirrored: Bool
    var highlight: Bool

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose)
    ]

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let offset = CGPoint(x: (size.width - imageSize.width * scale) / 2, y: (size.height - imageSize.height * scale) / 2)
            func map(_ joint: Joint) -> CGPoint? {
                guard let p = frame.imagePoint(joint) else { return nil }
                var x = p.x * imageSize.width * scale + offset.x
                if mirrored { x = size.width - x }
                return CGPoint(x: x, y: p.y * imageSize.height * scale + offset.y)
            }
            let color = highlight ? Theme.success : Theme.accent
            var path = Path()
            for (a, b) in Self.bones {
                if let pa = map(a), let pb = map(b) {
                    path.move(to: pa)
                    path.addLine(to: pb)
                }
            }
            context.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for joint in Joint.allCases where ![.leftEye, .rightEye, .leftEar, .rightEar].contains(joint) {
                if let p = map(joint) {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: LiveWorkoutController
    @ObservedObject private var voice: VoiceCoordinator
    @State private var repPulse = false

    init(plan: LiveWorkoutPlan, planned: PlannedWorkout?, model: AppModel, assistant: JarvisAssistant) {
        _controller = StateObject(wrappedValue: LiveWorkoutController(plan: plan, planned: planned, model: model, assistant: assistant))
        _voice = ObservedObject(wrappedValue: model.voice)
    }

    private var snapshot: SessionSnapshot { controller.snapshot }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: controller.camera.session).ignoresSafeArea()
            SkeletonOverlay(frame: controller.latestFrame, imageSize: controller.camera.imageSize,
                            mirrored: controller.camera.usingFrontCamera, highlight: repPulse)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let summary = controller.summary {
                    summaryCard(summary)
                } else {
                    centerHUD
                    Spacer()
                    bottomHUD
                }
            }
            .padding(.horizontal, 16)

            if controller.camera.authorizationDenied {
                permissionOverlay
            }
        }
        .statusBarHidden()
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.flashRep) { _, _ in
            withAnimation(.easeOut(duration: 0.12)) { repPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { repPulse = false } }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.exercise.map { model.t($0.name) } ?? model.t("Hazırlanıyor", "Getting ready"))
                    .font(Theme.title)
                    .foregroundStyle(.white)
                Text(model.t("Hareket \(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount) · Set \(snapshot.setNumber)/\(max(1, snapshot.totalSets))",
                             "Exercise \(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount) · Set \(snapshot.setNumber)/\(max(1, snapshot.totalSets))"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            JarvisOrb(state: voice.orbState, size: 52)
            Button {
                controller.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel(model.t("Antrenmanı kapat", "Close workout"))
        }
        .padding(.top, 12)
    }

    @ViewBuilder private var centerHUD: some View {
        switch snapshot.phase {
        case .countdown(let n):
            Text("\(n)")
                .font(Theme.display(140))
                .foregroundStyle(Theme.accent)
                .transition(.scale)
        case .resting:
            VStack(spacing: 8) {
                Text(model.t("DİNLENME", "REST")).font(Theme.headline).tracking(3).foregroundStyle(Theme.textSecondary)
                Text("\(snapshot.restRemaining ?? 0)")
                    .font(Theme.display(110))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if let next = snapshot.nextExercise {
                    Text(model.t("Sıradaki: \(next.name.tr)", "Next: \(next.name.en)"))
                        .font(Theme.headline).foregroundStyle(Theme.accent)
                }
            }
        case .active:
            VStack(spacing: 4) {
                if snapshot.exercise?.isTimed == true {
                    Text("\(Int(snapshot.holdSeconds))")
                        .font(Theme.display(130)).monospacedDigit()
                        .foregroundStyle(repPulse ? Theme.success : .white)
                    Text(model.t("/ \(snapshot.target) sn", "/ \(snapshot.target) s")).font(Theme.title).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("\(snapshot.reps)")
                        .font(Theme.display(150)).monospacedDigit()
                        .foregroundStyle(repPulse ? Theme.success : .white)
                        .scaleEffect(repPulse ? 1.08 : 1)
                    Text("/ \(snapshot.target)").font(Theme.title).foregroundStyle(Theme.textSecondary)
                }
            }
        case .paused:
            Label(model.t("Duraklatıldı — \"devam\" de", "Paused — say \"continue\""), systemImage: "pause.circle.fill")
                .font(Theme.title).foregroundStyle(Theme.warning)
        case .positioning:
            VStack(spacing: 10) {
                Image(systemName: "figure.stand").font(.system(size: 54)).foregroundStyle(Theme.accent)
                if let exercise = snapshot.exercise {
                    Text(model.t(exercise.setupInstruction))
                        .font(Theme.body).multilineTextAlignment(.center).foregroundStyle(.white)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.45)))
        default:
            EmptyView()
        }
    }

    private var bottomHUD: some View {
        VStack(spacing: 12) {
            if snapshot.phase == .active, snapshot.exercise?.isTimed == false {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * snapshot.progress)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
            if !controller.caption.isEmpty {
                Text(controller.caption)
                    .font(Theme.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.5)))
            }
            if !voice.lastHeard.isEmpty {
                Label(voice.lastHeard, systemImage: "waveform")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Button {
                    controller.command(snapshot.phase == .paused ? .resume : .pause)
                } label: {
                    Image(systemName: snapshot.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.white.opacity(0.15)))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(snapshot.phase == .paused ? model.t("Devam", "Resume") : model.t("Duraklat", "Pause"))
                if case .resting = snapshot.phase {
                    Button(model.t("Dinlenmeyi atla", "Skip rest")) { controller.command(.skipRest) }
                        .buttonStyle(SecondaryButtonStyle())
                } else if snapshot.phase == .active {
                    Button(model.t("Seti bitir", "Finish set")) { controller.command(.finishSet) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    controller.camera.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.white.opacity(0.15)))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(model.t("Kamerayı değiştir", "Switch camera"))
            }
            if !voice.isListening {
                Text(model.t("Mikrofon kapalı — sesli komutlar için izin ver.", "Microphone off — allow access for voice commands."))
                    .font(Theme.caption).foregroundStyle(Theme.warning)
            }
        }
        .padding(.bottom, 12)
    }

    private func summaryCard(_ summary: WorkoutSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary.safetyConcern != nil ? model.t("Antrenman güvenlik için durduruldu", "Workout stopped for safety")
                                                   : model.t("Antrenman tamamlandı", "Workout complete"))
                    .font(Theme.title)
                    .foregroundStyle(summary.safetyConcern != nil ? Theme.warning : .white)
                if let concern = summary.safetyConcern {
                    Text(model.t(concern.message)).font(Theme.body).foregroundStyle(.white)
                }
                HStack {
                    stat(model.t("Set", "Sets"), "\(summary.sets.count)")
                    stat(model.t("Tekrar", "Reps"), "\(summary.totalReps)")
                    stat(model.t("Dakika", "Minutes"), "\(summary.durationMinutes)")
                }
                ForEach(Array(summary.sets.enumerated()), id: \.offset) { _, set in
                    HStack {
                        Text("\(model.t(set.exercise.name)) · \(set.setNumber)").foregroundStyle(.white)
                        Spacer()
                        Text(set.exercise.isTimed ? "\(set.achieved) s" : "\(set.reps)/\(set.target)")
                            .foregroundStyle(set.achieved >= set.target ? Theme.success : Theme.textSecondary)
                    }
                    .font(Theme.body)
                }
                Button(model.t("Kapat", "Close")) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.bottom, 24)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(Theme.display(28)).foregroundStyle(Theme.accent)
            Text(title).font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text(model.t("Canlı antrenör için kamera izni gerekli. Görüntü yalnızca bu iPhone'da işlenir.",
                         "The live coach needs camera access. Video is processed only on this iPhone."))
                .multilineTextAlignment(.center).foregroundStyle(.white)
            Button(model.t("Ayarları aç", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
        .padding(24)
    }
}
