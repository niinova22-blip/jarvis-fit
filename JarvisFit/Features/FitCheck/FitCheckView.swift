import SwiftUI
import JarvisCore

/// Guided body scan: a front photo (arms slightly away from the body) and a side photo, both
/// head-to-toe. Measurements are estimates with ranges; optional tape measurements calibrate them.
struct FitCheckView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var frontImage: UIImage?
    @State private var sideImage: UIImage?
    @State private var showCamera = false
    @State private var analyzing = false
    @State private var error: String?
    @State private var result: FitCheckRecord?
    @State private var rawEstimates: [MeasurementEstimate] = []
    @State private var tape: [MeasurementSite: String] = [:]
    @State private var weight: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result {
                        resultView(result)
                    } else {
                        instructions
                        photoSlot(title: model.t("1. Önden", "1. Front"), image: frontImage) { step = 0; showCamera = true }
                        photoSlot(title: model.t("2. Yandan", "2. Side"), image: sideImage) { step = 1; showCamera = true }
                        Stepper(value: $weight, in: 35...250, step: 0.1) {
                            Text(model.t("Bugünkü kilo: \(String(format: "%.1f", weight)) kg", "Today's weight: \(String(format: "%.1f", weight)) kg"))
                                .foregroundStyle(.white)
                        }
                        if let error { Text(error).foregroundStyle(Theme.warning).font(Theme.body) }
                        Button {
                            Task { await analyze() }
                        } label: {
                            if analyzing { ProgressView().tint(.black) } else { Text(model.t("Analiz et", "Analyse")) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(frontImage == nil || analyzing)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Fit Check")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    showCamera = false
                    guard let image else { return }
                    if step == 0 { frontImage = image } else { sideImage = image }
                }
                .ignoresSafeArea()
            }
            .onAppear { if weight == 0 { weight = model.data.weights.last?.kg ?? model.profile?.weightKg ?? 75 } }
        }
    }

    private var instructions: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.t("Nasıl çekilir", "How to shoot"), systemImage: "camera.metering.center.weighted").font(Theme.headline).foregroundStyle(.white)
                Text(model.t("• Dar kıyafet giy, iyi ışıkta dur.\n• Telefonu bel hizasına koy, 2–3 m uzaklaş; baştan ayağa görün.\n• Önden: kollarını gövdenden hafifçe uzaklaştır.\n• Yandan: kollar yanda, dik dur.\n• Zamanlayıcıyı kullan veya birinden yardım iste.",
                             "• Wear fitted clothes in good light.\n• Phone at waist height, 2–3 m away; head to toe in frame.\n• Front: arms slightly away from the body.\n• Side: arms down, stand tall.\n• Use the timer or ask someone to help."))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Text(model.t("Ölçümler fotoğraftan yapılan tahminlerdir (kalibrasyonsuz ±%7–12). Bir kez mezura ile ölçüm girersen sonraki tahminler kalibre edilir.",
                             "Measurements are photo estimates (±7–12% uncalibrated). Enter a tape measurement once to calibrate future scans."))
                    .font(Theme.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    private func photoSlot(title: String, image: UIImage?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 70, height: 100).clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceRaised).frame(width: 70, height: 100)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.textSecondary))
                }
                Text(title).font(Theme.headline).foregroundStyle(.white)
                Spacer()
                Image(systemName: image == nil ? "camera" : "arrow.clockwise").foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }

    private func analyze() async {
        guard let frontImage, let profile = model.profile else { return }
        analyzing = true
        error = nil
        defer { analyzing = false }
        do {
            let front = try await BodyScanAnalyzer.analyze(frontImage, front: true)
            var side: BodyScanAnalyzer.Output?
            if let sideImage { side = try? await BodyScanAnalyzer.analyze(sideImage, front: false) }
            let estimator = BodyMeasurementEstimator()
            let raw = estimator.estimate(front: front.mask, frontLandmarks: front.landmarks, side: side?.mask, sideLandmarks: side?.landmarks, heightCm: profile.heightCm)
            let calibrated = estimator.estimate(front: front.mask, frontLandmarks: front.landmarks, side: side?.mask, sideLandmarks: side?.landmarks,
                                                heightCm: profile.heightCm, calibrationFactors: model.calibrationFactors)
            guard !calibrated.isEmpty else {
                error = model.t("Vücudunu tam göremedim. Baştan ayağa göründüğünden emin olup tekrar dene.", "I couldn't see your whole body. Make sure you're visible head to toe and try again.")
                return
            }
            rawEstimates = raw
            var record = FitCheckRecord(date: Date(), estimates: calibrated, posture: PostureReport.analyze(front: front.pose, side: side?.pose), weightKg: weight)
            if model.data.settings.savePhotos {
                record.frontPhotoFile = save(frontImage, name: "\(record.id)-front.jpg")
                if let sideImage { record.sidePhotoFile = save(sideImage, name: "\(record.id)-side.jpg") }
            }
            result = record
        } catch {
            self.error = model.t("Analiz başarısız oldu: fotoğrafta tek bir kişi tam boy görünmeli.", "Analysis failed: one person must be fully visible in the photo.")
        }
    }

    private func save(_ image: UIImage, name: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url = DataStore.photosDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return name
        } catch { return nil }
    }

    private func resultView(_ record: FitCheckRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: model.t("Tahmini çevre ölçüleri", "Estimated circumferences"))
            ForEach(record.estimates, id: \.site) { estimate in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.t(estimate.site.title)).font(Theme.headline).foregroundStyle(.white)
                            Spacer()
                            Text(estimate.display()).font(Theme.headline).foregroundStyle(Theme.accent)
                        }
                        Text(estimate.calibrated ? model.t("Kalibre edilmiş tahmin", "Calibrated estimate") : model.t("Kalibre edilmemiş tahmin", "Uncalibrated estimate"))
                            .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        TextField(model.t("Mezura ile ölçtüysen (cm)", "Tape measurement if you have one (cm)"), text: Binding(
                            get: { tape[estimate.site] ?? "" }, set: { tape[estimate.site] = $0 }))
                            .keyboardType(.decimalPad)
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceRaised))
                    }
                }
            }
            let notes = record.posture.observations()
            if !notes.isEmpty {
                SectionTitle(text: model.t("Duruş gözlemleri", "Posture observations"))
                ForEach(notes, id: \.self) { note in
                    Text("• " + model.t(note)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Button(model.t("Kaydet", "Save")) {
                var final = record
                var factors: [MeasurementSite: Double] = [:]
                for (site, text) in tape {
                    guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                          let raw = rawEstimates.first(where: { $0.site == site })?.valueCm,
                          let factor = BodyMeasurementEstimator.calibrationFactor(tapeCm: value, rawEstimateCm: raw) else { continue }
                    factors[site] = factor
                    final.tapeMeasurements[site.rawValue] = value
                    if let i = final.estimates.firstIndex(where: { $0.site == site }) {
                        let u = site.relativeUncertainty(calibrated: true)
                        final.estimates[i] = MeasurementEstimate(site: site, valueCm: value, lowCm: value * (1 - u), highCm: value * (1 + u), calibrated: true)
                    }
                }
                model.addFitCheck(final, calibration: factors)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
