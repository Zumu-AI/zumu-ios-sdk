# Zumu iOS SDK - Quick Start Guide for Engineers

## 🚀 Repository

**GitHub**: https://github.com/Zumu-AI/zumu-ios-sdk

## ✅ What Changed

The iOS SDK has been completely rewritten to fix audio issues. The new implementation is based on LiveKit's proven [agent-starter-swift](https://github.com/livekit-examples/agent-starter-swift) example, which has working audio out of the box.

### Old SDK Issues (Fixed)
- ❌ Audio visualizer showed dummy data (all zeros)
- ❌ Custom AudioRenderer callbacks never fired
- ❌ Missing RoomOptions/ConnectOptions configuration
- ❌ No agent audio playback

### New SDK Features (Working)
- ✅ Real-time audio visualization with BarAudioVisualizer
- ✅ Automatic audio routing via LiveKit Session class
- ✅ Agent audio plays automatically through speaker
- ✅ Agent state tracking (listening/processing/speaking)
- ✅ Voice-only translation UI

## 📱 Getting Started (5 Minutes)

### 1. Clone the Repository

```bash
git clone https://github.com/Zumu-AI/zumu-ios-sdk.git
cd zumu-ios-sdk
```

### 2. Configure API Key

**Option A: Environment Variable (Recommended)**

In Xcode:
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. Click `+` to add: `ZUMU_API_KEY` = `zumu_YOUR_API_KEY_HERE`

**Option B: Hardcode for Testing**

Open `ZumuTranslator/ZumuTranslatorApp.swift` and edit line 17:

```swift
// Change this line:
return "zumu_YOUR_API_KEY_HERE"

// To your actual API key:
return "zumu_iZkF5TngXZs3-HWAVjblozL2sB8H2jPi9sc38JRQvWk"
```

### 3. Open in Xcode

```bash
open ZumuTranslator.xcodeproj
```

### 4. Build & Run

1. Connect a **physical iOS device** (simulator audio is limited)
2. Select your device in Xcode
3. Click Run (⌘R)
4. Grant microphone permissions when prompted

### 5. Test Translation

1. **Enter Configuration**:
   - Driver Name: "Test Driver"
   - Driver Language: "English"
   - Passenger Name: "Test Passenger"
   - Passenger Language: "Spanish"

2. **Tap "Start Translation"**

3. **Speak in English** → Agent responds in Spanish

4. **Verify**:
   - Audio visualizer animates when agent speaks ✅
   - Translation context shows "Test Driver → Test Passenger" ✅
   - Agent state cycles: listening → processing → speaking ✅

## 🔧 How to Customize

### Change Translation Parameters

**File**: `ZumuTranslator/App/ConfigurationView.swift`

```swift
// Add/remove languages
private let supportedLanguages = [
    "English",
    "Spanish",
    "Russian",
    "Chinese",
    "Arabic",
    "Hindi",
    "Turkish",
    "French",   // Add new
    "German"    // Add new
]
```

### Bypass Configuration Screen (Pre-set Parameters)

**File**: `ZumuTranslator/ZumuTranslatorApp.swift`

Replace the entire `init()` method:

```swift
init() {
    // Programmatically set configuration
    let presetConfig = ZumuTokenSource.TranslationConfig(
        driverName: "John Smith",
        driverLanguage: "English",
        passengerName: "Maria Garcia",
        passengerLanguage: "Spanish",
        tripId: "trip_12345",
        pickupLocation: "123 Main St",
        dropoffLocation: "456 Oak Ave"
    )

    _config = State(initialValue: presetConfig)

    let tokenSource = ZumuTokenSource(apiKey: Self.apiKey, config: presetConfig)
    let session = Session(
        tokenSource: tokenSource.cached(),
        options: SessionOptions(
            room: Room(
                roomOptions: RoomOptions(
                    defaultAudioCaptureOptions: AudioCaptureOptions(),
                    defaultAudioPublishOptions: AudioPublishOptions()
                )
            )
        )
    )
    _session = State(initialValue: session)
}

var body: some Scene {
    WindowGroup {
        // Remove the if-else, always show AppView
        if let session = session {
            AppView()
                .environmentObject(session)
                .environmentObject(LocalMedia(session: session))
                .environment(\.translationConfig, config)
        }
    }
}
```

### Change Backend URL

**File**: `ZumuTranslator/TokenSources/ZumuTokenSource.swift`

Change the default baseURL (line 36):

```swift
public init(apiKey: String,
            config: TranslationConfig,
            baseURL: String = "https://your-backend.com") {  // Change here
    // ...
}
```

Or pass it when creating the token source:

```swift
let tokenSource = ZumuTokenSource(
    apiKey: apiKey,
    config: config,
    baseURL: "https://staging.translator.zumu.ai"  // Custom URL
)
```

### Customize Audio Visualizer

**File**: `ZumuTranslator/Media/AgentView.swift`

Edit lines 36-40:

```swift
BarAudioVisualizer(
    audioTrack: audioTrack,
    agentState: session.agent.agentState ?? .listening,
    barCount: 7,              // Change from 5 → More bars
    barSpacingFactor: 0.1,    // Change from 0.05 → More spacing
    barMinOpacity: 0.2        // Change from 0.1 → Brighter minimum
)
```

