import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = SubscriptionManager.yearlyID
    @State private var message: String?

    private var features: [(String, String)] {
        [("camera.viewfinder", model.t("Sınırsız canlı antrenman", "Unlimited live workouts")),
         ("waveform", model.t("Gelişmiş NOVA sohbeti ve kişisel hafıza", "Advanced NOVA chat and personal memory")),
         ("fork.knife", model.t("Sınırsız yerel yemek analizi", "Unlimited on-device meal analysis")),
         ("figure.stand", model.t("Fit Check vücut analizi", "Fit Check body analysis")),
         ("chart.line.uptrend.xyaxis", model.t("Gelişim raporları ve adaptif program", "Progress reports and adaptive plan"))]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        JarvisOrb(state: .speaking, size: 110)
                        Spacer()
                    }
                    Text("NOVA Coach Premium").font(Theme.display(30)).foregroundStyle(.white)
                    ForEach(features.indices, id: \.self) { i in
                        Label(features[i].1, systemImage: features[i].0).font(Theme.body).foregroundStyle(.white)
                    }
                    if subscriptions.products.isEmpty {
                        Text(model.t("Abonelik seçenekleri yüklenemedi. İnternet bağlantını kontrol et; satın alma ve geri yükleme için bağlantı gerekir.",
                                     "Subscription options couldn't be loaded. Check your connection; purchasing and restoring need internet."))
                            .font(Theme.caption).foregroundStyle(Theme.warning)
                        Button(model.t("Tekrar dene", "Retry")) { Task { await subscriptions.loadProducts() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    ForEach(subscriptions.products, id: \.id) { product in
                        Button { selectedID = product.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.id == SubscriptionManager.yearlyID ? model.t("Yıllık", "Yearly") : model.t("Aylık", "Monthly"))
                                        .font(Theme.headline).foregroundStyle(.white)
                                    Text(product.displayPrice + (product.id == SubscriptionManager.yearlyID ? model.t(" / yıl", " / year") : model.t(" / ay", " / month")))
                                        .font(Theme.body).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if product.id == SubscriptionManager.yearlyID {
                                    Text(model.t("En avantajlı", "Best value")).font(Theme.caption).foregroundStyle(.black)
                                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.accent))
                                }
                                Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(selectedID == product.id ? Theme.accentSoft : Theme.surface))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        guard let product = subscriptions.products.first(where: { $0.id == selectedID }) else { return }
                        Task {
                            switch await subscriptions.purchase(product) {
                            case .success: dismiss()
                            case .pending: message = model.t("Satın alma onay bekliyor.", "Purchase is pending approval.")
                            case .cancelled: break
                            case .failed(let error): message = error
                            }
                        }
                    } label: {
                        if subscriptions.purchaseInProgress { ProgressView().tint(.black) } else { Text(model.t("Devam et", "Continue")) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(subscriptions.products.isEmpty)
                    Button(model.t("Satın alımları geri yükle", "Restore purchases")) {
                        Task {
                            let restored = await subscriptions.restore()
                            message = restored ? model.t("Premium geri yüklendi.", "Premium restored.") : model.t("Aktif abonelik bulunamadı.", "No active subscription found.")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if let message { Text(message).font(Theme.caption).foregroundStyle(Theme.warning) }
                    Text(model.t("Abonelik, dönem bitmeden en az 24 saat önce iptal edilmezse otomatik yenilenir. Ödeme Apple Kimliği hesabından alınır. Aboneliğini App Store hesap ayarlarından yönetebilir ve iptal edebilirsin.",
                                 "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Payment is charged to your Apple Account. Manage or cancel in your App Store account settings."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Link(model.t("Kullanım Koşulları", "Terms of Use"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Spacer()
                        NavigationLink(model.t("Gizlilik Politikası", "Privacy Policy")) { PrivacyPolicyView() }
                    }
                    .font(Theme.caption)
                }
                .padding(20)
            }
            .novaBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("Kapat", "Close")) { dismiss() } } }
        }
    }
}
