# NOVA Coach (eski adı JARVIS FIT) — Geliştirme Durumu

_Son güncelleme: 2026-11-08_

## 2026-11-08 (2) — Her açı/mesafeden algılama + konu sınırlı AI sohbet

- **Uyarlanabilir tekrar sayacı** (`AdaptiveRepCounter`, `AdaptiveSignalSpec`): her hareket için bakış açısından
  bağımsız sinyal (squat/lunge: kalça yüksekliği, şınav: omuz, curl/press/yana açış/jumping jack: bilek–omuz, bilek
  kadraj dışındaysa dirsek), vücut ölçeğine göre eşik (uzaklıktan bağımsız), kullanıcının kendi genliğinden öğrenilen
  eşik ve canlı gürültü tahmini (uzakta titreyen eklemler sahte tekrar üretmesin). Açı sayacı yine önde (daha iyi form
  geri bildirimi); görmediği ya da 2 tekrar geride kaldığı durumda uyarlanabilir sayaç devralır. Açı sayacının
  vücut hareketi olmayan "tekrar"ları elenir.
- **Kadraj:** sabit mesafe/yükseklik/yan-ön şartı kaldırıldı; yalnızca hareketin ihtiyaç duyduğu eklemler aranır
  (kol hareketleri yakın çekimde çalışır), kişi çok küçükse "yaklaş" der. "Hazır" bekleme 1,0 → 0,6 sn.
- **Uzak mesafe:** kişi kadrajın ~%45'inden küçükse Vision kişinin etrafındaki bölgede (ROI) çalışır = dijital
  yakınlaştırma. ROI koordinat dönüşümü çalışma anında önceki kareyle doğrulanır.
- **Testler:** `AnyAngleTests` — 10 hareket × 6 yerleşim (uzak ~6 m, uzak+kenarda, yakın çekim/uzuvlar kadraj dışı,
  ~65° çapraz, telefon yerde, uzak+çapraz+alçak) tam sayım; hareketsiz dururken 0; önden şınav; şınav pozisyonuna
  iniş tekrar sayılmaz. ⚠️ Sentetik veri; gerçek kayıtlarla eşikler ayarlanmalı.
- **AI sohbet:** `TopicGuard` (spor/beslenme dışını modele sormadan reddeder, selam/teşekkürü reddetmez), model
  talimatları "spor ve beslenmenin her konusu" + standart red cümlesi, Apple modeli yapılandırılmış çıktı
  (`onTopic` + cevap) döndürür. Modeli olmayan cihazlarda `FitnessKnowledge` (31 konu, kişiye göre) cevap verir.
  Red cümlesi: "Ben yalnızca spor ve beslenme konusunda yardımcı olabilirim…". ❌ Model davranışı cihazda denenmeli.

## 2026-11-08 — Yeniden markalama + App Store reddi düzeltmesi

- **ITMS-90208 (1.0 build 106 ve 108 reddedildi):** `onnxruntime.framework`'ün Info.plist'i
  `MinimumOSVersion 15.1` diyor, ama Xcode framework ikilisini uygulamanın hedefiyle (iOS 17) bağlıyor; Apple
  ikilinin minimum sürümü ile Info.plist uyuşmadığı için reddediyor. (İlk tahmin "statik framework" yanlıştı:
  arşivdeki ikili dinamik; o adım hiçbir şeyi silmedi.) Düzeltme `testflight.yml`: arşivden sonra her gömülü
  framework'ün Info.plist'ine ikilinin gerçek `minos` değeri yazılır (exportArchive yeniden imzalar); IPA'da
  uyuşmazlık kalırsa iş akışı hata verir.
- **Yeni ad: NOVA Coach**, asistanın adı **NOVA** ("JARVIS" Marvel/Disney markası riskini kaldırır). Uyandırma
  kelimesi "Nova" (eski "Jarvis" de hâlâ anlaşılır). Bundle ID, hedef/tip adları (JarvisCore, JarvisFit) ve
  abonelik ürün kimlikleri değişmedi. **App Store Connect'teki uygulama adı elle "NOVA Coach" yapılmalı.**
- **Yeni tasarım:** derin uzay zemin + mor bulutsu ışıltı, "nova lime" vurgu rengi, geniş (expanded) başlık
  yazısı, degrade kartlar, kapsül butonlar, yıldız çekirdekli yeni durum küresi, NOVA logotipi, Bugün ekranında
  selamlama başlığı. Yeni ikon: `tools/brand/make_icon.py`.