### Customize UI Colors/Fonts

**Colors**: Edit color definitions in `ZumuTranslator/Assets.xcassets/Colors/`
**Fonts**: Modify `.font()` modifiers in view files
**Layout**: Adjust `.grid` multipliers (1 grid = 8 points)

## 🏗️ Architecture

### Key Components

```
┌─────────────────────────────────────────────────┐
│  ConfigurationView (Pre-session form)           │
│  - Capture driver/passenger names & languages   │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  ZumuTokenSource (Backend API integration)      │
│  POST /api/conversations/start                  │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  LiveKit Session (Room connection)              │
│  - Audio track management                       │
│  - Agent state tracking                         │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  AppView (Main UI)                              │
│  ├─ AgentView (Audio visualizer + overlay)      │
│  └─ ControlBar (Mic toggle + disconnect)        │
└─────────────────────────────────────────────────┘
```

### Data Flow

1. **User Input** → ConfigurationView captures driver/passenger context
2. **Token Request** → ZumuTokenSource calls `POST /api/conversations/start`
3. **Connection** → LiveKit Session connects to room with token
4. **Agent Join** → Python agent joins room automatically
5. **Translation** → Bidirectional audio streams with real-time translation
6. **Visualization** → BarAudioVisualizer shows agent waveform

## 🔑 API Integration

### Backend Endpoint

```
POST https://translator.zumu.ai/api/conversations/start
Authorization: Bearer zumu_YOUR_API_KEY
Content-Type: application/json

{
  "driver_name": "John",
  "driver_language": "English",
  "passenger_name": "Maria",
  "passenger_language": "Spanish",
  "trip_id": "trip_12345",
  "pickup_location": "123 Main St",
  "dropoff_location": "456 Oak Ave"
}
```

### Response

```json
{
  "livekit": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "url": "wss://zumu-livekit.livekit.cloud"
  }
}
```

### Implementation

See `ZumuTranslator/TokenSources/ZumuTokenSource.swift` for full implementation.

## 🐛 Troubleshooting

### No Audio Output

**Check**:
1. Device volume is up
2. Microphone permissions granted (Settings → Zumu Translator)
3. Agent is deployed and running
4. Backend API is accessible (check Xcode console for 200 response)

**Logs to look for**:
```
✅ Received LiveKit token from Zumu backend
✅ Connected to room: zumu-org_xxx-session_xxx
🤖 Agent connected
```

### Connection Fails

**Check**:
1. API key is valid (copy-paste carefully)
2. Network connectivity (WiFi/cellular)
3. Backend URL is correct
4. Xcode console for error messages

**Common errors**:
- `HTTP error` → API key invalid or backend down
- `Missing token` → Backend response format changed
- `Network error` → No internet connection

### Audio Visualizer Not Animating

**Check**:
1. Agent is actually speaking (check console for agent state)
2. `Session.agent.audioTrack` exists (print in AgentView)
3. Agent audio track is published
4. LiveKit SDK logs (enable verbose logging)

**Verify agent state**:
```
📡 Agent state: listening    ← Waiting for user
📡 Agent state: processing   ← Generating translation
📡 Agent state: speaking     ← Agent is speaking (visualizer should animate)
```

### Build Errors

**"No such module 'LiveKit'"**
- Wait for Swift Package Manager to resolve dependencies
- Product → Clean Build Folder
- Close and reopen Xcode

**"Failed to build module 'LiveKitComponents'"**
- Ensure you're using Xcode 15+
- Check Swift version: `xcrun swift --version` (should be 5.9+)

## 📚 Documentation

- **Full README**: [README.md](./README.md)
- **LiveKit Docs**: https://docs.livekit.io/
- **Zumu Backend API**: https://translator.zumu.ai/docs

## 💬 Support

- **GitHub Issues**: https://github.com/Zumu-AI/zumu-ios-sdk/issues
- **Questions**: Ask in #ios-sdk Slack channel
- **Email**: support@zumu.ai

## ✨ Next Steps

After confirming the SDK works:

1. **Integrate into your app**:
   - Copy `ZumuTranslator/TokenSources/ZumuTokenSource.swift`
   - Copy `ZumuTranslator/Media/AgentView.swift`
   - Copy `ZumuTranslator/ControlBar/ControlBar.swift`
   - Adapt UI to match your app's design

2. **Production readiness**:
   - Move API key to Keychain
   - Add error analytics (Sentry, Firebase)
   - Implement retry logic for network failures
   - Add unit tests

3. **Advanced features** (optional):
   - Add chat UI (LiveKit has components)
   - Add video support (uncomment in Environment.swift)
   - Add session recording
   - Add call quality metrics

## 🎉 Success Criteria

The SDK is working correctly when:

- ✅ Configuration screen shows and accepts input
- ✅ Backend API returns 200 with LiveKit token
- ✅ Room connection succeeds
- ✅ Agent joins automatically
- ✅ Audio visualizer animates when agent speaks
- ✅ Microphone visualizer animates when user speaks
- ✅ Agent responds in target language
- ✅ Disconnect button works and returns to config screen

Happy coding! 🚀
