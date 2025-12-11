# Zumu Translator iOS SDK - Integration Guide

## Overview

The Zumu Translator SDK provides **two UI components** for integrating real-time voice translation into your iOS app:

1. **Your Button** - You add a button to your UI
2. **Agent Screen** - The SDK provides the translation interface

### Integration Flow

```
┌─────────────────────────────────┐
│  Your App UI                    │
│  ┌───────────────────────────┐  │
│  │  Your Button              │  │ ← You provide this
│  │  "Start Translation"      │  │
│  └───────────────────────────┘  │
└─────────────────┬───────────────┘
                  │ User taps button
                  │ You pass variables to SDK
                  ▼
┌─────────────────────────────────┐
│  Zumu Translator SDK            │
│  ┌───────────────────────────┐  │
│  │  Agent Screen             │  │ ← SDK provides this
│  │  • Audio visualizer       │  │
│  │  • Microphone control     │  │
│  │  • Disconnect button      │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

## Quick Start (5 Minutes)

### 1. Clone the SDK Repository

```bash
git clone https://github.com/Zumu-AI/zumu-ios-sdk.git
cd zumu-ios-sdk
open ZumuTranslator.xcodeproj
```

**Important**: Swift Package Manager is not supported due to LiveKit's complex binary dependencies (WebRTC framework) and swift-protobuf submodule issues. Use manual integration instead.

### 2. Add SDK Files to Your Project

You have two integration options:

#### Option A: Copy SDK Files (Recommended)

Copy these folders into your Xcode project:

1. **Required Core SDK Files**:
   - `ZumuTranslator/SDK/` → Contains main SDK public API
   - `ZumuTranslator/TokenSources/` → Backend integration
   - `ZumuTranslator/Media/` → Audio visualization components
   - `ZumuTranslator/ControlBar/` → UI controls
   - `ZumuTranslator/Interactions/` → Interaction views
   - `ZumuTranslator/Helpers/` → Utilities and extensions
   - `ZumuTranslator/App/` → Core view components

2. **Required Support Files**:
   - `ZumuTranslator/Assets.xcassets` → UI assets
   - `ZumuTranslator/Info.plist` → Permissions configuration
   - `ZumuTranslator/Localizable.xcstrings` → Localization

3. **Add LiveKit Dependencies**:
   - In your project: File → Add Package Dependencies...
   - Add: `https://github.com/livekit/client-sdk-swift.git` (v2.0+)
   - Add: `https://github.com/livekit/components-swift.git` (v0.1.6+)

#### Option B: Build as Framework

1. Open `ZumuTranslator.xcodeproj`
2. Build the ZumuTranslator target as a framework
3. Link the built framework to your app
4. Embed the framework in your app bundle

### 3. Import the SDK

```swift
import ZumuTranslator
```

### 4. Add Translation Button to Your UI

#### SwiftUI Integration

```swift
import SwiftUI
import ZumuTranslator

struct YourView: View {
    @State private var showTranslation = false

    var body: some View {
        // Your existing UI...

        Button("Start Translation") {
            showTranslation = true
        }
        .fullScreenCover(isPresented: $showTranslation) {
            ZumuTranslatorView(
                config: ZumuTranslator.TranslationConfig(
                    driverName: "John Smith",
                    driverLanguage: "English",
                    passengerName: "Maria Garcia",
                    passengerLanguage: "Spanish"
                ),
                apiKey: "zumu_YOUR_API_KEY"
            )
        }
    }
}
```

#### UIKit Integration

```swift
import UIKit
import ZumuTranslator

class YourViewController: UIViewController {

    @IBAction func startTranslationTapped(_ sender: UIButton) {
        let config = ZumuTranslator.TranslationConfig(
            driverName: "John Smith",
            driverLanguage: "English",
            passengerName: "Maria Garcia",
            passengerLanguage: "Spanish"
        )

        ZumuTranslator.present(
            config: config,
            apiKey: "zumu_YOUR_API_KEY",
            from: self
        )
    }
}
```

That's it! The SDK handles everything else.

## SDK API Reference

### ZumuTranslator.TranslationConfig

Configuration object passed to the SDK:

```swift
public struct TranslationConfig {
    public let driverName: String        // Required: Driver's name
    public let driverLanguage: String    // Required: Driver's language
    public let passengerName: String     // Required: Passenger's name
    public let passengerLanguage: String?  // Optional: Passenger's language (auto-detect if nil)
    public let tripId: String?             // Optional: Unique trip ID (UUID generated if nil)
    public let pickupLocation: String?     // Optional: Pickup address
    public let dropoffLocation: String?    // Optional: Drop-off address

    public init(
        driverName: String,
        driverLanguage: String,
        passengerName: String,
        passengerLanguage: String? = nil,
        tripId: String? = nil,
        pickupLocation: String? = nil,
        dropoffLocation: String? = nil
    )
}
```

