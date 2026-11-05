# JARVIS FIT — Geliştirme Durumu

_Son güncelleme: 2026-11-05_

## Özet

| Alan | Durum | Doğrulama |
|---|---|---|
| JarvisCore (platformdan bağımsız mantık) | ✅ Tamam | 65 otomatik test, Windows'ta (Swift 6.4) geçti |
| Canlı antrenör algoritmaları (10 hareket) | ✅ Kod + sentetik testler | ⚠️ Gerçek kullanıcı videolarıyla doğrulanmadı |
| Eller serbest oturum motoru | ✅ Kod + uçtan uca simülasyon testi | ⚠️ Cihazda doğrulanmadı |
| iOS uygulaması (SwiftUI) | ✅ Kod yazıldı | ❌ Henüz derlenmedi (macOS gerekir → GitHub Actions) |
| Kamera + Vision poz | ✅ Kod | ❌ Cihaz testi gerekli |
| Ses (STT/TTS, AEC, araya girme) | ✅ Kod | ❌ Cihaz testi gerekli |
| Yerel LLM (Apple Foundation Models) | ✅ Kod (iOS 26+) | ❌ Cihaz testi gerekli |
| Planlayıcı, beslenme, adaptif motor | ✅ Kod + testler | ✅ Birim testleri |
| Yemek fotoğrafı tanıma | ✅ Kod (VNClassifyImageRequest) | ❌ Doğruluk ölçülmedi |
| Fit Check ölçümleri | ✅ Kod + matematik testleri | ❌ Mezura ile karşılaştırma yapılmadı |
| StoreKit 2 abonelik | ✅ Kod + .storekit dosyası | ❌ App Store Connect'te ürünler oluşturulmadı |
| CI (GitHub Actions) | ✅ ci.yml, testflight.yml | ❌ Depo henüz GitHub'a gönderilmedi |
| TestFlight | ⏳ Hazır iş akışı | ❌ Engelleyiciler aşağıda |

## TestFlight için kalan engelleyiciler

1. **GitHub'a gönderme**: Depo yerel (`main` dalı). `gh repo create jarvis-fit --private --source . --push`.
   - Not: Private depoda macOS dakikaları ücretli kotadan düşer (macOS = 10x). Diğer uygulama depoların public.
2. **Gizli anahtarlar**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (App Store Connect API anahtarı, Admin
   rolü). strengthspan deposundaki anahtar kullanılabilir: `gh secret set ... -R niinova22-blip/jarvis-fit`.
3. **App Store Connect uygulama kaydı**: Bundle ID `com.niinova.jarvisfit` (preflight adımı API ile kaydeder).
   Uygulama kaydı API ile oluşturulamaz: App Store Connect > Uygulamalar > + > Yeni Uygulama.
4. İş akışını çalıştır: `gh workflow run TestFlight -R niinova22-blip/jarvis-fit`.

## Sonraki adımlar (öncelik sırası)

1. CI'da iOS derleme hatalarını düzelt (kod ilk kez macOS'ta derlenecek).
2. TestFlight yüklemesi.
3. Gerçek cihazda Canlı Antrenör doğrulaması — `docs/DEVICE_TESTING.md`.
4. Gerçek oturum kayıtlarından (poz JSON) eşik ayarı; kayıt aracı ekle (Settings > Developer).
5. App Store Connect'te abonelik ürünleri (`com.niinova.jarvisfit.premium.monthly` 12,99 USD,
   `...yearly` 79,99 USD) ve gizlilik politikası sayfası.
6. App Store adı/marka kontrolü (bkz. RESEARCH.md › Riskler).
