import SwiftUI

/// In-app privacy policy (also published as docs/privacy.html for the App Store listing).
struct PrivacyPolicyView: View {
    @EnvironmentObject private var model: AppModel

    private var sections: [(String, String)] {
        if model.language == .turkish {
            return [
                ("Özet", "NOVA Coach tüm yapay zekâ işlemlerini iPhone'unda yapar. Bir sunucumuz yoktur; verilerin bize veya üçüncü taraflara gönderilmez. Reklam, izleme veya analiz SDK'sı kullanılmaz."),
                ("Kamera", "Canlı antrenmanda kamera görüntüsü yalnızca anlık olarak vücut eklemlerini bulmak için işlenir ve kaydedilmez. Fit Check ve yemek fotoğrafları yalnızca sen istersen cihazda saklanır ve istediğin an silinebilir."),
                ("Mikrofon ve konuşma", "Sesli komutlar Apple'ın cihaz üzerindeki konuşma tanıma özelliğiyle işlenir. Ses kaydı saklanmaz. Sohbet metinleri cihazda tutulur ve Ayarlar'dan silinebilir."),
                ("Kişisel hafıza", "NOVA yalnızca kısa bilgileri (hedefler, sevdiğin hareketler, başarılar) hatırlar. Hafızayı görüntüleyebilir, tek tek veya tamamen silebilir ya da kapatabilirsin."),
                ("Sağlık ve vücut verileri", "Profil, antrenman, beslenme, kilo ve ölçüm verilerin yalnızca bu cihazda, iOS veri koruması ile şifreli olarak saklanır. Apple Sağlık'a erişim yoktur."),
                ("Satın almalar", "Abonelikler Apple'ın App Store'u üzerinden yapılır ve doğrulanır. Ödeme bilgilerini görmeyiz."),
                ("Verilerini silme", "Ayarlar > Gizlilik > Tüm verilerimi sil ile her şeyi kalıcı olarak silebilirsin. Uygulamayı silmek de tüm verileri kaldırır."),
                ("Çocuklar", "Uygulama 13 yaş altındaki çocuklara yönelik değildir."),
                ("İletişim", "Sorular için App Store sayfasındaki destek bağlantısını kullanabilirsin.")
            ]
        }
        return [
            ("Summary", "NOVA Coach runs all AI on your iPhone. There is no server; your data is never sent to us or third parties. No advertising, tracking or analytics SDKs are used."),
            ("Camera", "During live workouts, camera frames are processed in real time only to locate body joints and are not recorded. Fit Check and meal photos are stored on the device only if you choose, and can be deleted at any time."),
            ("Microphone and speech", "Voice commands are processed with Apple's on-device speech recognition. Audio is not stored. Chat text stays on the device and can be deleted in Settings."),
            ("Personal memory", "NOVA only remembers short facts (goals, favourite moves, achievements). You can view, delete individual items, erase everything, or turn memory off."),
            ("Health and body data", "Your profile, workouts, nutrition, weight and measurements are stored only on this device, encrypted with iOS data protection. The app does not access Apple Health."),
            ("Purchases", "Subscriptions are purchased and verified through Apple's App Store. We never see your payment details."),
            ("Deleting your data", "Settings > Privacy > Delete all my data permanently removes everything. Deleting the app also removes all data."),
            ("Children", "The app is not directed at children under 13."),
            ("Contact", "Use the support link on the App Store page for questions.")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sections[index].0).font(Theme.headline).foregroundStyle(.white)
                        Text(sections[index].1).font(Theme.body).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(20)
        }
        .novaBackground()
        .navigationTitle(model.t("Gizlilik politikası", "Privacy policy"))
    }
}