### ZumuTranslatorView (SwiftUI)

Main translation interface view:

```swift
public struct ZumuTranslatorView: View {
    public init(
        config: ZumuTranslator.TranslationConfig,
        apiKey: String,
        baseURL: String = "https://translator.zumu.ai"
    )
}
```

**Usage**:
- Present as `.sheet()` for modal presentation
- Present as `.fullScreenCover()` for full-screen presentation
- Use as `NavigationLink` destination

### ZumuTranslator.present() (UIKit)

Present translation interface from UIViewController:

```swift
@MainActor
public static func present(
    config: TranslationConfig,
    apiKey: String,
    baseURL: String = "https://translator.zumu.ai",
    from viewController: UIViewController
)
```

## Supported Languages

- English
- Spanish
- Russian
- Chinese
- Arabic
- Hindi
- Turkish

**To add more languages**: Contact Zumu to ensure backend support, then pass the language name in `driverLanguage` or `passengerLanguage`.

## Configuration Options

### API Key Management

**Development** (Environment Variable):
```swift
let apiKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] ?? "default_key"
```

**Production** (Keychain or Secure Storage):
```swift
let apiKey = KeychainManager.shared.getAPIKey() ?? "default_key"
```

**⚠️ Never commit API keys to version control!**

### Custom Backend URL

```swift
ZumuTranslatorView(
    config: config,
    apiKey: apiKey,
    baseURL: "https://staging.translator.zumu.ai"  // Custom URL
)
```

### Trip Context (Optional but Recommended)

Including trip details improves translation quality:

```swift
ZumuTranslator.TranslationConfig(
    driverName: driver.name,
    driverLanguage: driver.preferredLanguage,
    passengerName: passenger.name,
    passengerLanguage: passenger.preferredLanguage,
    tripId: trip.id,                    // ✅ Recommended
    pickupLocation: trip.pickupAddress,  // ✅ Recommended
    dropoffLocation: trip.dropoffAddress // ✅ Recommended
)
```

## Complete Integration Examples

### Example 1: Ride-Hailing App (SwiftUI)

```swift
import SwiftUI
import ZumuTranslator

struct TripView: View {
    let trip: Trip
    @State private var showTranslation = false

    var body: some View {
        VStack {
            // Your trip UI...
            Text("Trip to \(trip.destination)")
            Text("Driver: \(trip.driver.name)")

            Button(action: { showTranslation = true }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Talk to Driver")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .fullScreenCover(isPresented: $showTranslation) {
            ZumuTranslatorView(
                config: ZumuTranslator.TranslationConfig(
                    driverName: trip.driver.name,
                    driverLanguage: trip.driver.language,
                    passengerName: trip.passenger.name,
                    passengerLanguage: trip.passenger.language,
                    tripId: trip.id,
                    pickupLocation: trip.pickupAddress,
                    dropoffLocation: trip.dropoffAddress
                ),
                apiKey: AppConfig.zumuAPIKey
            )
        }
    }
}
```

### Example 2: Delivery App (UIKit)

```swift
import UIKit
import ZumuTranslator

class DeliveryViewController: UIViewController {

    var delivery: Delivery!

    @IBAction func contactDriverTapped(_ sender: UIButton) {
        let config = ZumuTranslator.TranslationConfig(
            driverName: delivery.driver.name,
            driverLanguage: delivery.driver.preferredLanguage ?? "English",
            passengerName: delivery.customer.name,
            passengerLanguage: delivery.customer.preferredLanguage,
            tripId: delivery.id,
            pickupLocation: delivery.restaurant.address,
            dropoffLocation: delivery.deliveryAddress
        )

        ZumuTranslator.present(
            config: config,
            apiKey: AppConfig.shared.zumuAPIKey,
            from: self
        )
    }
}
```

### Example 3: Simple Integration (No Trip Data)

```swift
import SwiftUI
import ZumuTranslator

struct SimpleView: View {
    @State private var showTranslation = false

    var body: some View {
        Button("Translate") {
            showTranslation = true
        }
        .sheet(isPresented: $showTranslation) {
            ZumuTranslatorView(
                config: ZumuTranslator.TranslationConfig(
                    driverName: "Driver",
                    driverLanguage: "English",
                    passengerName: "Passenger",
                    passengerLanguage: "Spanish"
                ),
                apiKey: "zumu_YOUR_API_KEY"
            )
        }
    }
}
```

## What the SDK Provides

### Agent Screen Features

