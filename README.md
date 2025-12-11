# Zumu Translator iOS SDK

Real-time voice translation iOS SDK powered by LiveKit and Zumu AI agents. Enables seamless driver-passenger communication across language barriers.

## Features

- 🎙️ **Voice-Only Translation**: Real-time bidirectional speech translation
- 🌐 **Multi-Language Support**: English, Spanish, Russian, Chinese, Arabic, Hindi, Turkish
- 📊 **Audio Visualization**: Live waveform display for agent and microphone audio
- 🔄 **Agent State Tracking**: Visual feedback for listening, processing, and speaking states
- 📱 **Native iOS**: Built with SwiftUI for iOS 17.0+, macOS 14.0+

## Requirements

- iOS 17.0+ / macOS 14.0+
- Xcode 15.0+
- Swift 5.9+
- Physical device (for testing audio - simulator has limited capabilities)
- Zumu API key (get from [translator.zumu.ai](https://translator.zumu.ai))

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Zumu-AI/zumu-ios-sdk.git
cd zumu-ios-sdk
```

### 2. Open in Xcode

```bash
open ZumuTranslator.xcodeproj
```

### 3. Configure API Key

Open `ZumuTranslator/ZumuTranslatorApp.swift` and set your API key:

```swift
@main
struct ZumuTranslatorApp: App {
    // TODO: Replace with your Zumu API key
    private static let apiKey = "zumu_YOUR_API_KEY_HERE"
    // ...
}
```

**⚠️ Security Note**: For production apps, store the API key in:
- Keychain for secure storage
- Environment variables
- Configuration file (added to .gitignore)
- Remote configuration service

### 4. Update Bundle Identifier

In Xcode:
1. Select project in navigator
2. Select target "ZumuTranslator"
3. Update Bundle Identifier to your organization's identifier (e.g., `com.yourcompany.zumutranslator`)

## Configuration

### Translation Context

The SDK requires translation context before starting a session. This is captured via the configuration screen.

**Required Parameters:**
- `driverName` (String): Driver's name
- `driverLanguage` (String): Driver's language (e.g., "English", "Spanish")
- `passengerName` (String): Passenger's name
- `passengerLanguage` (String?): Passenger's language (optional - will auto-detect if nil)

**Optional Parameters:**
- `tripId` (String?): Unique trip identifier (auto-generated UUID if not provided)
- `pickupLocation` (String?): Pickup location
- `dropoffLocation` (String?): Drop-off location

### Programmatic Configuration

If you want to bypass the configuration screen and set parameters programmatically:

```swift
@main
struct ZumuTranslatorApp: App {
    private static let apiKey = "zumu_YOUR_API_KEY_HERE"

    @State private var session: Session?
    @State private var config: ZumuTokenSource.TranslationConfig?

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
            if let session = session {
                AppView()
                    .environmentObject(session)
                    .environmentObject(LocalMedia(session: session))
                    .environment(\.translationConfig, config)
            }
        }
    }
}
```

### Environment Variables (Alternative)

You can also configure via environment variables:

```swift
private static let apiKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"] ?? "zumu_default_key"
```

Then set in Xcode Scheme:
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. Add: `ZUMU_API_KEY` = `zumu_YOUR_API_KEY_HERE`

## Usage

### Basic Flow

1. **Launch App** → Configuration screen appears
2. **Enter Translation Context**:
   - Driver name and language
   - Passenger name and language
3. **Tap "Start Translation"** → Connects to Zumu backend
4. **Speak** → Real-time translation begins
5. **Tap "Disconnect"** → Ends session

### Expected Behavior

**Connection:**
```
🚀 Starting Zumu translation session
   Driver: John (English)
   Passenger: Maria (Spanish)
✅ Received LiveKit token from Zumu backend
🔗 Connecting to LiveKit...
✅ Connected to room: zumu-org_xxx-session_xxx
🤖 Agent connected
📡 Agent state: listening
```

**During Translation:**
- Agent listens → User speaks → Agent processes → Agent responds
- Audio visualizer shows waveform when agent speaks
- Microphone visualizer shows waveform when user speaks
- Translation context displayed: "John → Maria" and "English ⇄ Spanish"

## Architecture

### Components

**Token Source (`ZumuTokenSource.swift`)**
- Calls Zumu backend API: `POST /api/conversations/start`
- Returns LiveKit token with room credentials
- Includes translation context in request

**Session Management (`Session` from LiveKit)**
- Manages room connection lifecycle
- Tracks agent state (listening/processing/speaking)
- Handles audio track routing automatically

**UI Components**
- `ConfigurationView`: Pre-session form for translation context
- `AgentView`: Audio visualizer + translation context overlay
- `ControlBar`: Microphone toggle, disconnect button
- `AppView`: Main container with session management

### Data Flow

```
User Input (ConfigurationView)
    ↓
ZumuTokenSource → POST /api/conversations/start
    ↓
LiveKit Token
    ↓
Session.connect(token)
    ↓
LiveKit Room + Zumu Agent
    ↓
Audio Streams (bidirectional)
    ↓
Real-time Translation
```

## API Integration

### Backend Endpoint

**URL**: `https://translator.zumu.ai/api/conversations/start`

**Method**: `POST`

**Headers**:
```
Authorization: Bearer zumu_YOUR_API_KEY
Content-Type: application/json
```

