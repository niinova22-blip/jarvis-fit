import SwiftUI
import PhotosUI
import JarvisCore

struct NutritionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var analysis: PhotoAnalysisState?
    @State private var showSearch = false
    @State private var showVoice = false
    @State private var showPaywall = false
    @State private var voiceResult: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    actions
                    if let voiceResult {
                        Card { Text(voiceResult).font(Theme.body).foregroundStyle(.white) }
                    }
                    ForEach(MealType.allCases, id: \.self) { meal in
                        mealSection(meal)
                    }
                    Text(model.t("Kalori ve makrolar yerel besin tablosuna dayanan tahminlerdir. Tarifler ve porsiyonlar farklılık gösterebilir.",
                                 "Calories and macros are estimates from a local food table. Recipes and portions vary."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.t("Beslenme", "Nutrition"))
            .sheet(item: $analysis) { state in PhotoConfirmSheet(state: state) }
            .sheet(isPresented: $showSearch) { FoodSearchSheet() }
            .sheet(isPresented: $showVoice) { VoiceMealSheet(result: $voiceResult) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    showCamera = false
                    if let image { analyze(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { analyze(image) }
                    photoItem = nil
                }
            }
        }
    }

    private func analyze(_ image: UIImage) {
        guard model.canScanFood() else { showPaywall = true; return }
        model.recordFoodScan()
        Task {
            let result = await FoodPhotoAnalyzer.analyze(image)
            analysis = PhotoAnalysisState(image: image, candidates: result.candidates.map { PhotoCandidate(food: $0.item, confidence: $0.confidence) })
        }
    }

    private var summaryCard: some View {
        Card {
            if let day = model.nutritionToday {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(day.totals.kcal))").font(Theme.display(40)).foregroundStyle(.white)
                        Text("/ \(day.targets.kcal) kcal").font(Theme.headline).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(day.remainingKcal >= 0 ? model.t("\(day.remainingKcal) kaldı", "\(day.remainingKcal) left")
                                                    : model.t("\(-day.remainingKcal) fazla", "\(-day.remainingKcal) over"))
                            .font(Theme.caption).foregroundStyle(day.remainingKcal >= 0 ? Theme.success : Theme.warning)
                    }
                    HStack {
                        macro("P", day.totals.protein, day.targets.proteinG)
                        macro("K", day.totals.carbs, day.targets.carbsG, en: "C")
                        macro("Y", day.totals.fat, day.targets.fatG, en: "F")
                    }
                    Text(model.t(day.targets.rationale)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func macro(_ tr: String, _ value: Double, _ target: Int, en: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value))/\(target) g").font(Theme.headline).foregroundStyle(.white)
            Text(model.language == .turkish ? tr == "P" ? "Protein" : tr == "K" ? "Karbonhidrat" : "Yağ"
                                            : tr == "P" ? "Protein" : en == "C" ? "Carbs" : "Fat")
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { if model.canScanFood() { showCamera = true } else { showPaywall = true } } label: {
                    Label(model.t("Fotoğraf çek", "Take photo"), systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(model.t("Galeriden", "From library"), systemImage: "photo")
                        .font(Theme.headline).foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accentSoft))
                }
            }
            HStack(spacing: 10) {
                Button { showVoice = true } label: { Label(model.t("Sesle ekle", "Add by voice"), systemImage: "mic.fill") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { showSearch = true } label: { Label(model.t("Ara", "Search"), systemImage: "magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if !model.isPremium {
                Text(model.t("Ücretsiz: bugün \(model.foodScansLeftToday) fotoğraf analizi hakkın kaldı.", "Free: \(model.foodScansLeftToday) photo analyses left today."))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder private func mealSection(_ meal: MealType) -> some View {
        let entries = model.entries(on: Date()).filter { $0.meal == meal }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: model.t(meal.title))
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.t(entry.name)).font(Theme.headline).foregroundStyle(.white)
                            Text("\(formatQuantity(entry.quantity)) \(model.t(entry.unit.title)) · \(Int(entry.grams)) g\(entry.isEstimate ? " · " + model.t("tahmini", "estimate") : "")")
                                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(entry.macros.kcal)) kcal").font(Theme.headline).foregroundStyle(.white)
                            Text("P \(Int(entry.macros.protein)) g").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Button { model.deleteFoodEntry(entry.id) } label: { Image(systemName: "trash").foregroundStyle(Theme.danger) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.t("Sil", "Delete"))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                }
            }
        }
    }
}