✅ **Audio Visualization**
- Real-time waveform display when agent speaks
- Microphone level visualization when user speaks

✅ **Translation Context Overlay**
- Shows driver and passenger names
- Shows language pair (e.g., "English ⇄ Spanish")

✅ **Control Bar**
- Microphone toggle (mute/unmute)
- Audio device selector (macOS only)
- Disconnect button

✅ **Agent State Tracking**
- Listening: Agent is waiting for speech
- Processing: Agent is generating translation
- Speaking: Agent is responding

✅ **Automatic Behavior**
- Connects to Zumu backend automatically
- Joins LiveKit room automatically
- Agent joins and starts translating automatically
- Audio routes to speaker automatically
- Dismisses when user taps disconnect

## Requirements

- **iOS**: 17.0+
- **macOS**: 14.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Device**: Physical device recommended (simulator audio is limited)
- **Permissions**: Microphone access (configured automatically by SDK)

## Troubleshooting

### No Audio Output

**Check**:
1. Device volume is up
2. Microphone permissions granted
3. Zumu agent is deployed and running
4. Backend API is accessible

**Enable verbose logging**:
```swift
// In your app before presenting SDK
Logger.logLevel = .debug
```

### Connection Fails

**Check**:
1. API key is valid
2. Network connectivity
3. Backend URL is correct

**Error messages**:
- `HTTP error` → Invalid API key or backend down
- `Missing token` → Backend response format changed
- `Network error` → No internet connection

### Audio Visualizer Not Animating

**Check**:
1. Agent is actually speaking (check console logs)
2. Agent audio track is published
3. LiveKit connection is established

### Build Errors

**"No such module 'ZumuTranslator'"**
- Ensure SDK is properly added to project
- Clean build folder: Product → Clean Build Folder
- Restart Xcode

## Testing the SDK

### 1. Add Test Button to Your App

```swift
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
```

### 2. Run on Physical Device

- Connect iPhone/iPad via USB
- Select device in Xcode
- Build and Run (⌘R)

### 3. Grant Permissions

- Allow microphone access when prompted

### 4. Test Translation

1. Tap your "Test Translation" button
2. Wait for "Translation ready. Start speaking..." message
3. Speak in English
4. Listen for Spanish response
5. Verify audio visualizer animates
6. Tap disconnect button to dismiss

### Expected Console Output

```
🚀 Starting Zumu translation session
   Driver: Test Driver (English)
   Passenger: Test Passenger (Spanish)
✅ Received LiveKit token from Zumu backend
🔗 Connecting to LiveKit...
✅ Connected to room: zumu-org_xxx-session_xxx
🤖 Agent connected
📡 Agent state: listening
```

## Advanced Topics

### Custom Error Handling

```swift
// Monitor SDK errors in your app
NotificationCenter.default.addObserver(
    forName: .zumuTranslationError,
    object: nil,
    queue: .main
) { notification in
    if let error = notification.userInfo?["error"] as? Error {
        // Handle error in your app
        print("Translation error: \(error)")
    }
}
```

### Analytics Integration

```swift
// Track translation sessions
ZumuTranslatorView(config: config, apiKey: apiKey)
    .onAppear {
        Analytics.log("translation_started", parameters: [
            "trip_id": config.tripId,
            "driver_language": config.driverLanguage,
            "passenger_language": config.passengerLanguage
        ])
    }
```

### Custom UI Button Styling

```swift
Button(action: { showTranslation = true }) {
    Label("Talk to Driver", systemImage: "phone.fill")
}
.buttonStyle(.borderedProminent)
.tint(.blue)
.controlSize(.large)
```

## Production Checklist

Before releasing your app:

- [ ] API key stored securely (Keychain, not hardcoded)
- [ ] Error handling implemented
- [ ] Analytics tracking added
- [ ] Tested on multiple devices (iPhone, iPad)
- [ ] Tested in different network conditions
- [ ] Microphone permission description updated in Info.plist
- [ ] Background audio modes configured if needed
- [ ] Version number tracked for SDK updates

## Support

- **Documentation**: Full SDK docs at [GitHub](https://github.com/Zumu-AI/zumu-ios-sdk)
- **Issues**: https://github.com/Zumu-AI/zumu-ios-sdk/issues
- **Email**: support@zumu.ai
- **Example App**: See `ZumuTranslator/Examples/ExampleIntegrationApp.swift`

## What's Next?

After integration is working:

1. **Customize button** - Match your app's design
2. **Add analytics** - Track translation usage
3. **Error handling** - Implement retry logic
4. **User feedback** - Show loading states
5. **Production keys** - Use environment-specific keys

Happy integrating! 🚀