**Request Body**:
```json
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

**Response**:
```json
{
  "livekit": {
    "token": "eyJhbGc...",
    "url": "wss://..."
  }
}
```

### Custom Backend

To use a different backend URL:

```swift
let tokenSource = ZumuTokenSource(
    apiKey: apiKey,
    config: config,
    baseURL: "https://your-custom-backend.com"  // Custom URL
)
```

## Customization

### Supported Languages

Edit `ConfigurationView.swift` to add/remove languages:

```swift
private let supportedLanguages = [
    "English",
    "Spanish",
    "Russian",
    "Chinese",
    "Arabic",
    "Hindi",
    "Turkish",
    "French",  // Add new language
    "German"   // Add new language
]
```

**Note**: Backend must support the language for translation to work.

### UI Customization

**Colors** - Edit color definitions in project
**Fonts** - Modify `.font()` modifiers in views
**Layout** - Adjust spacing/sizing using `.grid` multipliers
**Audio Visualizer** - Configure in `AgentView.swift`:
```swift
BarAudioVisualizer(
    audioTrack: audioTrack,
    agentState: session.agent.agentState ?? .listening,
    barCount: 5,           // Number of bars
    barSpacingFactor: 0.05, // Space between bars
    barMinOpacity: 0.1     // Minimum bar opacity
)
```

## Testing

### Pre-flight Checklist

- [ ] Physical iOS device connected (simulator audio is limited)
- [ ] Valid Zumu API key configured
- [ ] Backend API accessible (`https://translator.zumu.ai`)
- [ ] Microphone permissions granted
- [ ] Zumu agent deployed and running

### Test Procedure

1. **Build & Run** on physical device
2. **Enter Configuration**:
   - Driver: "Test Driver" (English)
   - Passenger: "Test Passenger" (Spanish)
3. **Tap "Start Translation"**
4. **Verify Connection**:
   - Status shows "Translation ready. Start speaking..."
   - Audio visualizer visible
   - Translation context overlay displays
5. **Test Audio**:
   - Speak in English → Listen for Spanish response
   - Check waveform animates when agent speaks
   - Check microphone visualizer shows input levels
6. **Verify Agent State**:
   - Should cycle: listening → processing → speaking → listening
7. **Test Disconnect**: Tap phone icon → Returns to configuration

### Common Issues

**No Audio Output**
- Check device volume is up
- Ensure microphone permissions granted
- Verify agent is deployed and running
- Check backend API is accessible

**Connection Fails**
- Verify API key is valid
- Check network connectivity
- Ensure backend URL is correct
- Check Xcode console for error messages

**Audio Visualizer Not Animating**
- Ensure agent is speaking (check agent state)
- Verify audio track exists (check Session.agent.audioTrack)
- Check LiveKit SDK logs for audio routing issues

## Project Structure

```
ZumuTranslator/
├── ZumuTranslatorApp.swift       # App entry point
├── App/
│   ├── AppView.swift              # Main container view
│   └── ConfigurationView.swift   # Pre-session config form
├── TokenSources/
│   └── ZumuTokenSource.swift     # Backend API integration
├── Media/
│   ├── AgentView.swift            # Audio visualizer + overlay
│   └── LocalMedia.swift           # Microphone management
├── ControlBar/
│   ├── ControlBar.swift           # Audio controls
│   └── ControlBarButtonStyle.swift
├── Interactions/
│   └── VoiceInteractionView.swift # Voice-only UI
├── Helpers/
│   ├── Environment.swift          # Environment values
│   ├── Extensions.swift           # Utility extensions
│   └── ...
└── Info.plist                     # Permissions & config
```

## Permissions

Required permissions configured in `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Zumu Translator needs microphone access for real-time translation</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## Dependencies

**LiveKit Swift SDK**
- Room management and WebRTC
- Audio capture and playback
- Track management

**LiveKit Components**
- `BarAudioVisualizer`: Audio waveform visualization
- `SwiftUIVideoView`: Video rendering (for future avatar support)
- Session management utilities

Dependencies are managed via Swift Package Manager and configured in the Xcode project.

## Production Deployment

### Security Best Practices

1. **API Key Storage**:
   - Move API key to secure storage (Keychain)
   - Never commit API keys to version control
   - Use environment-specific keys (dev/staging/prod)

2. **Network Security**:
   - Ensure HTTPS for all API calls
   - Implement certificate pinning for production
   - Add request timeout handling

3. **Error Handling**:
   - Log errors to crash reporting service
   - Show user-friendly error messages
   - Implement retry logic for network failures

### Build Configuration

Create separate schemes for Dev/Staging/Production:
1. Duplicate existing scheme
2. Set environment variables per scheme
3. Use build configurations for feature flags

### App Store Submission

Before submitting:
- [ ] Update version and build number
- [ ] Test on multiple device types
- [ ] Verify all permissions are described
- [ ] Add App Store screenshots
- [ ] Write App Store description
- [ ] Complete privacy policy

## Support

For issues or questions:
- GitHub Issues: https://github.com/Zumu-AI/zumu-ios-sdk/issues
- Documentation: https://translator.zumu.ai/docs
- Email: support@zumu.ai

## License

[Your License Here]

## Credits

Built on [LiveKit](https://livekit.io/) - Open source WebRTC infrastructure
Based on [agent-starter-swift](https://github.com/livekit-examples/agent-starter-swift) example