func formatQuantity(_ q: Double) -> String {
    q == q.rounded() ? String(Int(q)) : String(format: "%.1f", q)
}

struct PhotoCandidate: Identifiable {
    var id: String { food.id }
    var food: FoodItem
    var confidence: Double
}

struct PhotoAnalysisState: Identifiable {
    let id = UUID()
    var image: UIImage
    var candidates: [PhotoCandidate]
}

/// The user confirms detected foods and portion sizes — the photo alone cannot measure them.
struct PhotoConfirmSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let state: PhotoAnalysisState
    @State private var selected: [String: Double] = [:]  // food id → portion multiplier
    @State private var extra: [FoodItem] = []
    @State private var meal = MealType.forHour(Calendar.current.component(.hour, from: Date()))
    @State private var showSearch = false

    private let sizes: [(LocalizedText, Double)] = [
        (LocalizedText(tr: "Az", en: "Small"), 0.6), (LocalizedText(tr: "Normal", en: "Normal"), 1.0),
        (LocalizedText(tr: "Büyük", en: "Large"), 1.5), (LocalizedText(tr: "Çift", en: "Double"), 2.0)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: state.image).resizable().scaledToFill().frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 18))
                    if state.candidates.isEmpty {
                        Text(model.t("Fotoğrafta tanıdığım bir yemek bulamadım. Aşağıdan arayarak ekleyebilirsin.",
                                     "I couldn't recognise a food in this photo. Add it with search below."))
                            .font(Theme.body).foregroundStyle(Theme.warning)
                    } else {
                        Text(model.t("Gördüklerim (doğru olanları seç ve porsiyonu belirt):", "What I see (select the right ones and set the portion):"))
                            .font(Theme.headline).foregroundStyle(.white)
                    }
                    ForEach(state.candidates.map(\.food) + extra, id: \.id) { food in
                        foodRow(food, confidence: state.candidates.first { $0.food.id == food.id }?.confidence)
                    }
                    Button { showSearch = true } label: { Label(model.t("Başka yiyecek ekle", "Add another food"), systemImage: "plus") }
                        .buttonStyle(SecondaryButtonStyle())
                    Picker(model.t("Öğün", "Meal"), selection: $meal) {
                        ForEach(MealType.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(model.t("Porsiyonlar fotoğraftan kesin ölçülemez; değerler tahminidir.", "Portions can't be measured precisely from a photo; values are estimates."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.t("Yemeği doğrula", "Confirm meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.t("Ekle", "Add")) {
                        let all = state.candidates.map(\.food) + extra
                        let entries = selected.compactMap { id, multiplier -> FoodLogEntry? in
                            guard let food = all.first(where: { $0.id == id }) else { return nil }
                            return FoodLogEntry(date: Date(), meal: meal, food: food, quantity: multiplier, unit: food.defaultUnit, source: .photo)
                        }
                        model.addFoodEntries(entries)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .sheet(isPresented: $showSearch) {
                FoodPickerSheet { food in
                    extra.append(food)
                    selected[food.id] = 1
                }
            }
            .onAppear {
                if let best = state.candidates.first, best.confidence > 0.5 { selected[best.food.id] = 1 }
            }
        }
    }

    private func foodRow(_ food: FoodItem, confidence: Double?) -> some View {
        let isOn = selected[food.id] != nil
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isOn { selected[food.id] = nil } else { selected[food.id] = 1 }
            } label: {
                HStack {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
                    Text(model.t(food.name)).font(Theme.headline).foregroundStyle(.white)
                    Spacer()
                    if let confidence { Text("\(Int(confidence * 100))%").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                }
            }
            .buttonStyle(.plain)
            if isOn {
                HStack {
                    ForEach(sizes.indices, id: \.self) { index in
                        let size = sizes[index]
                        ChipButton(title: model.t(size.0), selected: selected[food.id] == size.1) { selected[food.id] = size.1 }
                    }
                }
                let grams = food.defaultPortionGrams * (selected[food.id] ?? 1)
                Text("1 \(model.t(food.defaultUnit.title)) ≈ \(Int(food.defaultPortionGrams)) g → \(Int(food.macros(grams: grams).kcal)) kcal")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

struct FoodPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (FoodItem) -> Void

    var body: some View {
        NavigationStack {
            List(FoodDatabase.search(query)) { food in
                Button {
                    onPick(food)
                    dismiss()
                } label: {
                    HStack {
                        Text(model.t(food.name)).foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(food.per100.kcal)) kcal/100g").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: model.t("Yiyecek ara", "Search food"))
            .navigationTitle(model.t("Yiyecek seç", "Choose food"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { dismiss() } } }
        }
    }
}

struct FoodSearchSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: FoodItem?
    @State private var quantity: Double = 1
    @State private var grams: Double = 100
    @State private var unit: PortionUnit = .portion
    @State private var meal = MealType.forHour(Calendar.current.component(.hour, from: Date()))

    var body: some View {
        if let food = picked {
            NavigationStack {
                Form {
                    Section(model.t(food.name)) {
                        if unit == .gram {
                            Stepper(value: $grams, in: 10...1000, step: 10) { Text("\(Int(grams)) g") }
                        } else {
                            Stepper(value: $quantity, in: 0.5...20, step: 0.5) { Text("\(formatQuantity(quantity)) × \(model.t(unit.title))") }
                        }
                        Picker(model.t("Birim", "Unit"), selection: $unit) {
                            ForEach([PortionUnit.gram] + Array(food.units.keys).sorted { $0.rawValue < $1.rawValue }, id: \.self) {
                                Text(model.t($0.title)).tag($0)
                            }
                        }
                        Picker(model.t("Öğün", "Meal"), selection: $meal) {
                            ForEach(MealType.allCases, id: \.self) { Text(model.t($0.title)).tag($0) }
                        }
                        let entry = FoodLogEntry(date: Date(), meal: meal, food: food, quantity: unit == .gram ? grams : quantity, unit: unit, source: .manual)
                        Text("\(Int(entry.grams)) g · \(Int(entry.macros.kcal)) kcal · P \(Int(entry.macros.protein)) g")
                    }
                }
                .navigationTitle(model.t("Miktar", "Amount"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.t("Ekle", "Add")) {
                            model.addFoodEntries([FoodLogEntry(date: Date(), meal: meal, food: food, quantity: unit == .gram ? grams : quantity, unit: unit, source: .manual)])
                            dismiss()
                        }
                    }
                }
            }
        } else {
            FoodPickerSheet { food in
                unit = food.defaultUnit
                DispatchQueue.main.async { picked = food }
            }
        }
    }
}

/// Speak a meal ("kahvaltıda üç yumurta ve iki dilim ekmek yedim").
struct VoiceMealSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @Environment(\.dismiss) private var dismiss
    @Binding var result: String?
    @State private var heard = ""
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                LiveOrb(voice: model.voice, size: 110)
                Text(model.t("Ne yediğini söyle. Örnek: \"Kahvaltıda üç yumurta ve iki dilim ekmek yedim.\"",
                             "Tell me what you ate. Example: \"For breakfast I had three eggs and two slices of bread.\""))
                    .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                Text(heard).font(Theme.title).foregroundStyle(.white).multilineTextAlignment(.center)
                TextField(model.t("veya yaz…", "or type…"), text: $typed)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    .onSubmit { submit(typed) }
                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { finish() } } }
            .onAppear(perform: listen)
        }
    }

    private func listen() {
        model.voice.onUtterance = { text, isFinal in
            heard = text
            guard isFinal else { return false }
            submit(text)
            return true
        }
        model.voice.isBargeIn = { _ in true }
        Task {
            if !model.voice.hasPermissions { _ = await model.voice.requestPermissions() }
            model.voice.startListening()
        }
    }

    private func submit(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let reply = assistant.logMeal(text, model: model)
        result = reply
        model.voice.say(reply, priority: .high)
        finish()
    }

    private func finish() {
        model.voice.onUtterance = nil
        model.voice.stopListening()
        dismiss()
    }
}

/// UIKit camera picker.
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}
