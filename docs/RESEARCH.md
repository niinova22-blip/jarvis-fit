# Technical research and model selection

All AI runs on device. No paid or cloud AI APIs are used.

## Pose estimation

| Option | License | iOS | Notes | Decision |
|---|---|---|---|---|
| **Apple Vision `VNDetectHumanBodyPoseRequest`** (2D, 19 joints) | Apple SDK (free for App Store apps) | iOS 14+ | Neural Engine accelerated, no model download, good on iPhone 15 Pro | ✅ Used |
| Apple Vision 3D body pose (`VNDetectHumanBodyPose3DRequest`) | Apple SDK | iOS 17+ | Better depth; heavier; single-image | Future: torso lean / depth checks |
| MediaPipe Pose Landmarker (BlazePose) | Apache-2.0 | via MediaPipe Tasks | 33 landmarks incl. feet; extra dependency (~10 MB) | Alternative if Vision accuracy is insufficient for floor exercises |
| MoveNet (TF Lite) | Apache-2.0 | TFLite / Core ML conversion | 17 keypoints, fast | Not needed |

## Speech recognition

| Option | License | Turkish | Decision |
|---|---|---|---|
| **Apple `SFSpeechRecognizer` with `requiresOnDeviceRecognition`** | Apple SDK | Yes, if the on-device model is installed (checked at runtime via `supportsOnDeviceRecognition`) | ✅ Used |
| Apple `SpeechAnalyzer` (iOS 26) | Apple SDK | Language availability varies | Future upgrade for long-form transcription |
| whisper.cpp (Whisper small/base) | MIT (code), MIT (weights) | Good | Heavier (≥150 MB, higher latency/battery); fallback option if Apple on-device Turkish is missing |

## Speech synthesis
Apple `AVSpeechSynthesizer` (TR/EN voices incl. downloadable enhanced/premium voices). Commercial use
allowed. Custom neural TTS (e.g. Piper, MIT; voices have individual licenses) was not added to keep the
binary small; can be evaluated for a branded voice. JARVIS must not imitate the film character's voice.

## Language model

| Option | License | TR quality | Size / latency | Decision |
|---|---|---|---|---|
| **Apple Foundation Models (on-device ~3B)** | Apple developer terms; no extra license | Turkish is among Apple Intelligence languages (verify on device) | No download; low latency on A17 Pro+ | ✅ Used (iOS 26+, Apple Intelligence enabled) |
| Qwen2.5-1.5B/3B-Instruct (MLX / llama.cpp) | Apache-2.0 (1.5B); **3B has a research license** | Good | 1–2 GB, extra memory/battery | Candidate fallback for devices without Apple Intelligence (1.5B) |
| Llama 3.2 1B/3B | Llama 3.2 Community License (commercial with conditions, attribution, 700M MAU limit) | Fair | 0.7–2 GB | Not chosen (license conditions) |
| Gemma 2/3 2B | Gemma Terms of Use (commercial allowed with use policy) | Good | ~1.5 GB | Possible fallback |
| Phi-3.5-mini | MIT | Weak Turkish | 2.2 GB | Not chosen |

Workout commands never depend on the LLM: they are parsed deterministically (`IntentParser`) and
answered from app data (`ResponseComposer`), so they work on every device and offline.

## Food recognition
- **Apple `VNClassifyImageRequest`** (built-in taxonomy, ~1,300 labels incl. many dishes): free,
  on device. ✅ Used, mapped to the local food table; the user confirms items and portion size.
- Food-101-trained models: the Food-101 dataset is for research; commercial use of models trained on it
  needs legal review → not used.
- Nutrition values: USDA FoodData Central (public domain, CC0) rounded per 100 g; Turkish dishes use
  typical recipes (approximate). Shown as estimates.

## Body measurement accuracy (Fit Check)
Published evaluations of smartphone-photo anthropometry report mean errors of a few centimetres for
waist/hip and larger errors for limbs; results depend strongly on clothing, pose and camera position.
The app therefore shows ranges (±7% torso / ±10–12% limbs uncalibrated, ±3–6% after a one-time tape
calibration), only reports changes larger than the error, and never shows single exact centimetres.

## Risks
- **Name/trademark**: "JARVIS" is associated with Marvel's Iron Man. The app does not use the
  character, its voice or UI, but App Store review or a trademark holder could object to the name.
  Consider "Jarvis Fit" as a descriptive brand only after a trademark search, or an alternative name.
- Floor exercises (push-up, plank, bridge, crunch) depend on Vision detecting a lying body; accuracy
  must be measured on device.
- Turkish on-device speech recognition availability differs per device/iOS version.
- Foundation Models availability depends on device, region and the Apple Intelligence setting.
