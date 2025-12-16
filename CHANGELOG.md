# Zumu iOS SDK Changelog

## [Latest] - December 16, 2025

### 🔧 Critical Threading Fixes
- **Fixed MutexWrapper EXC_BREAKPOINT crash** - Added `@MainActor` annotations to prevent concurrent access
- **Fixed UI not switching to translation view** - Reverted to using `session.isConnected` directly instead of manual polling
- **Thread-safe session lifecycle** - All `@State` variable access now runs on main thread
- **Concurrent access protection** - Added `isCleaningUp` flag to prevent race conditions
- **Proper LiveKit observation** - SwiftUI observes LiveKit's published properties automatically (no manual state tracking needed)

### ✨ Major Improvements
- **Proper Session initialization** - Session now created with complete `SessionOptions` including `RoomOptions`
- **Fresh session per conversation** - Each SDK open creates new session (no caching/reuse)
- **Complete cleanup lifecycle** - Proper session teardown prevents memory leaks
- **Connection state monitoring** - Manual tracking of `isConnected` with 100ms polling

### 🎵 Audio Improvements
- **Comprehensive audio diagnostics** - Detailed logging for AVAudioSession, AudioManager, mixer, and tracks
- **Force audio configuration** - AudioManager settings enforced at connection and after connection
- **Track volume management** - Agent audio track volume forced to maximum
- **Speaker output preferred** - Automatically switches to speaker for better audio quality

### 🆕 New Features
- **TranscriptView component** - Display message history with clean UI
- **Auto-start connection** - Session automatically connects 500ms after creation
- **Better error handling** - Separate error handling for session, agent, and media
- **Loading states** - Clean loading UI while session initializes

### 🐛 Bug Fixes
- **Session reuse bug** - Fixed crash when opening/closing SDK multiple times
- **Concurrent cleanup** - Prevented concurrent session operations during cleanup
- **State observation** - Fixed SwiftUI not observing Session.isConnected changes
- **Audio playback** - Fixed issues with remote audio track not playing

### 🏗️ Architecture Changes
- **Changed from `@StateObject` to `@State` for session** - Allows fresh instance creation
- **Session created in `onAppear` not `init`** - Ensures clean state per view lifecycle
- **Explicit `@MainActor` on all lifecycle methods** - Prevents threading issues
- **Task blocks use `@MainActor`** - All async operations run on main thread

### 📝 Code Quality
- **Removed AVAudioSession manual management** - Let LiveKit handle audio session
- **Simplified session initialization** - No complex wrappers or custom options
- **Better separation of concerns** - Audio config, cleanup, and lifecycle separate
- **Comprehensive logging** - Detailed logs for debugging session/audio issues

### ⚠️ Breaking Changes
None - All improvements are internal to SDK. Driver apps using the SDK don't need changes.

### 🧪 Testing Recommendations
1. Test multiple open/close cycles - Should not crash
2. Test session.start() after cleanup - Should handle gracefully
3. Test concurrent dismiss actions - Should not deadlock
4. Monitor for MutexWrapper crashes - Should be eliminated

### 📚 Documentation
- See `QUICKSTART.md` for integration guide
- See `SDK_INTEGRATION.md` for detailed setup
- See `INTEGRATION_TROUBLESHOOTING.md` for common issues
- See `UI_IMPROVEMENTS.md` for UI customization

---

## Key Commits

- `3393262` - REVERT: Use session.isConnected directly - remove broken manual polling (WORKING FIX)
- `c073365` - FIX: Use explicit MainActor.run for state updates (superseded by 3393262)
- `f57b245` - FIX: Remove redundant @MainActor annotations (superseded by 3393262)
- `3f2509d` - FIX: Add @MainActor annotations to prevent MutexWrapper crash
- `84b1484` - Update SDK with latest improvements (Dec 16, 2025)
- `51ccb13` - Fix iOS SDK crash with fresh session pattern (Phase 2) - LAST KNOWN WORKING VERSION
- `3f4afc4` - CRITICAL FIX: Remove custom AVAudioSession - let LiveKit handle it

---

## Migration Guide

### For Existing Apps Using Old SDK

**No code changes required!** Simply update your dependency:

```swift
// In Package.swift
.package(url: "https://github.com/Zumu-AI/zumu-ios-sdk.git", from: "1.0.0")
```

Or in Xcode:
1. File → Swift Packages → Update to Latest Package Versions
2. Clean build folder (Cmd+Shift+K)
3. Build and run

The SDK API remains identical - all improvements are internal.

### What You Get

- ✅ No more MutexWrapper crashes
- ✅ Reliable session lifecycle
- ✅ Better audio playback
- ✅ Message transcript history
- ✅ Cleaner UI and loading states

---

## Known Issues

None currently. Previous threading issues and session reuse bugs are resolved.

---

## Support

Issues: https://github.com/Zumu-AI/zumu-ios-sdk/issues
Docs: https://github.com/Zumu-AI/zumu-ios-sdk#readme
