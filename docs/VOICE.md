# JARVIS sesi — durum, araştırma ve eğitim planı

## Şu an uygulamada (C — tamamlandı)
- **Cinsiyete göre ses**: erkek kullanıcıya erkek, kadın kullanıcıya kadın ses (`VoiceSelector`, Ayarlar › Ses tipi).
  Belirtmeyen kullanıcıya kadın ses. Önce doğru cinsiyet, sonra kalite (Premium > Gelişmiş > Standart);
  "novelty" sesler ve kullanıcının Kişisel Sesi otomatik seçilmez.
- **Stüdyo ses işleme**: EQ (90 Hz high-pass, 280 Hz −2 dB, 3,5 kHz +2,5 dB, 10 kHz +1,5 dB raf) → kompresör
  (−20 dB eşik, +4 dB kazanç) → çok hafif küçük oda yankısı (%6). Ayarlar'dan kapatılabilir.
- **Kişiliğe göre tonlama**: hız, perde ve cümle arası sessizlik (`VoiceProsody`).
- **Okunuş hazırlığı** (`SpeechText`, JarvisCore, 12 test): her cümle seslendirilmeden önce sayılar, birimler
  (g, kg, kcal, sn, g/kg…), saatler, aralıklar (60–90), set×tekrar (3x12), yüzdeler, sıra sayıları (2. set / 2nd) ve
  ondalıklar (1,5 → "bir buçuk") yazıya çevrilir; markdown, liste işaretleri ve emoji silinir. Türkçe seste İngilizce
  hareket adları Türkçe okunuşla yazılır (squat → skuat, lunge → lanç, biceps curl → bayseps körl, JARVIS → Carvis).
  Kendi ses modelimiz için de gerekli (sinirsel model rakam/kısaltma okuyamaz).
- **Çıkış 48 kHz** (önceden 22,05 kHz, üst frekanslar kesiliyordu). Ayarlar'da sesin kendi örnekleme hızı
  görünür; gerçek etkisi cihazda dinlenmeli.
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

## Karar (2026-11-06)
Şimdilik **Apple sesleri + C iyileştirmeleri** (build 105). Özel ses eğitimi ertelendi.
- Commencis veri seti Hugging Face'ten kaldırılmış (404).
- ISSAI TSC indirildi ve incelendi: 179.258 kayıt / ~208 saat ama **16 kHz**, TV/yayın kaynaklı kendiliğinden konuşma,
  konuşmacı bilgisi yok. Tek bir konuşmacıyı ayıklayıp eğitmek tanınabilir gerçek bir kişinin sesini izinsiz kopyalamak
  olur → yapılmamalı. Mümkün olan tek temiz yol: çok konuşmacılı model + ortalama (gerçek kişiye ait olmayan) ses; 16 kHz
  ve gürültü yüzünden kalite beklentisi düşük.
- Gerçek kalite artışı için önerilen yol: kendi kaydımız (bir erkek + bir kadın, ~1.500 cümle, 44 kHz).
- Hazır ortam: WSL2 Ubuntu, `/root/voice/.venv` (PyTorch 2.11 + CUDA 12.8, RTX 5070 doğrulandı, `tools/voice/setup_env.sh`),
  ISSAI açılmış hâlde `/root/voice/data/ISSAI_TSC_218` (25 GB).

## Öğretmen model yolu (2026-11-06/07) — gerçek kişiye ait olmayan Türkçe erkek ses
Gerçek bir kişinin sesini kopyalamadan Türkçe erkek ses elde etmek için:
1. Kokoro-82M (Apache 2.0) ile yapay İngilizce erkek sesler üretilir (`tools/voice/make_samples.py en`).
2. Chatterbox Multilingual (MIT) bu yapay sesi referans alıp aynı tınıyla Türkçe konuşur (`make_samples.py tr`).
   Ortam: `tools/voice/setup_teachers.sh` (WSL, `/root/voice/.venv-kokoro`, `.venv-chatterbox`).
3. Seçilen sesle binlerce Türkçe cümle üretilir, Whisper ile anlaşılırlığı düşük olanlar elenir, bu veriyle Piper
   modeli eğitilir (aşağıdaki plan, adım 3–5).

**Anlaşılırlık ölçümü** (2026-11-07, `tools/voice/asr_check.py`, Whisper large-v3-turbo, 1 test cümlesi; sayılar
yazıya çevrilerek karşılaştırılır):

| Ses | Karakter hata oranı | Hata |
|---|---|---|
| am_michael | %0,0 | — |
| bm_george | %0,0 | — |
| am_fenrir | %0,6 | "Sırzını" |
| am_onyx | %0,6 | "Sıvtını" |
| bm_fable | %0,6 | "antrenmanım" |
| am_puck | %2,2 | "antrenmanım", "üst et" |

Bu yalnızca anlaşılırlık; doğallık ve İngiliz aksanı dinleyerek değerlendirilmeli. Örnekler:
`\\wsl.localhost\Ubuntu\root\voice\samples`.

**Seçim (2026-11-07, kullanıcı):** Türkçe = `bm_george` tınısı (Chatterbox), İngilizce = Kokoro `am_michael`.

## Özel ses hattı (2026-11-07)
| Adım | Araç | Durum |
|---|---|---|
| Cümleler: Common Voice (CC0) + uygulama metinleri + antrenör kalıpları, fonem çifti kapsamasına göre seçim | `build_corpus.py` | ✅ TR 1.383, EN 1.369 cümle |
| Ses üretimi (TR Chatterbox/george, EN Kokoro/michael), 22,05 kHz, kırpma, seviye eşitleme | `generate_dataset.py` | ✅ EN; TR sürüyor |
| Whisper ile yanlış okunan kayıtları eleme (CER > %8) | `filter_dataset.py` | ✅ EN 1.360 kayıt / 1,15 sa |
| Fonemler: kendi dönüştürücümüz (espeak yok); Python ve Swift birebir aynı (1.215 satırlık altın dosya testi) | `phonemes.py`, `Phonemizer.swift` | ✅ |
| Eğitim ortamı (piper1-gpl, yalnızca bilgisayarda) | `setup_piper.sh` | ⏳ kullanıcı onayı gerekli |
| İnce ayar: LJ Speech medium (kamu malı) checkpoint'inden, `phoneme_type text` | `train_voice.sh` | ⏳ |
| Uygulama: ONNX Runtime ile cihazda sentez, cümle cümle; erkek ses istendiğinde kullanılır, yoksa Apple sesi | `NeuralVoice.swift` | ✅ CI'da derleniyor; model bekliyor |
| Dağıtım: modeller GitHub sürümü `voices-v1` dosyası olarak; CI/TestFlight indirir | iş akışları | ✅ adım hazır |

Neden fettah/dfki checkpoint'i değil: dfki ticari kullanıma kapalı (CC BY-NC-SA), fettah'ın checkpoint'i yok. Piper
belgelerine göre farklı dilden ince ayar işe yarıyor; LJ Speech verisi kamu malı.

## Eğitim planı (ileride; bu bilgisayar: RTX 5070 12 GB)
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
