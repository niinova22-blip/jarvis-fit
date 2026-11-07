import Foundation

/// Built-in answers to common sport and nutrition questions, personalised with the user's own
/// targets. Used when the on-device language model is unavailable (older iPhones, Apple
/// Intelligence off) or fails, so NOVA can still hold a useful conversation everywhere.
///
/// Content is general, widely accepted guidance (e.g. ISSN/ACSM/WHO positions), never a diagnosis.
public enum FitnessKnowledge {
    struct Topic {
        let id: String
        /// Folded stems (see `TextNormalizer`); a topic needs at least one hit.
        let keys: [String]
        let answer: (AssistantContext) -> LocalizedText
    }

    /// Best matching answer, or nil when no topic fits.
    public static func answer(_ question: String, context: AssistantContext) -> LocalizedText? {
        let n = " " + TextNormalizer.normalize(question) + " "
        var best: (topic: Topic, score: Int)?
        for topic in topics {
            let score = topic.keys.reduce(0) { $0 + (n.contains(" " + $1) ? $1.count : 0) }
            if score > 0 && score > (best?.score ?? 0) { best = (topic, score) }
        }
        return best?.topic.answer(context)
    }

    /// Topic ids, for tests.
    public static func topicId(for question: String) -> String? {
        let n = " " + TextNormalizer.normalize(question) + " "
        var best: (id: String, score: Int)?
        for topic in topics {
            let score = topic.keys.reduce(0) { $0 + (n.contains(" " + $1) ? $1.count : 0) }
            if score > 0 && score > (best?.score ?? 0) { best = (topic.id, score) }
        }
        return best?.id
    }

    private static func t(_ tr: String, _ en: String) -> LocalizedText { LocalizedText(tr: tr, en: en) }

