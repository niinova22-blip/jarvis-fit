# JARVIS FIT — Geliştirme Durumu

_Son güncelleme: 2026-11-05 (2. oturum)_

## Özet

| Alan | Durum | Doğrulama |
|---|---|---|
| JarvisCore (platformdan bağımsız mantık) | ✅ Tamam | 85 otomatik test (1 atlanan: gerçek kayıt fixture'ı yok), Windows'ta (Swift 6.4) geçti |
| Canlı antrenör algoritmaları (10 hareket) | ✅ Kod + sentetik testler | ⚠️ Gerçek kullanıcı verisiyle doğrulanmadı → poz kayıt aracı hazır |
| Eller serbest oturum motoru | ✅ Kod + uçtan uca simülasyon testi | ⚠️ Cihazda doğrulanmadı |
| Poz kaydı + tekrar oynatma (gerçek veriyle doğrulama) | ✅ Kod + testler | Kullanıcı kaydı bekleniyor |
| Hafif mod (eski cihaz / ısı / düşük güç) | ✅ Politika + testler, kamera entegrasyonu | ❌ iPhone 12/13'te ölçülmedi |
| iOS uygulaması (SwiftUI) | ✅ Kod yazıldı, elle gözden geçirildi | ❌ Henüz derlenmedi (macOS gerekir → GitHub Actions) |
| Kamera + Vision poz | ✅ Kod | ❌ Cihaz testi gerekli |
| Ses (STT/TTS, AEC, araya girme) | ✅ Kod | ❌ Cihaz testi gerekli |
| Sesli onboarding (cevapları konuşarak verme) | ✅ Ayrıştırıcı + testler + ekran entegrasyonu | ❌ Cihaz testi gerekli |
| Yerel LLM (Apple Foundation Models) | ✅ Kod (iOS 26+) | ❌ Cihaz testi gerekli |
| Planlayıcı, aşamalı yüklenme, kaçırılan antrenmanı taşıma | ✅ Kod + testler | ✅ Birim testleri |
| Adaptif motor (7 kural, açıklamalı, kullanıcı onaylı) | ✅ Kod + testler | ✅ Birim testleri |
| Haftalık rapor, hareket bazlı gelişim grafiği, motivasyon | ✅ Kod + testler | ✅ Birim testleri |
| Kişiselleştirilmiş bildirimler (7 günlük brifing, hatırlatma, haftalık) | ✅ Kod | ❌ Cihaz testi gerekli |
| Yemek fotoğrafı tanıma + doğrulama soruları (yağ/şeker/sos) | ✅ Kod + testler | ❌ Tanıma doğruluğu ölçülmedi |
| Fit Check ölçümleri + duruş değişimi | ✅ Kod + matematik testleri | ❌ Mezura ile karşılaştırma yapılmadı |
| Ücretsiz / Premium ayrımı (şartnameye göre) | ✅ Kod | ❌ Sandbox satın alma testi gerekli |
| StoreKit 2 abonelik | ✅ Kod + .storekit dosyası | ❌ App Store Connect'te ürünler oluşturulmadı |
| Gizlilik: PrivacyInfo.xcprivacy, uygulama içi politika, docs/privacy.html | ✅ | Barındırma URL'si gerekli (App Store Connect) |
| Veri güvenliği (dayanıklı JSON çözme, bozuk dosya yedeği) | ✅ Kod + uygulama testi | CI'da çalışacak |
| CI (GitHub Actions) | ✅ ci.yml, testflight.yml | ❌ Depo henüz GitHub'a gönderilmedi |
| TestFlight | ⏳ Hazır iş akışı | ❌ Engelleyiciler aşağıda |

## Şartname karşılaştırması (ilk prompt)

- §2 Onboarding: 5 hedef, yaş/boy/kilo, geçmiş, ekipman, günler/saat, sağlık, beslenme; JARVIS soruları sesli sorar,
  cevaplar dokunarak **veya konuşarak** verilebilir. ✅
- §3 Live Coach: 10 hareket, ayrı algoritmalar, faz tespiti, tanıma, sayım, tempo, form (yalnızca güvenilir olanlar),
  set/dinlenme, set içi zorluk ayarı, kadraj yönlendirmesi, LLM'den bağımsız. ✅ (cihaz doğrulaması bekliyor)
- §4 Voice: yerel STT/LLM/TTS, komutlar, sıra yönetimi, araya girme, AEC, hafıza, olay motoru, TR/EN. ✅
- §5 Kişilik (4) + hafıza (görüntüle/sil/kapat, veri minimizasyonu). ✅
- §6 Planlayıcı: kurallı, bilimsel; sıra, set/tekrar, dinlenme, aşamalı yüklenme, kaçırılanı yeniden planlama,
  alternatif hareket, toparlanma. ✅
- §7 Beslenme: foto tanıma, çoklu yiyecek, porsiyon + doğrulama soruları, makrolar, hedef karşılaştırma, sesli kayıt. ✅
- §8 Fit Check: silüet, bel/göğüs/kalça/kol/bacak tahmini (aralıklı), duruş + değişimi, önce-sonra, grafikler. ✅
- §9 Adaptif: performans artış/düşüş, zorluk, beslenme hedefi, alışkanlık (saat), toparlanma, uzun vadeli trend;
  açıklanabilir ve kullanıcı onaylı. ✅
- §10 Brifing: günlük özet, makrolar, hatırlatmalar, haftalık rapor, motivasyon, kişisel bildirimler. ✅
- §11 8 ekran, koyu tema, durum küresi, canlı kamera HUD. ✅
- §12 Freemium + StoreKit 2 (12,99 / 79,99 USD). ✅ (ASC ürünleri oluşturulmalı)
- §13 Güvenlik: ağrı/baş dönmesi → durdurma, teşhis yok, sağlık kısıtlarına göre hareket seçimi. ✅
- §14–15 Testler, CI, durum dosyaları. ✅ — Gerçek cihaz testleri: `docs/DEVICE_TESTING.md`.

## TestFlight için kalan engelleyiciler

1. **GitHub'a gönderme** (otomatik izin sistemi engelledi; kullanıcı çalıştırmalı):
   `gh repo create jarvis-fit --private --source . --remote origin --push`
   - Private depoda macOS dakikaları ücretli kotadan düşer (macOS = 10x). Diğer uygulama depoların public.
2. **Gizli anahtarlar**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (App Store Connect API anahtarı, Admin
   rolü). strengthspan deposundaki anahtar kullanılabilir: `gh secret set ... -R niinova22-blip/jarvis-fit`.
3. **App Store Connect uygulama kaydı**: Bundle ID `com.niinova.jarvisfit` (preflight adımı API ile kaydeder).
   Uygulama kaydı API ile oluşturulamaz: App Store Connect > Uygulamalar > + > Yeni Uygulama.
4. İş akışını çalıştır: `gh workflow run TestFlight -R niinova22-blip/jarvis-fit`.

## Sonraki adımlar (öncelik sırası)

1. CI'da iOS derleme hatalarını düzelt (kod ilk kez macOS'ta derlenecek).
2. TestFlight yüklemesi.
3. Gerçek cihazda Canlı Antrenör doğrulaması: poz kayıtlarını topla, etiketle, `Fixtures/`'a koy, eşikleri ayarla.
4. App Store Connect'te abonelik ürünleri (`com.niinova.jarvisfit.premium.monthly` 12,99 USD,
   `...yearly` 79,99 USD), gizlilik politikası URL'si (docs/privacy.html barındırılmalı).
5. App Store adı/marka kontrolü (bkz. RESEARCH.md › Riskler).
