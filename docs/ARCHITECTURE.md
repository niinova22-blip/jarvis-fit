# Architecture

```
SPOR/
├─ Packages/JarvisCore/        Platform-independent logic (Foundation only; builds on macOS/Linux/Windows)
│  ├─ Pose/                    Joint model, geometry, One-Euro smoothing
│  ├─ Exercises/               RepCounter (hysteresis state machine), 10 exercise specs, plank timer,
│  │                           form issues, rule-based exercise recognizer
│  ├─ Coach/                   FramingGuide, WorkoutSessionEngine (hands-free state machine),
│  │                           CoachCue + CoachVoice (personality phrasebook TR/EN), Safety
│  ├─ Voice/                   IntentParser (TR/EN commands), ResponseComposer, DailyBriefing, PromptBuilder
│  ├─ Planner/                 UserProfile, ExerciseLibrary (46 exercises), WorkoutPlanner, Progression, ScheduleRules
│  ├─ Nutrition/               FoodDatabase (~95 foods), NutritionCalculator, MealParser (voice), FoodLogEntry
│  ├─ FitCheck/                Silhouette → circumference estimator with ranges + calibration, posture
│  ├─ Adaptive/                AdaptiveEngine (explainable recommendations)
│  └─ Memory/                  MemoryItem + extractor (data minimisation)
├─ JarvisFit/                  iOS app (SwiftUI, iOS 17+)
│  ├─ App/                     AppModel (state + persistence), AppData (JSON, complete file protection)
│  ├─ Services/                CameraPoseService (AVCapture + Vision), VoiceCoordinator (Speech + TTS on one
│  │                           AVAudioEngine with voice processing), LanguageModelService (Foundation Models),
│  │                           JarvisAssistant, VisionAnalyzers (food, body scan), SubscriptionManager, Notifications
│  ├─ Features/                Onboarding, Dashboard, LiveWorkout, Workout plan, Nutrition, FitCheck, Progress,
│  │                           Chat, Settings, Paywall
│  └─ DesignSystem/            Theme, JarvisOrb, components
├─ JarvisFitTests/             App-level unit tests
├─ project.yml                 XcodeGen spec (the .xcodeproj is generated in CI)
└─ .github/workflows/          ci.yml (Linux core tests + macOS simulator build/tests), testflight.yml
```

## Live Coach pipeline (independent of the language model)

```
AVCaptureSession (30 fps, 720p, portrait, unmirrored)
  → VNDetectHumanBodyPoseRequest (drop frames while busy; 15 fps under thermal pressure)
  → PoseFrame (19 joints, normalised, top-left origin)
  → WorkoutSessionEngine.process
       PoseSmoother (One-Euro) → FramingGuide (positioning) / ExerciseAnalyzer (active set)
       → RepCounter events, form issues, plank timer, recognizer check
  → [CoachCue] → CoachVoice (pre-written phrases) → VoiceCoordinator.say (priority queue)
Timer 10 Hz → engine.tick (countdown, rest, inactivity auto-finish, lost tracking)
Speech (on-device SFSpeechRecognizer) → IntentParser → engine.handle(command) / ResponseComposer / LLM
```

Hands-free flow: positioning (framing must be "ready" for 1 s) → spoken 3-2-1 → set → auto-finish
(target reached, "bitti/done", or 10 s inactivity) → rest countdown → next set/exercise → summary.

## Key decisions

- **Rule-based, testable core**: rep counting, planning, nutrition and adaptation are deterministic
  and unit-tested; the LLM is only used for open conversation.
- **Echo handling**: TTS is rendered with `AVSpeechSynthesizer.write` into a player node of the same
  `AVAudioEngine` whose input has voice processing (AEC) enabled; additionally, while JARVIS speaks only
  barge-in words are accepted.
- **Honesty**: every estimate (calories, measurements) is labelled; form aspects a single 2D camera
  cannot judge are listed per exercise (`unassessableFormAspects`) and never corrected.
- **Privacy**: no server. Data is a single JSON file with `completeFileProtection`; memory stores
  short facts only; the user can view/delete memory and all data.
