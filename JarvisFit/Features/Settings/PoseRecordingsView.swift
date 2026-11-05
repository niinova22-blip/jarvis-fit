import SwiftUI
import JarvisCore

/// Developer tool: records the raw pose stream of live workouts so rep counting can be checked
/// against the user's own count and tuned offline (`ReplayEvaluator`, JarvisCore fixtures).
struct PoseRecordingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var files: [URL] = []

    var body: some View {
        List {
            Section {
                Toggle(model.t("Canlı antrenmanlarda poz verisini kaydet", "Record pose data in live workouts"),
                       isOn: Binding(get: { model.data.settings.recordPoseData }, set: { v in model.updateSettings { $0.recordPoseData = v } }))
                Text(model.t("Yalnızca eklem koordinatları kaydedilir (görüntü ve ses kaydedilmez). Dosyalar bu cihazda kalır; paylaşmadığın sürece kimseye gönderilmez. Her setten sonra gerçek tekrar sayını girersen sayım doğruluğu ölçülebilir.",
                             "Only joint coordinates are stored (no video or audio). Files stay on this device unless you share them. Enter your real rep count for each set to measure counting accuracy."))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Section(model.t("Kayıtlar", "Recordings")) {
                if files.isEmpty {
                    Text(model.t("Henüz kayıt yok.", "No recordings yet.")).foregroundStyle(Theme.textSecondary)
                }
                ForEach(files, id: \.self) { url in
                    NavigationLink {
                        PoseRecordingDetailView(url: url)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.deletingPathExtension().lastPathComponent).font(Theme.caption).foregroundStyle(.white)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize(url)), countStyle: .file))
                                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .swipeActions {
                        Button(model.t("Sil", "Delete"), role: .destructive) {
                            try? FileManager.default.removeItem(at: url)
                            reload()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(model.t("Poz kayıtları", "Pose recordings"))
        .onAppear(perform: reload)
    }

    private func reload() {
        files = ((try? FileManager.default.contentsOfDirectory(at: DataStore.recordingsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

struct PoseRecordingDetailView: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    @State private var recording: PoseRecording?
    @State private var outcomes: [ReplayEvaluator.SetOutcome] = []
    @State private var loadError = false

    var body: some View {
        List {
            if let recording {
                Section {
                    LabeledContent(model.t("Cihaz", "Device"), value: recording.device)
                    LabeledContent(model.t("Kamera", "Camera"), value: recording.cameraPosition)
                    LabeledContent(model.t("Süre", "Duration"), value: "\(Int(recording.durationSeconds)) s · \(recording.frames.count) frames")
                    if let accuracy = ReplayEvaluator.accuracy(outcomes, tolerance: 0) {
                        LabeledContent(model.t("Doğruluk (etiketli setler)", "Accuracy (labelled sets)"), value: "\(Int(accuracy * 100))%")
                    }
                }
                Section(model.t("Setler — gerçek sayını gir", "Sets — enter your real count")) {
                    ForEach(recording.sets.indices, id: \.self) { index in
                        let set = recording.sets[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1). \(model.t(set.exercise.name)) · \(set.view.rawValue)").font(Theme.headline).foregroundStyle(.white)
                            Text(model.t("Uygulama: \(set.counted)", "App: \(set.counted)") +
                                 (outcomes.first { $0.index == set.index }.map { model.t(" · yeniden analiz: \($0.replayed)", " · replay: \($0.replayed)") } ?? ""))
                                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            Stepper(value: Binding(get: { self.recording?.sets[index].actual ?? set.counted },
                                                   set: { self.recording?.sets[index].actual = $0 }), in: 0...600) {
                                Text(model.t("Gerçek: \(self.recording?.sets[index].actual.map(String.init) ?? "—")",
                                             "Actual: \(self.recording?.sets[index].actual.map(String.init) ?? "—")"))
                            }
                        }
                    }
                }
                Section {
                    Button(model.t("Kaydet ve yeniden analiz et", "Save and re-analyse")) { save() }
                    ShareLink(item: url) { Label(model.t("Dosyayı paylaş", "Share file"), systemImage: "square.and.arrow.up") }
                }
            } else if loadError {
                Text(model.t("Kayıt okunamadı.", "Couldn't read the recording.")).foregroundStyle(Theme.warning)
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(model.t("Kayıt", "Recording"))
        .task { await load() }
    }

    private func load() async {
        let url = self.url
        let result = await Task.detached(priority: .userInitiated) { () -> (PoseRecording, [ReplayEvaluator.SetOutcome])? in
            guard let data = try? Data(contentsOf: url), let recording = try? PoseRecording.decode(data) else { return nil }
            return (recording, ReplayEvaluator.evaluate(recording))
        }.value
        if let result {
            recording = result.0
            outcomes = result.1
        } else {
            loadError = true
        }
    }

    private func save() {
        guard let recording, let data = try? recording.encoded() else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        outcomes = ReplayEvaluator.evaluate(recording)
    }
}
