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

## 2. Ekrana dokunmadan tam antrenman
Telefonu yerleştir → konumlandırma ipuçları → geri sayım → setler → dinlenme → sonraki hareket → özet.
Sesli komutlar: "kaç tekrar kaldı", "dur", "devam", "bitti", "30 saniye daha", "atla", "yoruldum".
Güvenlik: "başım dönüyor" → antrenman durur.

## 3. Ses
- Hoparlörden JARVIS konuşurken mikrofonun kendi sesini komut sanmaması (AEC).
- JARVIS konuşurken "dur" ile araya girme.
- Türkçe çevrimdışı tanıma (Uçak modu açıkken).
- Bluetooth kulaklıkla çalışma.

## 4. Performans (iPhone 15 Pro, 30 dk antrenman)
Instruments ile: pose işleme FPS (hedef ≥25), ses gecikmesi (komut → yanıt < 1,5 sn), bellek (< 300 MB),
pil tüketimi, sıcaklık (thermal state). Eski cihazlar (iPhone 12/13) için hafif mod ihtiyacı.

## 5. Diğer
- Foundation Models: iOS 26 + Apple Intelligence açıkken Türkçe yanıt kalitesi.
- Yemek fotoğrafı: 50 farklı tabakta ilk 3 adayda doğru yemek oranı.
- Fit Check: 5 kişide mezura ile karşılaştırma (bel, kalça, göğüs); hata bandının doğrulanması.
- StoreKit: sandbox/TestFlight satın alma, geri yükleme, iptal, çevrimdışı premium.
