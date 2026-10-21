# Le Bot — iOS

SwiftUI app (iOS 26+). The Xcode project is generated from `project.yml`, so it isn't committed.

```sh
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig   # add SUPABASE_URL / SUPABASE_ANON_KEY
xcodegen generate && open LeBot.xcodeproj
```

- The call animation is a Metal shader (`LeBot/Features/Voice/PixelSun.metal`); first-time builds may need
  `xcodebuild -downloadComponent MetalToolchain`.
- `Packages/LeBotKit` holds shared code: `LeBotCore` (config, Supabase, auth) and `LeBotDesign` (palette, type, components).
- Debug builds offer "Explore without an account" to browse the UI without a backend.
- Tests: `xcodebuild test -scheme LeBot -destination 'platform=iOS Simulator,name=iPhone 18 Pro'` and `swift test` in `Packages/LeBotKit`.
- App icon: `swift scripts/make-app-icon.swift LeBot/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