- **Antrenman sesleri:** tekrar "blip"i, geri sayım tıkı, "başla" tonu, set ve antrenman bitiş melodisi + haptik
  (`CueSound` JarvisCore'da, 4 test; Ayarlar › Kamera ve bildirimler'den kapatılabilir). ❌ Cihazda dinlenmedi.


## Özet

| Alan | Durum | Doğrulama |
|---|---|---|
| JarvisCore (platformdan bağımsız mantık) | ✅ Tamam | 107 otomatik test (1 atlanan: gerçek kayıt fixture'ı yok), Windows'ta (Swift 6.4) geçti |
| Canlı antrenör algoritmaları (10 hareket) | ✅ Kod + sentetik testler | ⚠️ Gerçek kullanıcı verisiyle doğrulanmadı → poz kayıt aracı hazır |
| Eller serbest oturum motoru | ✅ Kod + uçtan uca simülasyon testi | ⚠️ Cihazda doğrulanmadı |
| Poz kaydı + tekrar oynatma (gerçek veriyle doğrulama) | ✅ Kod + testler | Kullanıcı kaydı bekleniyor |
| Hafif mod (eski cihaz / ısı / düşük güç) | ✅ Politika + testler, kamera entegrasyonu | ❌ iPhone 12/13'te ölçülmedi |
| iOS uygulaması (SwiftUI) | ✅ Kod | ✅ Xcode 26.3 ile derlendi, 6 uygulama testi geçti |
| Kamera + Vision poz | ✅ Kod | ❌ Cihaz testi gerekli |
| Ses (STT/TTS, AEC, araya girme) | ✅ Kod | ❌ Cihaz testi gerekli |
| Ses kalitesi (cinsiyete göre ses, EQ/kompresör, okunuş hazırlığı, 48 kHz) | ✅ Kod + testler (`SpeechText`) | ❌ Cihazda dinlenmeli — ayrıntı `docs/VOICE.md` |
| Özel erkek sesler (Piper/ONNX, TR + EN, cihazda) | ✅ Eğitildi, PC'de Whisper CER TR %1,2 / EN %0,2; `voices-v1` yayında, TestFlight'ta | ❌ Cihaz testi |
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
| CI (GitHub Actions) | ✅ ci.yml, testflight.yml | ✅ macOS derleme + testler yeşil |
| TestFlight | ✅ 1.0 (103) yüklendi | Apple işleme süresi sonrası iç testte |

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

Tamamlananlar (2026-11-05): depo `niinova22-blip/jarvis-fit` (public), CI yeşil (iOS derleme + 6 uygulama testi +
85 çekirdek testi), secrets (yeni API anahtarı "JARVIS FIT GitHub CI", Admin, key BCH7KLCAZ4), bundle ID
`com.niinova.jarvisfit`, App Store Connect kaydı "JARVIS FIT" (Türkçe, SKU jarvisfit2026). TestFlight preflight geçiyor.

**TestFlight: ✅ 1.0 (103) yüklendi** (2026-11-06, run 42124407071). İç test grubu "JARVIS FIT Internal" oluşturuldu,
ekip üyeleri eklendi. En eski Apple Distribution sertifikası (M7S64Z7B66) kullanıcının onayıyla iptal edildi; her
çalıştırma geçici sertifikasını sonunda siliyor, slot sonraki çalıştırmalar için boş kalıyor.
Yeni sürüm: `gh workflow run TestFlight -R niinova22-blip/jarvis-fit`.

## Sonraki adımlar (öncelik sırası)

> **Test aşaması:** `AppModel.testPhaseUnlocked = true` → tüm Premium özellikler açık. App Store sürümünden önce `false` yapılmalı.

1. Gerçek cihazda Canlı Antrenör doğrulaması: poz kayıtlarını topla, etiketle, `Fixtures/`'a koy, eşikleri ayarla.
2. App Store Connect'te abonelik ürünleri (`com.niinova.jarvisfit.premium.monthly` 12,99 USD,
   `...yearly` 79,99 USD), gizlilik politikası URL'si (docs/privacy.html barındırılmalı).
3. App Store adı/marka kontrolü (bkz. RESEARCH.md › Riskler).
4. Ses: özel erkek sesler (TR george, EN michael) **eğitildi** (2026-11-07; Whisper CER TR %1,2, EN %0,2),
   GitHub sürümü `voices-v1` yayında, TestFlight'a yüklendi (run 42410223963). Kalan: cihazda dinleme, ilk ses
   gecikmesi, bellek ve pil ölçümü (Ayarlar'da "JARVIS · Özel ses" görünmeli).
   Ayrıntı: `docs/VOICE.md` › Özel ses hattı.
