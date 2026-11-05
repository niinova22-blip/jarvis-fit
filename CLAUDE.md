# JARVIS FIT — notes for future sessions

- Read `docs/STATUS.md` first: current state, blockers and next steps. Keep it updated.
- Windows dev machine; Swift 6.4 is installed, so `cd Packages/JarvisCore && swift test` runs locally.
  The iOS app (JarvisFit/) only builds on macOS → GitHub Actions (`ci.yml`). XcodeGen generates the project.
- Business logic belongs in `Packages/JarvisCore` (Foundation only, unit-tested). Keep the app layer thin.
- Never claim accuracy/performance that was not measured on a real device (`docs/DEVICE_TESTING.md`).
- TestFlight: `testflight.yml` (manual dispatch), secrets ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY,
  team ML3UZXMU3D, bundle com.niinova.jarvisfit. Signing is created per run by `scripts/asc_signing.py`.
- UI strings are inline TR/EN via `model.t("tr", "en")`; core strings use `LocalizedText`.
