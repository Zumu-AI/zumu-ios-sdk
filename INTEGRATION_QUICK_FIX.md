# Zumu iOS SDK - Integration Quick Fix Guide

## 🚨 Critical Fixes Applied

We've identified and fixed both compilation errors reported by your team:

### 1. ✅ Fixed: Environment KeyPath Type Mismatch (ZumuTranslator.swift:255)

**Issue**: `onDisconnect` environment value was declared `fileprivate` in ControlBar.swift, making it inaccessible from ZumuTranslator.swift.

**Fix**: Changed visibility from `fileprivate` to `internal` (default) in:
- File: `ZumuTranslator/ControlBar/ControlBar.swift:131`
- Change: `fileprivate var onDisconnect` → `var onDisconnect`

### 2. ✅ Fixed: TokenSourceConfigurable Protocol Implementation (ZumuTokenSource.swift:5)

**Issue**: Protocol signature changed in LiveKit SDK 2.10.0. Old signature used `token()`, new requires `fetch(_:)`.

**Fix**: Updated protocol implementation in `ZumuTranslator/TokenSources/ZumuTokenSource.swift`:

```swift
// OLD (broken):
public func token() async throws -> String { ... }

// NEW (fixed):
public func fetch(_ options: TokenRequestOptions) async throws -> TokenSourceResponse {
    let token = try await fetchToken()
    return TokenSourceResponse(token: token)
}

private func fetchToken() async throws -> String { ... }
```

## 📦 Exact LiveKit Dependency Versions (Tested & Working)

These are the **exact versions** used in the working SDK project:

### Required Dependencies

Add these to your Xcode project via **File → Add Package Dependencies...**:

1. **LiveKit Swift SDK**
   - URL: `https://github.com/livekit/client-sdk-swift`
   - **Exact Version**: `2.10.0`
   - Dependency Rule: "Up to Next Major" from 2.10.0

2. **LiveKit Components Swift**
   - URL: `https://github.com/livekit/components-swift`
   - **Exact Version**: `0.1.6`
   - Dependency Rule: "Up to Next Minor" from 0.1.6

### Transitive Dependencies (Auto-Resolved)

These will be automatically resolved by Xcode:
- `WebRTC` → 137.7151.10
- `swift-protobuf` → 1.31.0
- `swift-collections` → 1.2.1
- `swift-crypto` → 3.15.1
- `swift-asn1` → 1.5.0
- `jwt-kit` → 4.13.5

## 🔧 Integration Steps (Updated)

### Step 1: Pull Latest SDK Code

```bash
cd path/to/zumu-ios-sdk
git pull origin main
```

The fixes are now in the `main` branch.

### Step 2: Copy SDK Files to Your Project

Copy these folders from the SDK repository to your Xcode project:

**Required Folders:**
```
ZumuTranslator/SDK/                 ← Main SDK API
ZumuTranslator/TokenSources/        ← Backend integration (FIXED)
ZumuTranslator/Media/               ← Audio visualization
ZumuTranslator/ControlBar/          ← UI controls (FIXED)
ZumuTranslator/Interactions/        ← Interaction views
ZumuTranslator/Helpers/             ← Utilities
ZumuTranslator/App/                 ← Core views
```

**Required Support Files:**
```
ZumuTranslator/Assets.xcassets      ← UI assets
ZumuTranslator/Info.plist           ← Permissions
ZumuTranslator/Localizable.xcstrings ← Localization
```

### Step 3: Add LiveKit Dependencies

In your Xcode project:

1. Select your project in the navigator
2. Select your app target
3. Go to "Frameworks, Libraries, and Embedded Content"
4. Click "+" → "Add Package Dependency..."
5. Add both LiveKit packages with exact versions listed above

### Step 4: Verify Build

Build your project (⌘B). The compilation errors should be resolved.

## ✅ Verification Checklist

After integration, verify:

- [ ] No compilation errors in `ZumuTranslator.swift`
- [ ] No compilation errors in `ZumuTokenSource.swift`
- [ ] No compilation errors in `ControlBar.swift`
- [ ] All SDK files copied successfully
- [ ] LiveKit dependencies resolved (check Package Dependencies in project navigator)
- [ ] Info.plist includes microphone permission description

## 🧪 Test Integration

Use this minimal test code to verify the SDK works:

```swift
import SwiftUI
import ZumuTranslator

struct TestView: View {
    @State private var showTranslation = false

    var body: some View {
        Button("Test Translation") {
            showTranslation = true
        }
        .sheet(isPresented: $showTranslation) {
            ZumuTranslatorView(
                config: ZumuTranslator.TranslationConfig(
                    driverName: "Test Driver",
                    driverLanguage: "English",
                    passengerName: "Test Passenger",
                    passengerLanguage: "Spanish"
                ),
                apiKey: "zumu_YOUR_API_KEY"
            )
        }
    }
}
```

**Expected Result**:
- Code compiles without errors
- Button appears and can be tapped
- Translation interface appears when tapped

## 🆘 Troubleshooting

### "No such module 'ZumuTranslator'"

1. Ensure all SDK files are added to your target (check Target Membership in File Inspector)
2. Clean build folder: Product → Clean Build Folder (⇧⌘K)
3. Restart Xcode

### "Cannot find 'TokenSourceResponse' in scope"

- Ensure LiveKit SDK version is exactly **2.10.0** (not earlier)
- Check Package.resolved file for actual resolved version
- If wrong version, remove and re-add the LiveKit package

### "Module 'LiveKitComponents' not found"

- Ensure LiveKit Components version is exactly **0.1.6**
- Components must be explicitly added as a separate package dependency
- Check it appears in "Package Dependencies" section

### Build Still Fails

If you still see the original errors:
1. Ensure you pulled the latest SDK code (`git pull origin main`)
2. Verify the fixes are present:
   - `ControlBar.swift:131` should NOT have `fileprivate`
   - `ZumuTokenSource.swift:46` should have `func fetch(_ options:...)`
3. Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
4. Restart Xcode and rebuild

## 📞 Support

If issues persist after applying these fixes:

1. Check git commit: Latest should be after 2024-12-11 with fixes
2. Share build log: `xcodebuild build 2>&1 | grep error:`
3. Share Package.resolved: `cat YourProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
4. Contact: support@zumu.ai

## 📋 Summary

**Status**: ✅ Both compilation errors fixed and pushed to `main` branch

**Action Required**:
1. Pull latest SDK code
2. Use exact LiveKit versions: 2.10.0 (client-sdk) and 0.1.6 (components)
3. Follow integration steps above

The SDK is now fully functional and ready for integration.
