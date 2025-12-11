# Zumu iOS SDK - Integration Troubleshooting Guide

## 🚨 Common Integration Errors

### Error 1: "Type 'ShapeStyle' has no member 'fgAccent'" (Style.swift)

**Symptoms**:
```
Style.swift:28:26 Type 'ShapeStyle' has no member 'fgAccent'
Style.swift:40:38 Type 'ShapeStyle' has no member 'fgAccent'
Style.swift:40:94 Type 'ShapeStyle' has no member 'fg4'
```

**Root Cause**: Missing `Assets.xcassets` folder. Custom colors are defined there.

**Solution A: Copy Assets Folder (Recommended)**

1. Copy `ZumuTranslator/Assets.xcassets` folder to your project
2. Make sure it's added to your target (check Target Membership in File Inspector)
3. Rebuild

**Solution B: Use Standard Colors (Quick Fix)**

Replace `ZumuTranslator/Helpers/Style.swift` with this version that uses standard SwiftUI colors:

```swift
import SwiftUI

extension CGFloat {
    /// The grid spacing used as a design unit.
    static let grid: Self = 4

    #if os(visionOS)
    /// The corner radius for the platform-specific UI elements.
    static let cornerRadiusPerPlatform: Self = 11.5 * grid
    #else
    /// The corner radius for the platform-specific UI elements.
    static let cornerRadiusPerPlatform: Self = 2 * grid
    #endif

    /// The corner radius for the small UI elements.
    static let cornerRadiusSmall: Self = 2 * grid

    /// The corner radius for the large UI elements.
    static let cornerRadiusLarge: Self = 4 * grid
}

struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .background(.blue.opacity(configuration.isPressed ? 0.75 : 1))  // ✅ Standard color
            .cornerRadius(8)
    }
}

struct RoundButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .background(isEnabled ? .blue.opacity(configuration.isPressed ? 0.75 : 1) : .gray.opacity(0.4))  // ✅ Standard colors
            .clipShape(Circle())
    }
}

struct ControlBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    var isToggled: Bool = false
    let foregroundColor: Color
    let backgroundColor: Color
    let borderColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isEnabled ? foregroundColor.opacity(configuration.isPressed ? 0.75 : 1) : borderColor)
            .background(
                RoundedRectangle(cornerRadius: .cornerRadiusPerPlatform)
                    .fill(isToggled ? backgroundColor : .clear)
            )
    }
}

struct BlurredTop: ViewModifier {
    func body(content: Content) -> some View {
        content.mask(
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black, .black]),
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.2)
            )
        )
    }
}

struct Shimmering: ViewModifier {
    @State private var isShimmering = false

    func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    colors: [
                        .black.opacity(0.4),
                        .black,
                        .black,
                        .black.opacity(0.4),
                    ],
                    startPoint: isShimmering ? UnitPoint(x: 1, y: 0) : UnitPoint(x: -1, y: 0),
                    endPoint: isShimmering ? UnitPoint(x: 2, y: 0) : UnitPoint(x: 0, y: 0)
                )
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isShimmering)
            )
            .onAppear {
                isShimmering = true
            }
    }
}

extension View {
    func blurredTop() -> some View {
        modifier(BlurredTop())
    }

    func shimmering() -> some View {
        modifier(Shimmering())
    }
}
```

---

### Error 2: "Incorrect argument label in call (have 'token:', expected 'from:')" (ZumuTokenSource.swift)

**Symptoms**:
```
ZumuTokenSource.swift:48:35 Incorrect argument label in call (have 'token:', expected 'from:')
ZumuTokenSource.swift:48:43 Argument type 'String' does not conform to expected type 'Decoder'
```

**Root Cause**: Using old version of `ZumuTokenSource.swift` that has incorrect `TokenSourceResponse` initialization.

**Solution**: Update `ZumuTokenSource.swift` to latest version

Your `ZumuTokenSource.swift` should look like this at line 46-52:

```swift
public func fetch(_ options: TokenRequestOptions) async throws -> TokenSourceResponse {
    let (serverURL, token) = try await fetchTokenAndURL()
    return TokenSourceResponse(
        serverURL: serverURL,
        participantToken: token
    )
}
```

**If your code looks different**, re-copy the file from the latest SDK:

```bash
# In your project directory
cd path/to/zumu-ios-sdk
git pull origin main
cp ZumuTranslator/TokenSources/ZumuTokenSource.swift path/to/your-project/ZumuSDK/TokenSources/
```

---

## 📋 Complete Integration Checklist

When copying SDK files to your project, ensure you copy **ALL** of these:

