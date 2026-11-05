import SwiftUI
import AVFoundation
import JarvisCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = UserProfile()
    @State private var confirmDelete = false
    @State private var showPaywall = false
    @State private var showMemory = false

    var body: some View {
        NavigationStack {
            Form {
                Section(model.t("Abonelik", "Subscription")) {
                    if model.isPremium {
                        Label(model.t("Premium aktif", "Premium active"), systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
                        Link(model.t("Aboneliği yönet", "Manage subscription"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    } else {
                        Button(model.t("Premium'a geç", "Go Premium")) { showPaywall = true }
                    }
                }
                Section("JARVIS") {
                    Picker(model.t("Dil", "Language"), selection: $profile.language) {
                        Text("Türkçe").tag(AppLanguage.turkish)
                        Text("English").tag(AppLanguage.english)
                    }
                    Picker(model.t("Kişilik", "Personality"), selection: $profile.personality) {
                        ForEach(CoachPersonality.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                    }
                    Picker(model.t("Ses", "Voice"), selection: Binding(get: { model.data.settings.voiceIdentifier ?? "" },
                                                                     set: { id in model.updateSettings { $0.voiceIdentifier = id.isEmpty ? nil : id } })) {
                        Text(model.t("Otomatik (en kaliteli)", "Automatic (best quality)")).tag("")
                        ForEach(VoiceCoordinator.availableVoices(for: profile.language), id: \.identifier) { voice in
                            Text("\(voice.name) \(voice.quality == .premium ? "★★" : voice.quality == .enhanced ? "★" : "")").tag(voice.identifier)
                        }
                    }
                    Button(model.t("Sesi dene", "Test voice")) {
                        model.voice.say(model.t("Merhaba, ben JARVIS. Hazır olduğunda başlayalım.", "Hi, I'm JARVIS. Let's start when you're ready."), priority: .high)
                    }
                    Toggle(model.t("Antrenman dışında 'Jarvis' kelimesini bekle", "Require 'Jarvis' wake word outside workouts"),
                           isOn: Binding(get: { model.data.settings.requireWakeWord }, set: { v in model.updateSettings { $0.requireWakeWord = v } }))
                    if !model.voice.onDeviceRecognitionAvailable {
                        Text(model.t("Bu dil için çevrimdışı konuşma tanıma cihazda yok. Ayarlar > Genel > Klavye > Dikte'den indirebilirsin.",
                                     "Offline speech recognition for this language isn't on this device. Download it in Settings > General > Keyboard > Dictation."))
                            .font(Theme.caption).foregroundStyle(Theme.warning)
                    }
                }
                Section(model.t("Profil ve program", "Profile & plan")) {
                    Picker(model.t("Hedef", "Goal"), selection: $profile.goal) {
                        ForEach(FitnessGoal.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                    }
                    Picker(model.t("Seviye", "Level"), selection: $profile.experience) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                    }
                    Stepper(value: $profile.weightKg, in: 35...250, step: 0.5) { Text(String(format: model.t("Kilo: %.1f kg", "Weight: %.1f kg"), profile.weightKg)) }
                    Stepper(value: $profile.sessionMinutes, in: 20...90, step: 5) { Text(model.t("Süre: \(profile.sessionMinutes) dk", "Length: \(profile.sessionMinutes) min")) }
                    NavigationLink(model.t("Ekipman ve sağlık", "Equipment & health")) { EquipmentHealthEditor(profile: $profile) }
                    Button(model.t("Kaydet ve programı yeniden oluştur", "Save and rebuild plan")) {
                        model.updateProfile(profile, regeneratePlan: true)
                        dismiss()
                    }
                    Button(model.t("Yalnızca kaydet", "Save only")) {
                        model.updateProfile(profile, regeneratePlan: false)
                        dismiss()
                    }
                }
                Section(model.t("Kamera ve bildirimler", "Camera & notifications")) {
                    Toggle(model.t("Ön kamerayı kullan", "Use front camera"),
                           isOn: Binding(get: { model.data.settings.useFrontCamera }, set: { v in model.updateSettings { $0.useFrontCamera = v } }))
                    Picker(model.t("Performans", "Performance"), selection: Binding(get: { model.data.settings.performance },
                                                                                  set: { v in model.updateSettings { $0.performance = v } })) {
                        ForEach(PerformancePreference.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                    }
                    Toggle(model.t("Antrenman hatırlatmaları", "Workout reminders"),
                           isOn: Binding(get: { model.data.settings.workoutReminders }, set: { v in model.updateSettings { $0.workoutReminders = v } }))
                    Toggle(model.t("Günlük brifingi sesli oku", "Speak daily briefing"),
                           isOn: Binding(get: { model.data.settings.speakDailyBriefing }, set: { v in model.updateSettings { $0.speakDailyBriefing = v } }))
                    Toggle(model.t("Haftalık rapor", "Weekly report"),
                           isOn: Binding(get: { model.data.settings.weeklyReport }, set: { v in model.updateSettings { $0.weeklyReport = v } }))
                }
                Section(model.t("Gizlilik", "Privacy")) {
                    Button(model.t("JARVIS'in hafızası", "JARVIS memory")) { showMemory = true }
                    NavigationLink(model.t("Gizlilik politikası", "Privacy policy")) { PrivacyPolicyView() }
                    Toggle(model.t("Fit Check fotoğraflarını sakla", "Keep Fit Check photos"),
                           isOn: Binding(get: { model.data.settings.savePhotos }, set: { v in model.updateSettings { $0.savePhotos = v } }))
                    Text(model.t("Kamera görüntüsü, ses ve tüm verilerin yalnızca bu iPhone'da işlenir ve saklanır. Sunucumuz yoktur; satın alma doğrulaması için yalnızca Apple'ın App Store hizmetleri kullanılır.",
                                 "Camera video, audio and all your data are processed and stored only on this iPhone. There is no server; only Apple's App Store services are used to verify purchases."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Button(model.t("Tüm verilerimi sil", "Delete all my data"), role: .destructive) { confirmDelete = true }
                }
                Section(model.t("Sağlık uyarısı", "Health notice")) {
                    Text(model.t("JARVIS FIT bir tıbbi cihaz değildir, teşhis koymaz ve tedavi önermez. Kalori, ölçüm ve form değerlendirmeleri tahminidir. Yeni bir egzersiz programına başlamadan önce, özellikle bir sağlık sorunun varsa, doktoruna danış.",
                                 "JARVIS FIT is not a medical device and does not diagnose or treat. Calorie, measurement and form feedback are estimates. Consult your doctor before starting a new exercise program, especially if you have a health condition."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Section(model.t("Geliştirici", "Developer")) {
                    NavigationLink(model.t("Poz kayıtları (tekrar sayımı doğrulama)", "Pose recordings (rep counting validation)")) { PoseRecordingsView() }
                }
                Section {
                    Text("JARVIS FIT \(LiveWorkoutController.appVersion) · \(model.t("Model", "Model")): \(model.t("Apple Vision (poz), Apple Speech, Apple Foundation Models", "Apple Vision (pose), Apple Speech, Apple Foundation Models"))")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.t("Ayarlar", "Settings"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { dismiss() } } }
            .onAppear { if let p = model.profile { profile = p } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showMemory) { MemoryView() }
            .confirmationDialog(model.t("Tüm veriler kalıcı olarak silinsin mi?", "Permanently delete all data?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(model.t("Sil", "Delete"), role: .destructive) {
                    model.deleteAllData()
                    dismiss()
                }
            }
        }
    }
}

struct EquipmentHealthEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: UserProfile

    var body: some View {
        Form {
            Section(model.t("Ekipman", "Equipment")) {
                ForEach(Equipment.allCases, id: \.self) { item in
                    Toggle(model.t(item.title), isOn: Binding(get: { profile.equipment.contains(item) },
                                                              set: { on in if on { _ = profile.equipment.insert(item) } else { _ = profile.equipment.remove(item) } }))
                }
            }
            Section(model.t("Sağlık kısıtları", "Health limitations")) {
                ForEach(HealthLimitation.allCases, id: \.self) { item in
                    Toggle(model.t(item.title), isOn: Binding(get: { profile.limitations.contains(item) },
                                                              set: { on in if on { _ = profile.limitations.insert(item) } else { _ = profile.limitations.remove(item) } }))
                }
            }
            Section(model.t("Antrenman günleri", "Training days")) {
                ForEach(1...7, id: \.self) { day in
                    Toggle(dayName(day), isOn: Binding(get: { profile.availableDays.contains(day) },
                                                       set: { on in if on { _ = profile.availableDays.insert(day) } else { _ = profile.availableDays.remove(day) } }))
                }
            }
            Section(model.t("Beslenme", "Diet")) {
                Picker(model.t("Tercih", "Preference"), selection: $profile.diet) {
                    ForEach(DietPreference.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func dayName(_ day: Int) -> String {
        let tr = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
        let en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return (model.language == .turkish ? tr : en)[day - 1]
    }
}

struct MemoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.isPremium {
                    Section {
                        Text(model.t("Kişisel hafıza Premium özelliğidir. Ücretsiz sürümde yeni bilgi hatırlanmaz.",
                                     "Personal memory is a Premium feature. The free version doesn't remember new facts."))
                            .font(Theme.caption).foregroundStyle(Theme.warning)
                    }
                }
                Section {
                    Toggle(model.t("Kişisel hafıza açık", "Personal memory on"),
                           isOn: Binding(get: { model.data.memoryEnabled }, set: { model.setMemoryEnabled($0) }))
                    Text(model.t("JARVIS yalnızca kısa bilgileri hatırlar (sevdiğin hareketler, zorlandıkların, başarıların). Konuşmaların kaydedilmez. Hepsi bu cihazda kalır.",
                                 "JARVIS only remembers short facts (favourite moves, struggles, achievements). Conversations are not recorded. Everything stays on this device."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Section {
                    if model.data.memories.isEmpty {
                        Text(model.t("Henüz hatırlanan bir şey yok.", "Nothing remembered yet.")).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(model.data.memories.reversed()) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.t(item.kind.title)).font(Theme.caption).foregroundStyle(Theme.accent)
                            Text(item.text).foregroundStyle(.white)
                        }
                        .swipeActions { Button(model.t("Sil", "Delete"), role: .destructive) { model.deleteMemory(item.id) } }
                    }
                }
                if !model.data.memories.isEmpty {
                    Button(model.t("Hafızayı tamamen sil", "Erase all memory"), role: .destructive) { model.clearMemories() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(model.t("Hafıza", "Memory"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { dismiss() } } }
        }
    }
}
