# JARVIS sesi — durum, araştırma ve eğitim planı

## Şu an uygulamada (C — tamamlandı)
- **Cinsiyete göre ses**: erkek kullanıcıya erkek, kadın kullanıcıya kadın ses (`VoiceSelector`, Ayarlar › Ses tipi).
  Belirtmeyen kullanıcıya kadın ses. Önce doğru cinsiyet, sonra kalite (Premium > Gelişmiş > Standart);
  "novelty" sesler ve kullanıcının Kişisel Sesi otomatik seçilmez.
- **Stüdyo ses işleme**: EQ (90 Hz high-pass, 280 Hz −2 dB, 3,5 kHz +2,5 dB, 10 kHz +1,5 dB raf) → kompresör
  (−20 dB eşik, +4 dB kazanç) → çok hafif küçük oda yankısı (%6). Ayarlar'dan kapatılabilir.
- **Kişiliğe göre tonlama**: hız, perde ve cümle arası sessizlik (`VoiceProsody`).
- Daha iyi bir ses indirilebiliyorsa Ayarlar'da yol gösterilir (iOS Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler).
- **Sınır**: iOS'ta Türkçe için erkek sistem sesi olmayabilir (cihazda kontrol edilecek). Yoksa erkek kullanıcıya en iyi
  kadın ses düşer — özel Türkçe erkek ses modeli bu yüzden önemli.

## Açık kaynak araştırması (2026-11-06)

| Kaynak | Dil / cinsiyet | Lisans | Ticari? | Not |
|---|---|---|---|---|
| Commencis TTS Training Turkish Recordings (HF) | TR, 1 kadın + 1 erkek, ~4 sa | CC BY 4.0 | ✅ (atıf) | Erkek konuşmacı stüdyo kaydı; HF'de giriş/onay gerekiyor |
| ISSAI Turkish Speech Corpus | TR, çok konuşmacı, 218 sa | CC BY 4.0 | ✅ (atıf) | Tek, temiz bir konuşmacı seçilmeli |
| Piper `tr_TR-fettah-medium` | TR erkek | Veri CC0 | ✅ | Hazır model, orta kalite |
| Piper `tr_TR-dfki-medium` | TR | CC BY-NC-SA | ❌ | Ticari kullanılamaz |
| Piper `tr_TR-fahrettin` | TR erkek | Doğrulanamadı | ❓ | Kullanılmamalı |
| `piper-tts-tr-ilkiz-medium` | TR kadın | "MIT" etiketi, veri kaynağı yazılmamış | ❓ | Kaynağı belirsiz, kullanılmamalı |
| Piper `en_US-ljspeech` | EN kadın | Kamu malı | ✅ | |
| Piper `en_US-norman` | EN erkek | Kamu malı (LibriVox) | ✅ | |
| Piper `hfc_male/hfc_female` (Hi-Fi-CAPTAIN) | EN | CC BY-NC-SA | ❌ | |
| Kokoro-82M | EN kadın/erkek (28 ses) | Apache 2.0 | ✅ | Çok kaliteli; Türkçe yok |
| XTTS-v2, F5-TTS ağırlıkları | çok dilli | Ticari değil | ❌ | |

**Önemli lisans tuzağı:** Piper/Kokoro çalışma anında genelde `espeak-ng` (GPL-3) ile fonem üretir; GPL kod App Store
uygulamasına konmamalı. Çözüm: espeak-ng yalnızca **eğitimde** (bilgisayarda) kullanılır; uygulamada kendi Türkçe
fonem dönüştürücümüz (Türkçe yazım sese çok yakın) çalışır ve espeak çıktısıyla binlerce cümlede birebir test edilir.
Çalıştırma: ONNX Runtime (MIT).

**İngilizce için öneri:** Apple'ın Premium İngilizce sesleri (ör. kadın/erkek, ücretsiz, cihazda) çok iyi; önce
cihazda dinlenip gerekirse Kokoro (Apache 2.0) eklenir.

## Eğitim planı (bu bilgisayar: RTX 5070 12 GB)
1. **Ortam**: WSL2 + Ubuntu (kullanıcı kurar: `wsl --install -d Ubuntu`, yeniden başlatma), CUDA 12.8 + PyTorch ≥ 2.7
   (RTX 50 serisi için gerekli), Piper eğitim kodu (yalnızca bilgisayarda; model ağırlıkları bizim olur).
2. **Veri**: Commencis erkek + kadın kayıtları (CC BY 4.0; HF'de koşulları kabul etmek gerekiyor); gerekirse ISSAI'den
   tek bir temiz konuşmacı. Ses temizleme, 22,05 kHz, sessizlik kırpma, metin normalizasyonu.
3. **Eğitim**: Türkçe erkek ve kadın için `fettah`/`lessac` ağırlıklarından ince ayar (her ses için tahminen birkaç saat
   ila bir gece). Çıktı: ~30–60 MB ONNX ses modeli (float16).
4. **Uygulama**: Swift Türkçe fonem dönüştürücü + ONNX Runtime ile cihaz üzerinde sentez; mevcut EQ/kompresör zinciri;
   model yoksa sistem sesine geri dönüş. Uygulama içinde lisans/atıf sayfası (CC BY 4.0 gereği).
5. **Değerlendirme**: kör dinleme testi (sistem sesi vs. özel ses), gecikme (<300 ms ilk ses), bellek, pil.

Kalite beklentisi (dürüst): ~2 saatlik veriyle ince ayarlı "medium" Piper sesi temiz ve anlaşılır olur, ancak stüdyo
seslendirme sanatçısı kadar doğal olmaz. Asıl kazanç: Türkçe erkek ses ve uygulamaya özgü bir ses kimliği.
