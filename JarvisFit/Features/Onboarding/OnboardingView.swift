import SwiftUI
import JarvisCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var profile = UserProfile(language: AppLanguage.from(preferred: Locale.preferredLanguages))
    @State private var acceptedDisclaimer = false
    @State private var permissionsRequested = false
    @State private var voiceAnswers = false

    private let stepCount = 10
    private var lang: AppLanguage { profile.language }
    private func t(_ tr: String, _ en: String) -> String { lang == .turkish ? tr : en }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button { withAnimation { step -= 1 } } label: { Image(systemName: "chevron.left").font(.title3) }
                        .accessibilityLabel(t("Geri", "Back"))
                }
                ProgressView(value: Double(step), total: Double(stepCount - 1))
                    .tint(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        LiveOrb(voice: model.voice, size: 56)
                        Text(question)
                            .font(Theme.title)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                    voiceHint
                }
                .padding(20)
            }

            Button(step == stepCount - 1 ? t("Programımı oluştur", "Create my plan") : t("Devam", "Continue")) {
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.4)
            .padding(20)
        }
        .novaBackground()
        .onAppear {
            speakQuestion()
            if model.voice.hasPermissions { startVoiceAnswers() }
        }
        .onDisappear { endVoiceAnswers() }
        .onChange(of: step) { _, _ in speakQuestion() }
        .onChange(of: profile.language) { _, newValue in
            model.voice.configure(language: newValue, personality: profile.personality, voiceIdentifier: nil,
                                  gender: VoiceSelector.desiredGender(.matchUser, userSex: profile.sex))
            speakQuestion()
        }
    }

    private func speakQuestion() {
        model.voice.configure(language: profile.language, personality: profile.personality, voiceIdentifier: nil,
                              gender: VoiceSelector.desiredGender(.matchUser, userSex: profile.sex))
        model.voice.stopSpeaking()
        model.voice.say(question, priority: .high)
    }

    private var question: String {
        switch step {
        case 0: return t("Merhaba, ben NOVA. Kişisel spor mentorunum. Hangi dilde konuşalım?", "Hello, I'm NOVA, your personal fitness mentor. Which language should we speak?")
        case 1: return t("Sana nasıl hitap edeyim ve nasıl bir antrenör istersin?", "What should I call you, and what kind of coach do you want?")
        case 2: return t("Hangi vücuda ulaşmak istiyorsun?", "Which body are you working towards?")
        case 3: return t("Biraz seni tanıyayım. Yaşın, boyun ve kilon?", "Let me get to know you. Your age, height and weight?")
        case 4: return t("Ne kadar süredir antrenman yapıyorsun?", "How long have you been training?")
        case 5: return t("Hangi ekipmanlara erişimin var? Hiçbiri yoksa vücut ağırlığıyla çalışırız.", "What equipment do you have? If none, we'll use bodyweight.")
        case 6: return t("Hangi günler ve saatte antrenman yapabilirsin?", "Which days and what time can you train?")
        case 7: return t("Bilmem gereken bir sağlık durumu var mı?", "Is there any health condition I should know about?")
        case 8: return t("Beslenme tercihin nedir?", "What's your eating style?")
        default: return t("Son olarak, seni görebilmem ve duyabilmem için izinler gerekiyor.", "Finally, I need permission to see and hear you.")
        }
    }

    private var canContinue: Bool {
        switch step {
        case 3: return profile.validationErrors().filter { !$0.en.contains("training day") }.isEmpty
        case 6: return !profile.availableDays.isEmpty
        case 7: return acceptedDisclaimer
        default: return true
        }
    }

    private func next() {
        if step < stepCount - 1 {
            withAnimation { step += 1 }
        } else {
            model.voice.stopSpeaking()
            endVoiceAnswers()
            model.completeOnboarding(profile)
            Task { _ = await NotificationScheduler.requestAuthorization(); NotificationScheduler.reschedule(model: model) }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 12) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    selectionRow(language == .turkish ? "Türkçe" : "English", selected: profile.language == language) { profile.language = language }
                }
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                TextField(t("Adın (isteğe bağlı)", "Your name (optional)"), text: $profile.name)
                    .textContentType(.givenName)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                ForEach(CoachPersonality.allCases, id: \.self) { p in
                    selectionRow(p.title.resolve(lang), subtitle: p.summary.resolve(lang), selected: profile.personality == p) { profile.personality = p }
                }
            }
        case 2:
            VStack(spacing: 12) {
                ForEach(FitnessGoal.allCases, id: \.self) { goal in
                    selectionRow(goal.title.resolve(lang), subtitle: goal.summary.resolve(lang), selected: profile.goal == goal) { profile.goal = goal }
                }
            }
        case 3:
            VStack(alignment: .leading, spacing: 16) {
                Stepper(value: $profile.age, in: 16...90) { labeled(t("Yaş", "Age"), "\(profile.age)") }
                Stepper(value: $profile.heightCm, in: 120...230, step: 1) { labeled(t("Boy", "Height"), "\(Int(profile.heightCm)) cm") }
                Stepper(value: $profile.weightKg, in: 35...250, step: 0.5) { labeled(t("Kilo", "Weight"), String(format: "%.1f kg", profile.weightKg)) }
                SectionTitle(text: t("Kalori hesabı için", "For calorie estimates"))
                FlowLayout {
                    ForEach(BiologicalSex.allCases, id: \.self) { sex in
                        ChipButton(title: sex.title.resolve(lang), selected: profile.sex == sex) { profile.sex = sex }
                    }
                }
                ForEach(profile.validationErrors().filter { !$0.en.contains("training day") }, id: \.self) { error in
                    Text(error.resolve(lang)).font(Theme.caption).foregroundStyle(Theme.warning)
                }
            }
            .foregroundStyle(.white)
        case 4:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    selectionRow(level.title.resolve(lang), selected: profile.experience == level) { profile.experience = level }
                }
                SectionTitle(text: t("Gün içindeki hareketin", "Daily activity"))
                FlowLayout {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        ChipButton(title: level.title.resolve(lang), selected: profile.activity == level) { profile.activity = level }
                    }
                }
            }
        case 5:
            FlowLayout {
                ForEach(Equipment.allCases, id: \.self) { item in
                    ChipButton(title: item.title.resolve(lang), selected: profile.equipment.contains(item)) {
                        if profile.equipment.contains(item) { _ = profile.equipment.remove(item) } else { _ = profile.equipment.insert(item) }
                    }
                }
            }
        case 6:
            VStack(alignment: .leading, spacing: 16) {
                FlowLayout {
                    ForEach(1...7, id: \.self) { day in
                        ChipButton(title: weekdayName(day), selected: profile.availableDays.contains(day)) {
                            if profile.availableDays.contains(day) { _ = profile.availableDays.remove(day) } else { _ = profile.availableDays.insert(day) }
                        }
                    }
                }
                DatePicker(t("Antrenman saati", "Training time"), selection: timeBinding, displayedComponents: .hourAndMinute)
                    .foregroundStyle(.white)
                SectionTitle(text: t("Antrenman süresi", "Session length"))
                FlowLayout {
                    ForEach([20, 30, 45, 60, 75], id: \.self) { minutes in
                        ChipButton(title: t("\(minutes) dk", "\(minutes) min"), selected: profile.sessionMinutes == minutes) { profile.sessionMinutes = minutes }
                    }
                }
            }
        case 7:
            VStack(alignment: .leading, spacing: 14) {
                FlowLayout {
                    ForEach(HealthLimitation.allCases, id: \.self) { item in
                        ChipButton(title: item.title.resolve(lang), selected: profile.limitations.contains(item)) {
                            if profile.limitations.contains(item) { _ = profile.limitations.remove(item) } else { _ = profile.limitations.insert(item) }
                        }
                    }
                }
                if profile.limitations.contains(where: { $0.requiresClearance }) {
                    Text(t("Bu durumda antrenmana başlamadan önce doktorunun onayını almanı öneririm.", "With this condition, please get your doctor's clearance before training."))
                        .font(Theme.body).foregroundStyle(Theme.warning)
                }
                Toggle(isOn: $acceptedDisclaimer) {
                    Text(t("NOVA Coach tıbbi tavsiye vermez ve teşhis koymaz. Ağrı, baş dönmesi veya göğüs ağrısı hissedersen antrenmanı bırakıp bir sağlık profesyoneline başvuracağımı anlıyorum.",
                           "NOVA Coach does not give medical advice or diagnoses. I understand I should stop and contact a health professional if I feel pain, dizziness or chest pain."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.accent)
            }
        case 8:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(DietPreference.allCases, id: \.self) { diet in
                    selectionRow(diet.title.resolve(lang), selected: profile.diet == diet) { profile.diet = diet }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 14) {
                permissionRow("camera.fill", t("Kamera", "Camera"), t("Hareketlerini takip etmek ve yemek fotoğrafı için. Görüntü cihazdan çıkmaz.", "To follow your movement and analyse meal photos. Video never leaves the device."))
                permissionRow("mic.fill", t("Mikrofon ve konuşma tanıma", "Microphone & speech recognition"), t("Ekrana dokunmadan konuşabilmen için. Ses cihazda işlenir.", "So you can talk hands-free. Audio is processed on device."))
                permissionRow("bell.fill", t("Bildirimler", "Notifications"), t("Antrenman hatırlatmaları ve günlük brifing için.", "For workout reminders and the daily briefing."))
                Button(permissionsRequested ? t("İzinler istendi", "Permissions requested") : t("İzinleri ver", "Grant permissions")) {
                    Task {
                        _ = await CameraPoseService.requestAccess()
                        _ = await model.voice.requestPermissions()
                        _ = await NotificationScheduler.requestAuthorization()
                        permissionsRequested = true
                        if model.voice.hasPermissions && !voiceAnswers { startVoiceAnswers() }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                if !model.voice.onDeviceRecognitionAvailable {
                    Text(t("Not: Bu cihazda seçtiğin dil için çevrimdışı konuşma tanıma bulunamadı. Sesli komutlar için iOS Ayarlar > Genel > Klavye > Dikte bölümünden dil paketini indirebilirsin.",
                           "Note: offline speech recognition for this language isn't available on this device. You can download the language in iOS Settings > General > Keyboard > Dictation."))
                        .font(Theme.caption).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    // MARK: Voice answers

    private var topic: OnboardingTopic { OnboardingTopic(rawValue: step) ?? .permissions }

    @ViewBuilder private var voiceHint: some View {
        if voiceAnswers {
            Label(t("Cevabını söyleyebilirsin. Örn: \(example)", "You can answer by voice, e.g. \(example)"), systemImage: "mic.fill")
                .font(Theme.caption).foregroundStyle(Theme.accent)
            if !model.voice.lastHeard.isEmpty {
                Text("“\(model.voice.lastHeard)”").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        } else if topic != .permissions {
            Button {
                Task {
                    if await model.voice.requestPermissions() { startVoiceAnswers() }
                }
            } label: {
                Label(t("Sesle cevaplamak için mikrofonu aç", "Turn on the microphone to answer by voice"), systemImage: "mic")
                    .font(Theme.caption)
            }
        }
    }

    private var example: String {
        switch topic {
        case .language: return t("\"Türkçe\"", "\"English\"")
        case .nameAndCoach: return t("\"Adım Mert, sakin bir hoca istiyorum\"", "\"Call me Alex, be energetic\"")
        case .goal: return t("\"Kaslı bir vücut\"", "\"A strong body\"")
        case .body: return t("\"30 yaşındayım, boyum 180, 82 kilo\"", "\"I'm 30, 180 cm, 82 kilos\"")
        case .experience: return t("\"İki yıldır çalışıyorum\"", "\"About a year\"")
        case .equipment: return t("\"Dambıl ve barfiks barım var\"", "\"Dumbbells and a pull-up bar\"")
        case .schedule: return t("\"Pazartesi, çarşamba, cuma akşam yedide\"", "\"Monday, Wednesday, Friday at 7 pm\"")
        case .health: return t("\"Dizimde sorun var\" veya \"yok, kabul ediyorum\"", "\"Knee issues\" or \"none, I agree\"")
        case .diet: return t("\"Her şeyi yerim\"", "\"Vegetarian\"")
        case .permissions: return t("\"devam\"", "\"continue\"")
        }
    }

    private func startVoiceAnswers() {
        let voice = model.voice
        // NOVA's own question is never taken as an answer (no barge-in during onboarding).
        voice.isBargeIn = { _ in false }
        voice.onUtterance = { text, isFinal in
            guard isFinal else { return false }
            handleVoiceAnswer(text)
            return true
        }
        voice.startListening()
        voiceAnswers = voice.isListening
    }

    private func endVoiceAnswers() {
        model.voice.onUtterance = nil
        model.voice.isBargeIn = nil
        model.voice.stopListening()
        voiceAnswers = false
    }

    private func handleVoiceAnswer(_ text: String) {
        let result = OnboardingVoiceParser.apply(text, topic: topic, to: profile)
        let normalized = TextNormalizer.normalize(text)
        if topic == .health, ["kabul", "anladim", "onayliyorum", "understand", "agree", "accept"].contains(where: { normalized.contains($0) }) {
            acceptedDisclaimer = true
        }
        if result.understood { profile = result.profile }
        if result.goBack, step > 0 {
            withAnimation { step -= 1 }
            return
        }
        let singleChoice: Set<OnboardingTopic> = [.language, .goal, .experience, .diet]
        if (result.advance || (result.understood && singleChoice.contains(topic))) && canContinue {
            next()
        } else if result.understood || acceptedDisclaimer {
            model.voice.say(t("Tamam, not aldım. Hazırsan \"devam\" de.", "Got it. Say \"continue\" when you're ready."), priority: .high)
        } else if !canContinue && result.advance {
            model.voice.say(t("Devam etmeden önce bu adımı tamamlamamız gerekiyor.", "We need to finish this step before continuing."), priority: .high)
        } else {
            model.voice.say(t("Tam anlayamadım. Tekrar söyleyebilir ya da ekrandan seçebilirsin.", "I didn't quite get that. Say it again or pick on screen."), priority: .high)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: profile.preferredTrainingMinute / 60, minute: profile.preferredTrainingMinute % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            profile.preferredTrainingMinute = (c.hour ?? 19) * 60 + (c.minute ?? 0)
        }
    }

    private func weekdayName(_ day: Int) -> String {
        let tr = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return lang == .turkish ? tr[day - 1] : en[day - 1]
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.headline).foregroundStyle(.white)
        }
    }

    private func selectionRow(_ title: String, subtitle: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.headline).foregroundStyle(.white)
                    if let subtitle { Text(subtitle).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                    .font(.title3)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? Theme.accentSoft : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func permissionRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.headline).foregroundStyle(.white)
                Text(text).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