### ✅ Required Source Folders
- [ ] `ZumuTranslator/SDK/`
- [ ] `ZumuTranslator/TokenSources/`
- [ ] `ZumuTranslator/Media/`
- [ ] `ZumuTranslator/ControlBar/`
- [ ] `ZumuTranslator/Interactions/`
- [ ] `ZumuTranslator/Helpers/`
- [ ] `ZumuTranslator/App/`

### ✅ Required Asset & Config Files
- [ ] `ZumuTranslator/Assets.xcassets` ← **CRITICAL** (defines custom colors)
- [ ] `ZumuTranslator/Info.plist` ← (microphone permissions)
- [ ] `ZumuTranslator/Localizable.xcstrings` ← (localization)

### ✅ LiveKit Dependencies
- [ ] Added `client-sdk-swift` version **2.10.0**
- [ ] Added `components-swift` version **0.1.6**

---

## 🔍 Verification Steps

### 1. Check Assets Folder

```bash
# In your project, this command should list colors:
find YourProject/ZumuSDK -name "*.colorset" | wc -l
# Should return: 22
```

If it returns 0, you're missing Assets.xcassets.

### 2. Check ZumuTokenSource Version

```bash
# This should show the correct method signature:
grep "func fetch" YourProject/ZumuSDK/TokenSources/ZumuTokenSource.swift
# Should output: public func fetch(_ options: TokenRequestOptions) async throws -> TokenSourceResponse {
```

If you see `public func token()` instead, you have the old version.

### 3. Check SDK Version

```bash
cd path/to/zumu-ios-sdk
git log --oneline -1
# Should show: df933c8 Fix TokenSourceResponse initialization error (or later)
```

If you see an older commit, run `git pull origin main`.

---

## 🚀 Quick Resolution Script

Run this to verify your integration:

```bash
#!/bin/bash

echo "🔍 Checking Zumu SDK Integration..."

# Check Assets
ASSET_COUNT=$(find YourProject/ZumuSDK -name "*.colorset" 2>/dev/null | wc -l | xargs)
if [ "$ASSET_COUNT" -eq 22 ]; then
    echo "✅ Assets.xcassets: Found ($ASSET_COUNT colors)"
else
    echo "❌ Assets.xcassets: Missing (found $ASSET_COUNT, expected 22)"
    echo "   → Copy ZumuTranslator/Assets.xcassets to your project"
fi

# Check TokenSource
if grep -q "func fetch" YourProject/ZumuSDK/TokenSources/ZumuTokenSource.swift 2>/dev/null; then
    echo "✅ ZumuTokenSource: Up to date"
else
    echo "❌ ZumuTokenSource: Outdated"
    echo "   → Re-copy ZumuTranslator/TokenSources/ZumuTokenSource.swift"
fi

# Check SDK version
cd path/to/zumu-ios-sdk
COMMIT=$(git log --oneline -1 | cut -d' ' -f1)
if [ "$COMMIT" != "df933c8" ] && git merge-base --is-ancestor df933c8 HEAD 2>/dev/null; then
    echo "✅ SDK Version: Latest (commit $COMMIT)"
else
    echo "❌ SDK Version: Outdated (commit $COMMIT)"
    echo "   → Run: git pull origin main"
fi
```

---

## 🆘 Still Having Issues?

### Issue: "Cannot find 'ZumuTranslatorView' in scope"

**Solution**: Ensure `ZumuTranslator/SDK/ZumuTranslator.swift` is added to your target.

### Issue: "Module 'LiveKit' not found"

**Solution**: Add LiveKit dependencies via Xcode:
1. File → Add Package Dependencies...
2. Add `https://github.com/livekit/client-sdk-swift` version 2.10.0
3. Add `https://github.com/livekit/components-swift` version 0.1.6

### Issue: Build succeeds but runtime crash

**Check**:
1. Info.plist has `NSMicrophoneUsageDescription`
2. All SDK files are added to the same target
3. LiveKit dependencies are embedded (not just linked)

---

## 📞 Support

If problems persist:

1. Run the verification script above
2. Share output with support team
3. Include Xcode build log: `xcodebuild build 2>&1 | tee build.log`
4. Contact: support@zumu.ai

---

## 📝 Summary

**Most Common Mistakes**:
1. ❌ Copying only Swift files (missing Assets.xcassets)
2. ❌ Using old ZumuTokenSource.swift
3. ❌ Wrong LiveKit dependency versions
4. ❌ Not adding SDK files to app target

**Quick Fix**:
```bash
# 1. Update SDK repository
cd path/to/zumu-ios-sdk
git pull origin main

# 2. Re-copy ALL files (including Assets)
cp -r ZumuTranslator/* path/to/your-project/ZumuSDK/

# 3. Verify in Xcode:
# - Assets.xcassets is blue (folder reference)
# - All files have target checkbox checked
# - Clean build folder (⇧⌘K) and rebuild (⌘B)
```