    static let topics: [Topic] = [
        Topic(id: "protein", keys: ["protein", "ne kadar protein", "how much protein"]) { c in
            let kg = Int(c.profile.weightKg)
            let low = Int((c.profile.weightKg * 1.6).rounded()), high = Int((c.profile.weightKg * 2.2).rounded())
            let target = c.nutrition.map { " Senin günlük hedefin \($0.targets.proteinG) gram." } ?? ""
            let targetEn = c.nutrition.map { " Your daily target is \($0.targets.proteinG) g." } ?? ""
            return t("Kas için günde kilo başına yaklaşık 1,6–2,2 gram protein yeterli; \(kg) kiloda bu \(low)–\(high) gram eder.\(target) Bunu 3–5 öğüne, her öğünde 20–40 gram olacak şekilde böl.",
                     "For muscle, about 1.6–2.2 g of protein per kg per day is enough; at \(kg) kg that's \(low)–\(high) g.\(targetEn) Spread it over 3–5 meals of 20–40 g each.")
        },
        Topic(id: "fatLoss", keys: ["kilo ver", "zayifla", "yag yak", "yag kayb", "lose weight", "weight loss", "fat loss", "burn fat", "definasyon", "cutting", "kilo vermek"]) { c in
            let kcal = c.nutrition.map { " Senin hedefin günde yaklaşık \($0.targets.kcal) kalori." } ?? ""
            let kcalEn = c.nutrition.map { " Your target is about \($0.targets.kcal) kcal a day." } ?? ""
            return t("Yağ kaybı için günde yaklaşık 300–500 kalorilik açık ve haftada vücut ağırlığının %0,5–1'i kadar kayıp sürdürülebilir.\(kcal) Proteini yüksek tut ve kuvvet antrenmanına devam et ki kas korunsun.",
                     "For fat loss, a daily deficit of about 300–500 kcal and losing 0.5–1% of body weight per week is sustainable.\(kcalEn) Keep protein high and keep strength training so you hold on to muscle.")
        },
        Topic(id: "muscleGain", keys: ["kas kazan", "kas yap", "kas kutle", "hacim", "bulk", "kilo al", "gain weight", "build muscle", "muscle gain", "bulking", "kaslan"]) { _ in
            t("Kas kazanmak için günde yaklaşık 200–300 kalori fazlası, yeterli protein ve her hafta biraz daha ağırlık ya da tekrar (aşamalı yüklenme) gerekir. Kas başına haftada 10–20 zorlu set ve 7–9 saat uyku hedefle.",
              "To build muscle, aim for a small surplus of about 200–300 kcal, enough protein and a little more weight or reps each week (progressive overload). Target 10–20 hard sets per muscle per week and 7–9 hours of sleep.")
        },
        Topic(id: "creatine", keys: ["kreatin", "creatine"]) { _ in
            t("Kreatin monohidrat en çok araştırılmış takviyelerden; günde 3–5 gram, her gün düzenli alınır, yükleme şart değil. İlk haftalarda 1–2 kilo su tutulumu normaldir. Böbrek rahatsızlığın varsa önce doktoruna danış.",
              "Creatine monohydrate is one of the best-researched supplements: 3–5 g every day, no loading needed. A 1–2 kg water gain in the first weeks is normal. If you have kidney problems, ask your doctor first.")
        },
        Topic(id: "proteinPowder", keys: ["whey", "protein tozu", "protein shake", "protein powder", "bcaa"]) { _ in
            t("Protein tozu sadece pratik bir protein kaynağı; günlük hedefini yemekle tamamlayabiliyorsan şart değil. BCAA yeterli protein alan biri için ek fayda sağlamaz.",
              "Protein powder is just a convenient protein source; if you reach your daily target with food, you don't need it. BCAAs add nothing if your total protein is already sufficient.")
        },
        Topic(id: "preWorkout", keys: ["antrenman oncesi", "antrenmandan once", "sporden once", "spordan once", "before workout", "before training", "pre workout", "preworkout"]) { _ in
            t("Antrenmandan 1–3 saat önce karbonhidrat ve protein içeren normal bir öğün ideal; örneğin yulaf ve yoğurt ya da pilav ve tavuk. Vaktin azsa 30–60 dakika önce bir muz yeterli.",
              "A normal meal with carbs and protein 1–3 hours before training is ideal, e.g. oats with yogurt or rice with chicken. Short on time? A banana 30–60 minutes before is enough.")
        },
        Topic(id: "postWorkout", keys: ["antrenman sonrasi", "antrenmandan sonra", "spordan sonra", "after workout", "after training", "post workout"]) { _ in
            t("Antrenmandan sonraki birkaç saat içinde 20–40 gram protein ve biraz karbonhidrat al; örneğin yumurta ve ekmek ya da yoğurt ve meyve. 'Hemen 30 dakika içinde' kuralı katı değil, günlük toplam daha önemli.",
              "Within a few hours after training, have 20–40 g of protein with some carbs, e.g. eggs and bread or yogurt and fruit. The strict '30-minute window' isn't required; your daily total matters more.")
        },
        Topic(id: "water", keys: ["su ic", "ne kadar su", "sivi", "hydrat", "water", "electrolyte", "elektrolit"]) { c in
            let liters = String(format: "%.1f", c.profile.weightKg * 0.033)
            return t("Günde kilo başına yaklaşık 30–35 ml, yani senin için yaklaşık \(liters.replacingOccurrences(of: ".", with: ",")) litre su iyi bir başlangıç; antrenman saati başına 0,4–0,8 litre ekle. İdrar renginin açık sarı olması yeterli içtiğini gösterir.",
                     "About 30–35 ml per kg a day — roughly \(liters) litres for you — is a good start; add 0.4–0.8 L per hour of training. Pale yellow urine means you're drinking enough.")
        },
        Topic(id: "sleep", keys: ["uyku", "uyuyam", "uyumak", "sleep", "insomnia"]) { _ in
            t("Kas gelişimi ve toparlanma için 7–9 saat uyku hedefle. Her gün aynı saatte yat, yatmadan 1 saat önce ekranı azalt ve akşam geç saatte kafeinden kaçın.",
              "Aim for 7–9 hours of sleep for recovery and muscle growth. Keep a regular bedtime, cut screens an hour before bed and avoid caffeine late in the day.")
        },
        Topic(id: "soreness", keys: ["kas agri", "kasim agri", "kaslarim agri", "agriyor", "sore", "doms", "soreness", "tutuldum", "tutulma"]) { _ in
            t("Antrenmandan 24–72 saat sonra gelen kas ağrısı normaldir; hafif hareket, yürüyüş, iyi uyku ve yeterli protein geçmesine yardım eder. Keskin, eklemde ya da geçmeyen bir ağrıysa antrenmanı bırak ve bir sağlık profesyoneline danış.",
              "Muscle soreness 24–72 hours after training is normal; light movement, walking, good sleep and enough protein help. If the pain is sharp, in a joint or doesn't go away, stop training and see a health professional.")
        },
        Topic(id: "warmup", keys: ["isinma", "isinmak", "warm up", "warmup"]) { _ in
            t("5–10 dakika hafif kardiyo, ardından dinamik hareketler (bacak savurma, kol çevirme) ve ilk harekette 1–2 hafif set yeterli bir ısınmadır.",
              "5–10 minutes of light cardio, then dynamic moves (leg swings, arm circles) and 1–2 light sets of your first exercise make a good warm-up.")
        },
        Topic(id: "stretching", keys: ["esneme", "esnet", "esneklik", "stretch", "flexibility", "mobilite", "mobility"]) { _ in
            t("Antrenman öncesi dinamik esneme, sonrası ya da ayrı bir zamanda statik esneme (her pozisyonda 20–40 saniye) önerilir. Düzenli esneme hareket açıklığını artırır.",
              "Use dynamic stretching before training and static stretches (20–40 seconds each) afterwards or at another time. Regular stretching improves range of motion.")
        },
        Topic(id: "frequency", keys: ["kac gun", "haftada kac", "dinlenme gun", "rest day", "how often", "how many days", "her gun spor", "every day"]) { c in
            let days = c.profile.availableDays.count
            return t("Her kas grubunu haftada 2 kez çalıştırmak ve aynı kası tekrar zorlamadan önce yaklaşık 48 saat dinlendirmek iyi çalışır. Senin programın haftada \(days) güne göre ayarlandı.",
                     "Training each muscle group twice a week and resting a muscle about 48 hours before working it hard again works well. Your plan is built around \(days) days a week.")
        },
        Topic(id: "setsReps", keys: ["kac set", "kac tekrar", "set tekrar", "how many sets", "how many reps", "sets and reps", "rep range"]) { _ in
            t("Kas gelişimi için çoğunlukla 6–15 tekrar, sete 1–3 tekrar kala bitirerek; kuvvet için 3–6 tekrar ve setler arası 2–3 dakika dinlenme. Kas başına haftada 10–20 set iyi bir aralık.",
              "For muscle growth, mostly 6–15 reps, stopping 1–3 reps short of failure; for strength, 3–6 reps with 2–3 minutes rest. 10–20 sets per muscle per week is a good range.")
        },
        Topic(id: "cardio", keys: ["kardiyo", "cardio", "kosu", "running", "jogging", "hiit", "yuruyus", "walking"]) { _ in
            t("Sağlık için haftada en az 150 dakika orta ya da 75 dakika yüksek tempolu kardiyo önerilir (DSÖ). Kuvvet antrenmanıyla birlikte yapınca hem kalp sağlığı hem yağ kaybı için en iyi sonucu verir; yeni başlıyorsan yürüyüş-koşu aralıklarıyla başla.",
              "For health, at least 150 minutes of moderate or 75 minutes of vigorous cardio a week is recommended (WHO). Combined with strength training it's best for heart health and fat loss; beginners can start with walk–run intervals.")
        },
        Topic(id: "spotReduction", keys: ["gobek", "gobeg", "karin yag", "bolgesel", "belly fat", "spot reduc", "lose belly"]) { _ in
            t("Belirli bir bölgeden (örneğin göbekten) yağ yakmak mümkün değil; mekik karın kaslarını güçlendirir ama yağı oradan eritmez. Yağ, kalori açığıyla tüm vücuttan azalır.",
              "You can't burn fat from one spot such as the belly; crunches strengthen the abs but don't melt fat there. Fat comes off the whole body with a calorie deficit.")
        },
        Topic(id: "plateau", keys: ["ilerleyemiyorum", "gelisemiyorum", "takildim", "plato", "plateau", "not progressing", "stuck", "kilo vermiyorum"]) { _ in
            t("İlerleme durduysa: aşamalı yüklenme yapıyor musun, uykun yeterli mi, kalori ve proteinin hedefte mi, kontrol et. 4–8 haftada bir hafif bir hafta (deload) da yardımcı olur.",
              "If progress stalls, check that you're adding weight or reps over time, sleeping enough and hitting your calories and protein. A lighter deload week every 4–8 weeks also helps.")
        },
        Topic(id: "carbs", keys: ["karbonhidrat", "karb", "carb", "ekmek", "pirinc", "makarna", "bread", "rice", "pasta"]) { c in
            let carbs = c.nutrition.map { " Senin günlük hedefin yaklaşık \($0.targets.carbsG) gram." } ?? ""
            let carbsEn = c.nutrition.map { " Your daily target is about \($0.targets.carbsG) g." } ?? ""
            return t("Karbonhidrat kötü değil, antrenman için ana yakıttır.\(carbs) Tam tahıl, yulaf, baklagil, meyve ve sebzeyi tercih et; şekerli ve işlenmiş olanları sınırla.",
                     "Carbs aren't bad; they're the main fuel for training.\(carbsEn) Prefer whole grains, oats, legumes, fruit and vegetables, and limit sugary, processed ones.")
        },
        Topic(id: "fats", keys: ["yag ye", "saglikli yag", "zeytinyag", "avokado", "omega", "healthy fat", "dietary fat"]) { c in
            let fat = c.nutrition.map { " Senin hedefin yaklaşık \($0.targets.fatG) gram." } ?? ""
            let fatEn = c.nutrition.map { " Your target is about \($0.targets.fatG) g." } ?? ""
            return t("Yağ hormonlar için gerekli; kalorilerin yaklaşık %20–35'i yağdan gelebilir.\(fat) Zeytinyağı, kuruyemiş, avokado ve balık gibi doymamış yağları tercih et.",
                     "Fat is essential for hormones; about 20–35% of calories can come from fat.\(fatEn) Prefer unsaturated fats like olive oil, nuts, avocado and fish.")
        },
        Topic(id: "sugar", keys: ["seker", "tatli", "cikolata", "sugar", "dessert", "sweets", "chocolate"]) { _ in
            t("Eklenmiş şekeri günlük kalorinin %10'unun altında tutmak önerilir (DSÖ). Arada bir tatlı sorun değil; hedeflerine uyduğu sürece ölçülü ye.",
              "Keeping added sugar under 10% of daily calories is recommended (WHO). An occasional dessert is fine as long as it fits your targets.")
        },
        Topic(id: "alcohol", keys: ["alkol", "bira", "sarap", "alcohol", "beer", "wine"]) { _ in
            t("Alkol toparlanmayı ve uykuyu bozar, kas yapımını yavaşlatır ve boş kalori içerir. İçeceksen az ve seyrek iç, antrenmandan hemen sonra ve öncesinde kaçın.",
              "Alcohol disrupts recovery and sleep, slows muscle building and adds empty calories. If you drink, keep it light and occasional, and avoid it right around training.")
        },
        Topic(id: "fasting", keys: ["oruc", "aralikli", "intermittent", "fasting", "16 8", "kahvalti atla", "skip breakfast"]) { _ in
            t("Aralıklı oruç kaloriyi kontrol etmenin bir yolu; yağ kaybında asıl belirleyici toplam kalori ve protein. Sana kolay geliyorsa uygulayabilirsin, antrenman günlerinde proteini yeme penceresine sığdır.",
              "Intermittent fasting is one way to control calories; total calories and protein are what drive fat loss. Use it if it suits you, and fit your protein into the eating window on training days.")
        },
        Topic(id: "caffeine", keys: ["kafein", "kahve", "pre workout takviye", "caffeine", "coffee", "energy drink"]) { c in
            let mg = Int(c.profile.weightKg * 3)
            return t("Kafein performansı artırabilir: antrenmandan 30–60 dakika önce kilo başına yaklaşık 3 mg (senin için ~\(mg) mg). Sağlıklı yetişkinler için günde 400 mg'ı aşma ve akşam saatlerinde kaçın.",
                     "Caffeine can boost performance: about 3 mg per kg (~\(mg) mg for you) 30–60 minutes before training. Healthy adults should stay under 400 mg a day and avoid it in the evening.")
        },
        Topic(id: "supplements", keys: ["takviye", "vitamin", "mineral", "supplement", "multivitamin", "d vitamin", "magnezyum", "magnesium", "omega 3"]) { _ in
            t("Önce yemek: dengeli beslenen biri için çoğu takviye gereksiz. Kreatin, kafein ve protein tozu dışında kanıtı güçlü takviye az; D vitamini gibi eksiklikleri kan tahliliyle doktorunla değerlendir.",
              "Food first: most supplements are unnecessary with a balanced diet. Beyond creatine, caffeine and protein powder, few have strong evidence; check deficiencies like vitamin D with a blood test and your doctor.")
        },
        Topic(id: "weightFluctuation", keys: ["kilom artti", "kilo dalgalan", "tartida", "tarti", "scale weight", "weight went up", "weight fluctuat"]) { _ in
            t("Tartıdaki değer su, tuz ve sindirim yüzünden günden güne 1–2 kilo oynayabilir. Haftalık ortalamaya bak; tek güne değil.",
              "Scale weight can swing 1–2 kg day to day from water, salt and digestion. Watch the weekly average, not single days.")
        },
        Topic(id: "beginner", keys: ["yeni basl", "nereden basl", "nasil basl", "beginner", "how to start", "where to start", "just started"]) { _ in
            t("Yeni başlıyorsan haftada 2–3 gün tüm vücut antrenmanı, temel hareketler (squat, şınav, lunge, plank) ve doğru form en iyi başlangıç. Her hafta biraz artır, düzenlilik her şeyden önemli.",
              "As a beginner, 2–3 full-body sessions a week with the basics (squat, push-up, lunge, plank) and good form is the best start. Add a little each week; consistency matters most.")
        },
        Topic(id: "homeWorkout", keys: ["evde", "ekipmansiz", "aletsiz", "at home", "no equipment", "bodyweight", "vucut agirlig"]) { _ in
            t("Evde ekipmansız da gelişebilirsin: squat, lunge, şınav, glute bridge, plank ve mekik; zorlaştırmak için tekrarı, tempoyu yavaşlatmayı ya da tek bacak/kol varyasyonlarını kullan. Canlı antrenörde bu hareketleri sayıp formunu takip ediyorum.",
              "You can progress at home without equipment: squats, lunges, push-ups, glute bridges, planks and crunches; make them harder with more reps, slower tempo or single-leg/arm versions. In Live Coach I count these and track your form.")
        },
        Topic(id: "vegan", keys: ["vegan", "vejetaryen", "bitkisel protein", "et yemiyorum", "vegetarian", "plant protein", "plant based"]) { _ in
            t("Bitkisel beslenmede mercimek, nohut, fasulye, tofu, tempeh, edamame, tam tahıllar ve (vejetaryensen) yumurta ve süt ürünleri iyi protein kaynakları. Farklı kaynakları gün içinde birleştir; B12 için doktoruna danış.",
              "On a plant-based diet, lentils, chickpeas, beans, tofu, tempeh, edamame, whole grains and (if vegetarian) eggs and dairy are good protein sources. Combine sources through the day and ask your doctor about B12.")
        },
        Topic(id: "injury", keys: ["sakatl", "incindi", "burkul", "eklem agri", "diz agri", "bel agri", "omuz agri", "injur", "knee pain", "back pain", "shoulder pain", "joint pain"]) { _ in
            t("Teşhis koyamam. Keskin ya da geçmeyen ağrı, şişlik veya eklem ağrısında o bölgeyi zorlayan hareketi bırak ve bir doktor ya da fizyoterapiste görün. İyileşene kadar ağrısız hareketlerle devam edebiliriz.",
              "I can't diagnose. With sharp or persistent pain, swelling or joint pain, stop the movement that loads it and see a doctor or physiotherapist. Until then we can keep training with pain-free movements.")
        },
        Topic(id: "motivation", keys: ["motivasyon", "canim istemiyor", "usendim", "istek yok", "motivation", "motivated", "lazy", "dont feel like"]) { _ in
            t("Motivasyon gelip gider, düzen kalır: antrenmanı takvimine sabit bir saat olarak koy, hedefi küçült (sadece 10 dakika başla) ve ilerlemeni kaydet. Başladıktan sonra genelde devamı gelir.",
              "Motivation comes and goes; habits stay. Put training at a fixed time in your calendar, shrink the goal (just start for 10 minutes) and track your progress. Once you start, the rest usually follows.")
        },
        Topic(id: "healthyMeal", keys: ["ne yesem", "ne yemeliyim", "saglikli yemek", "ogun oner", "tarif", "what should i eat", "healthy meal", "meal idea", "recipe"]) { c in
            t("Dengeli bir tabak: yarısı sebze, çeyreği protein (tavuk, balık, yumurta, baklagil, yoğurt), çeyreği tam tahıl ya da patates, üstüne biraz zeytinyağı. Hedefin \(c.profile.goal.title.tr.lowercased()) için proteini her öğüne koy.",
              "A balanced plate: half vegetables, a quarter protein (chicken, fish, eggs, legumes, yogurt), a quarter whole grains or potatoes, plus a little olive oil. For your goal (\(c.profile.goal.title.en.lowercased())), put protein in every meal.")
        },
    ]
}
