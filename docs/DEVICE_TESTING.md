# Gerçek cihazda doğrulanması gerekenler

Aşağıdakiler simülatörde veya Windows'ta test edilemez. Sonuçlar ölçülmeden doğruluk/performans iddiası yapılmamalı.

## 1. Canlı Antrenör (öncelik 1)
Her hareket için 3 kişi × 2 kamera açısı × 20 tekrar; elle sayımla karşılaştır.

| Hareket | Önerilen bakış | Ölçülecek | Hedef |
|---|---|---|---|
| Squat | yan / ön | tekrar doğruluğu, sığ tekrar uyarısı, diz içe kaçma (ön) | ≥95% doğru sayım |
| Şınav | yan | sayım, kalça düşmesi/yükselmesi | ≥90% |
| Lunge | yan | sayım (alternatif bacak) | ≥90% |
| Jumping jack | ön | hızlı tempoda sayım | ≥95% |
| Plank | yan | süre doğruluğu, kalça uyarısı | ±2 sn |
| Biceps curl | ön | sayım, dirsek savurma | ≥95% |
| Omuz press | ön | sayım, tam kilitleme | ≥90% |
| Yana açış | ön | sayım, fazla yükseğe kaldırma | ≥90% |
| Glute bridge | yan | sayım | ≥90% |
| Crunch | yan | sayım (beta) | ≥80% |

Ayrıca: yanlış pozitif (dinlenirken sayım olmamalı), kadraja giriş/çıkış, iki kişi kadrajda, düşük ışık.

**Nasıl ölçülür:** Ayarlar › Geliştirici › Poz kayıtları › kaydı aç → antrenman yap → kayıtta her set için
gerçek sayıyı gir. Uygulama doğruluğu gösterir. JSON dosyasını paylaşıp
`Packages/JarvisCore/Tests/JarvisCoreTests/Fixtures/` içine koyunca eşikler gerçek veriyle ayarlanabilir ve
her değişiklik bu kayıtlara karşı otomatik test edilir (görüntü/ses kaydedilmez, yalnızca eklem koordinatları).

## 2. Ekrana dokunmadan tam antrenman
Telefonu yerleştir → konumlandırma ipuçları → geri sayım → setler → dinlenme → sonraki hareket → özet.
Sesli komutlar: "kaç tekrar kaldı", "dur", "devam", "bitti", "30 saniye daha", "atla", "yoruldum".
Güvenlik: "başım dönüyor" → antrenman durur.

## 3. Ses
- Hoparlörden JARVIS konuşurken mikrofonun kendi sesini komut sanmaması (AEC).
- JARVIS konuşurken "dur" ile araya girme.
- Türkçe çevrimdışı tanıma (Uçak modu açıkken).
- Bluetooth kulaklıkla çalışma.
- Ses kalitesi (Ayarlar › Ses › "Kullanılan ses" satırı ad, kalite ve sesin kendi örnekleme hızını gösterir):
  - Türkçe erkek sistem sesi var mı? Yoksa hangi ses seçiliyor?
  - Sesin örnekleme hızı kaç kHz? 22 kHz ise 48 kHz çıkışın etkisi yoktur; daha yüksekse "Ses iyileştirme" açık/kapalı
    karşılaştır.
  - Mikrofon açıkken (eko engelleme devrede) ve kapalıyken ses aynı netlikte mi? (Ses işleme çıkışı düşük hıza
    çekiyor olabilir.)
  - Okunuş: "140 g protein", "2,5 kg", "3x12", "60–90 sn", "saat 19:00'da", "2. set", "%20", "squat / lunge /
    biceps curl / plank" ve "JARVIS" doğru okunuyor mu? Yanlış okunanları `SpeechText` sözlüğüne ekle.
  - Müzik çalarken JARVIS anlaşılıyor mu? (Şu an müzik kısılmıyor, `.mixWithOthers`.)

## 4. Performans (iPhone 15 Pro, 30 dk antrenman)
Instruments ile: pose işleme FPS (hedef ≥25), ses gecikmesi (komut → yanıt < 1,5 sn), bellek (< 300 MB),
pil tüketimi, sıcaklık (thermal state).
Hafif mod (Ayarlar › Performans; ≤4 GB RAM, Düşük Güç Modu, ısınma veya ölçülen < 20 fps'de otomatik):
640p + her 2. kare (15 fps analiz). iPhone 12/13'te tekrar doğruluğu hafif modda ayrıca ölçülmeli
(sentetik testte 0,9 sn'lik jumping jack'ler 15 fps'de doğru sayıldı).

## 5. Diğer
- Foundation Models: iOS 26 + Apple Intelligence açıkken Türkçe yanıt kalitesi.
- Sesli onboarding: "30 yaşındayım, boyum 1,78, 82 kilo", "pazartesi çarşamba cuma akşam yedide" gibi cevaplar.
- Yemek fotoğrafı: 50 farklı tabakta ilk 3 adayda doğru yemek oranı.
- Fit Check: 5 kişide mezura ile karşılaştırma (bel, kalça, göğüs); hata bandının doğrulanması.
- StoreKit: sandbox/TestFlight satın alma, geri yükleme, iptal, çevrimdışı premium.

## Her açı / mesafe ve AI sohbet (2026-11-08)
- Her hareketi şu yerleşimlerde 10'ar tekrar yap, sayılanı not et: telefon yerde önde, masada çapraz (~45°),
  1 m yakın (kol hareketleri), 5–6 m uzak, yandan. Pose kaydını aç (Ayarlar › geliştirici) ve kayıtları sakla.
- Hareketsiz 30 sn dur ve şınav pozisyonuna inip kalk: sahte tekrar olmamalı.
- Uzakta (5–6 m) ROI yakınlaştırmanın çalıştığını iskelet çiziminin kişiye oturmasıyla kontrol et.
- Sohbet: spor/beslenme soruları (ör. "kreatin", "göbek yağı", "maç öncesi ne yemeli") cevaplanmalı; "film öner",
  "Python", "hava durumu" sorularına sabit red cümlesi gelmeli; "merhaba/teşekkürler" reddedilmemeli. Apple
  Intelligence kapalı bir cihazda yerleşik cevapları dene.

